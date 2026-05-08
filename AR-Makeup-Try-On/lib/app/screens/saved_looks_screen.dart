import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../utils/app_colors.dart';

// ── TAB ENUM ──────────────────────────────────────────────────────────────────

enum _LooksTab { all, favourites }

// ── SCREEN ────────────────────────────────────────────────────────────────────

class SavedLooksScreen extends StatefulWidget {
  const SavedLooksScreen({super.key});

  @override
  State<SavedLooksScreen> createState() => _SavedLooksScreenState();
}

class _SavedLooksScreenState extends State<SavedLooksScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _savedLooks = [];

  // Local set of favourited look IDs (persisted to Supabase column `is_favourite`)
  final Set<String> _favouriteIds = {};

  _LooksTab _currentTab = _LooksTab.all;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  final String _webBaseUrl =
      'https://tommie-mushy-noumenally.ngrok-free.dev/looks/';

  // ── INIT ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fetchSavedLooks();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── FETCH ──────────────────────────────────────────────────────────────────

  Future<void> _fetchSavedLooks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await Supabase.instance.client
          .from('saved_looks')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final looks = List<Map<String, dynamic>>.from(response);

      // Populate favourites from DB column (if it exists); defaults to false
      for (final look in looks) {
        if (look['is_favourite'] == true) {
          _favouriteIds.add(look['id'] as String);
        }
      }

      setState(() {
        _savedLooks = looks;
        _isLoading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      debugPrint("❌ Error fetching looks: $e");
      setState(() => _isLoading = false);
    }
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  String _formatDate(String isoString) {
    final date = DateTime.parse(isoString).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  List<Map<String, dynamic>> get _visibleLooks {
    if (_currentTab == _LooksTab.favourites) {
      return _savedLooks
          .where((l) => _favouriteIds.contains(l['id'] as String))
          .toList();
    }
    return _savedLooks;
  }

  // ── TOGGLE FAVOURITE ───────────────────────────────────────────────────────

  Future<void> _toggleFavourite(String lookId) async {
    final wasLiked = _favouriteIds.contains(lookId);
    setState(() {
      if (wasLiked) {
        _favouriteIds.remove(lookId);
      } else {
        _favouriteIds.add(lookId);
      }
    });
    // Haptic feedback
    HapticFeedback.lightImpact();
    try {
      await Supabase.instance.client
          .from('saved_looks')
          .update({'is_favourite': !wasLiked}).eq('id', lookId);
    } catch (e) {
      // Revert on failure
      setState(() {
        if (wasLiked) {
          _favouriteIds.add(lookId);
        } else {
          _favouriteIds.remove(lookId);
        }
      });
      debugPrint("❌ Toggle favourite failed: $e");
    }
  }

  // ── APPLY LOOK ─────────────────────────────────────────────────────────────

  Future<void> _applySavedLook(String lookId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
    );
    try {
      final items = await Supabase.instance.client
          .from('saved_look_items')
          .select()
          .eq('look_id', lookId);
      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context, items);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load look details.')),
      );
    }
  }

  // ── DELETE LOOK ────────────────────────────────────────────────────────────

  Future<void> _deleteLook(String lookId) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 26,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Delete Look?',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This look will be permanently removed and cannot be recovered.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border, width: 1.2),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
        false;

    if (!confirm) return;

    try {
      await Supabase.instance.client
          .from('saved_look_items')
          .delete()
          .eq('look_id', lookId);
      await Supabase.instance.client
          .from('saved_looks')
          .delete()
          .eq('id', lookId);
      setState(() {
        _savedLooks.removeWhere((look) => look['id'] == lookId);
        _favouriteIds.remove(lookId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Look deleted.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting look: $e')),
      );
    }
  }

  // ── SHARE / OPEN ACTIONS ───────────────────────────────────────────────────

  Future<void> _shareImage(String imageUrl, String lookName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing image…')),
      );
      final response = await http.get(Uri.parse(imageUrl));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$lookName.jpg');
      await file.writeAsBytes(response.bodyBytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my makeup look: $lookName!',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share image.')),
      );
    }
  }

  Future<void> _openInWeb(String lookId) async {
    final url = Uri.parse('$_webBaseUrl$lookId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the web link.')),
      );
    }
  }

  Future<void> _copyLink(String lookId) async {
    await Clipboard.setData(ClipboardData(text: '$_webBaseUrl$lookId'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Link copied! 📋',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareLink(String lookId, String lookName) async {
    await Share.share(
        'Check out my virtual makeup look "$lookName" here: $_webBaseUrl$lookId');
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── CUSTOM HEADER ────────────────────────────────────────────────
          _buildHeader(topPad),

          // ── BODY ─────────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 1.5,
                    ),
                  )
                : _savedLooks.isEmpty
                    ? _buildEmptyState()
                    : FadeTransition(
                        opacity: _fadeAnim,
                        child: _visibleLooks.isEmpty
                            ? _buildEmptyFavourites()
                            : _buildGrid(),
                      ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(double topPad) {
    final favCount =
        _savedLooks.where((l) => _favouriteIds.contains(l['id'])).length;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 14, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textMain,
                    size: 15,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Looks',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.6,
                      ),
                    ),
                    if (!_isLoading)
                      Text(
                        '${_savedLooks.length} saved  ·  $favCount favourited',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Tab bar
          Row(
            children: [
              _buildTab(_LooksTab.all, 'All Looks', Icons.grid_view_rounded),
              const SizedBox(width: 8),
              _buildTab(
                _LooksTab.favourites,
                'Favourites',
                Icons.favorite_rounded,
                badge: favCount > 0 ? favCount : null,
              ),
            ],
          ),
          const SizedBox(height: 0),
        ],
      ),
    );
  }

  Widget _buildTab(
    _LooksTab tab,
    String label,
    IconData icon, {
    int? badge,
  }) {
    final isSelected = _currentTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textMuted,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.25)
                      : AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── GRID ───────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.62,
      ),
      itemCount: _visibleLooks.length,
      itemBuilder: (context, index) {
        final look = _visibleLooks[index];
        return _buildCard(
          lookId: look['id'] as String,
          lookName: look['look_name'] ?? 'My Look',
          imageUrl: look['preview_image_url'] as String?,
          dateStr: look['created_at'] as String,
          index: index,
        );
      },
    );
  }

  // ── CARD ───────────────────────────────────────────────────────────────────

  Widget _buildCard({
    required String lookId,
    required String lookName,
    required String? imageUrl,
    required String dateStr,
    required int index,
  }) {
    final isFav = _favouriteIds.contains(lookId);

    return GestureDetector(
      onTap: () => _applySavedLook(lookId),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isFav
                ? AppColors.primary.withOpacity(0.30)
                : AppColors.border,
            width: isFav ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isFav
                  ? AppColors.primary.withOpacity(0.08)
                  : Colors.black.withOpacity(0.04),
              blurRadius: isFav ? 18 : 10,
              spreadRadius: isFav ? 2 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image area ───────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Image
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(22)),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: AppColors.background,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 1.5,
                                      value: loadingProgress
                                                  .expectedTotalBytes !=
                                              null
                                          ? loadingProgress
                                                  .cumulativeBytesLoaded /
                                              loadingProgress
                                                  .expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) =>
                                  _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),

                  // Subtle top-right favourite button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _toggleFavourite(lookId),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isFav
                              ? AppColors.primary
                              : Colors.black.withOpacity(0.30),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isFav
                                ? AppColors.primary
                                : Colors.white.withOpacity(0.15),
                            width: 1,
                          ),
                          boxShadow: isFav
                              ? [
                                  BoxShadow(
                                    color:
                                        AppColors.primary.withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // "Apply" label on bottom of image — subtle pill
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.40),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.auto_fix_high_rounded,
                            color: Colors.white,
                            size: 11,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Tap to apply',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Info row ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lookName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textMain,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (isFav) ...[
                              Icon(
                                Icons.favorite_rounded,
                                color: AppColors.primary,
                                size: 9,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _formatDate(dateStr),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Menu
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<int>(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: AppColors.surface,
                      elevation: 6,
                      shadowColor: Colors.black.withOpacity(0.12),
                      onSelected: (value) {
                        switch (value) {
                          case 0:
                            _toggleFavourite(lookId);
                          case 1:
                            if (imageUrl != null)
                              _shareImage(imageUrl, lookName);
                          case 2:
                            _openInWeb(lookId);
                          case 3:
                            _copyLink(lookId);
                          case 4:
                            _shareLink(lookId, lookName);
                          case 5:
                            _deleteLook(lookId);
                        }
                      },
                      itemBuilder: (context) => [
                        _menuItem(
                          0,
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          isFav
                              ? 'Remove Favourite'
                              : 'Add to Favourites',
                          true,
                          isFav ? AppColors.primary : AppColors.textMain,
                        ),
                        const PopupMenuDivider(height: 1),
                        _menuItem(1, Icons.image_outlined, 'Share Image',
                            imageUrl != null, AppColors.textMain),
                        _menuItem(2, Icons.open_in_browser_rounded,
                            'Open in Web', true, AppColors.textMain),
                        _menuItem(3, Icons.copy_rounded, 'Copy Link', true,
                            AppColors.textMain),
                        _menuItem(4, Icons.share_outlined, 'Share Link',
                            true, AppColors.textMain),
                        const PopupMenuDivider(height: 1),
                        _menuItem(5, Icons.delete_outline_rounded,
                            'Delete Look', true, Colors.redAccent),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _menuItem(
    int value,
    IconData icon,
    String label,
    bool enabled,
    Color color,
  ) {
    return PopupMenuItem<int>(
      value: value,
      enabled: enabled,
      height: 42,
      child: Row(
        children: [
          Icon(
            icon,
            color: enabled ? color : AppColors.textMuted.withOpacity(0.4),
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: enabled ? color : AppColors.textMuted.withOpacity(0.4),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── EMPTY STATES ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.primary.withOpacity(0.15), width: 1.5),
            ),
            child: Icon(
              Icons.face_retouching_natural_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Looks Saved Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Try on some makeup and save your\nfavorite combinations here!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: AppColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFavourites() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.primary.withOpacity(0.15), width: 1.5),
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 38,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Favourites Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textMain,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap the ♡ on any look to\nadd it to your favourites.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: AppColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primary.withOpacity(0.06),
      child: Center(
        child: Icon(
          Icons.face_retouching_natural_rounded,
          color: AppColors.primary.withOpacity(0.5),
          size: 36,
        ),
      ),
    );
  }
}