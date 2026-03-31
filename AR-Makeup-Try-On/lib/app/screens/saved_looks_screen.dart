import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../app/utils/app_colors.dart';

class SavedLooksScreen extends StatefulWidget {
  const SavedLooksScreen({super.key});

  @override
  State<SavedLooksScreen> createState() => _SavedLooksScreenState();
}

class _SavedLooksScreenState extends State<SavedLooksScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _savedLooks = [];

  final String _webBaseUrl = 'https://tommie-mushy-noumenally.ngrok-free.dev/looks/';

  @override
  void initState() {
    super.initState();
    _fetchSavedLooks();
  }

  Future<void> _fetchSavedLooks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('saved_looks')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _savedLooks = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching looks: $e");
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(String isoString) {
    final date = DateTime.parse(isoString).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  // ── 1. APPLY LOOK (TAP ON CARD) ──
  Future<void> _applySavedLook(String lookId) async {
    // Loading show karein taake user ko pata chale data fetch ho raha hai
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    try {
      // Fetch items for this look
      final items = await Supabase.instance.client
          .from('saved_look_items')
          .select()
          .eq('look_id', lookId);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.pop(context, items); // Wapis TryOnScreen par jayen data ke sath!
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load look details.')));
    }
  }

  // ── 2. DELETE LOOK ──
  Future<void> _deleteLook(String lookId) async {
    // Confirmation Dialog
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Look?', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this saved look? This cannot be undone.', style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      // Pehle items delete karein (Foreign Key constraint se bachne ke liye)
      await Supabase.instance.client.from('saved_look_items').delete().eq('look_id', lookId);
      // Phir main look delete karein
      await Supabase.instance.client.from('saved_looks').delete().eq('id', lookId);

      setState(() {
        _savedLooks.removeWhere((look) => look['id'] == lookId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Look deleted successfully.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting look: $e')));
    }
  }

  // ── OTHER MENU ACTIONS ──
  Future<void> _shareImage(String imageUrl, String lookName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preparing image...')));
      final response = await http.get(Uri.parse(imageUrl));
      final documentDirectory = await getTemporaryDirectory();
      final file = File('${documentDirectory.path}/$lookName.jpg');
      await file.writeAsBytes(response.bodyBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Check out my makeup look: $lookName!');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to share image.')));
    }
  }

  Future<void> _openInWeb(String lookId) async {
    final url = Uri.parse('$_webBaseUrl$lookId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the web link.')));
    }
  }

  Future<void> _copyLink(String lookId) async {
    final url = '$_webBaseUrl$lookId';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied! 📋')));
  }

  Future<void> _shareLink(String lookId, String lookName) async {
    final url = '$_webBaseUrl$lookId';
    await Share.share('Check out my virtual makeup look "$lookName" here: $url');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Saved Looks', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold, fontSize: 20)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _savedLooks.isEmpty
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  child: GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.65,
                    ),
                    itemCount: _savedLooks.length,
                    itemBuilder: (context, index) {
                      final look = _savedLooks[index];
                      return _buildGalleryCard(look['id'], look['look_name'] ?? 'My Look', look['preview_image_url'], look['created_at']);
                    },
                  ),
                ),
    );
  }

  Widget _buildGalleryCard(String lookId, String lookName, String? imageUrl, String dateStr) {
    return GestureDetector(
      onTap: () => _applySavedLook(lookId), // 🔴 TAP TO TRY ON
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: AppColors.secondary));
                        },
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(lookName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textMain)),
                        const SizedBox(height: 4),
                        Text(_formatDate(dateStr), style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 24, height: 24,
                    child: PopupMenuButton<int>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: AppColors.surface,
                      elevation: 4,
                      onSelected: (value) {
                        switch (value) {
                          case 1: if (imageUrl != null) _shareImage(imageUrl, lookName); break;
                          case 2: _openInWeb(lookId); break;
                          case 3: _copyLink(lookId); break;
                          case 4: _shareLink(lookId, lookName); break;
                          case 5: _deleteLook(lookId); break; // 🔴 DELETE ACTION
                        }
                      },
                      itemBuilder: (context) => [
                        _buildPopupItem(1, Icons.image_outlined, 'Share Image', imageUrl != null, AppColors.textMain),
                        _buildPopupItem(2, Icons.open_in_browser, 'Open in Web', true, AppColors.textMain),
                        _buildPopupItem(3, Icons.copy, 'Copy Link', true, AppColors.textMain),
                        _buildPopupItem(4, Icons.share_outlined, 'Share Link', true, AppColors.textMain),
                        const PopupMenuDivider(),
                        _buildPopupItem(5, Icons.delete_outline, 'Delete Look', true, Colors.redAccent), // 🔴 DELETE MENU ITEM
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

  PopupMenuItem<int> _buildPopupItem(int value, IconData icon, String text, bool enabled, Color color) {
    return PopupMenuItem<int>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, color: enabled ? color : AppColors.textMuted.withOpacity(0.5), size: 20),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: enabled ? color : AppColors.textMuted.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(color: AppColors.secondary.withOpacity(0.3), child: const Center(child: Icon(Icons.face_retouching_natural, color: AppColors.primary, size: 40)));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.secondary.withOpacity(0.5), shape: BoxShape.circle), child: const Icon(Icons.favorite_border, size: 60, color: AppColors.primary)),
          const SizedBox(height: 24),
          const Text('No Looks Saved Yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textMain)),
          const SizedBox(height: 12),
          const Text('Try on some makeup and save your\nfavorite combinations here!', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppColors.textMuted, height: 1.5)),
        ],
      ),
    );
  }
}