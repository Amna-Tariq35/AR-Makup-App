import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;
import 'package:path_provider/path_provider.dart';
import 'package:deepar_flutter/deepar_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../../app/utils/app_colors.dart';
import '../../app/screens/saved_looks_screen.dart';
import '../../app/screens/auth_screen.dart';
import '../../app/screens/profile_screen.dart';

// ── MODELS ───────────────────────────────────────────────────────────────────

class DbShade {
  final String productKey;
  final String shadeKey;
  final String shadeName;
  final String shadeHex;
  final int shadeOrder;

  DbShade({
    required this.productKey,
    required this.shadeKey,
    required this.shadeName,
    required this.shadeHex,
    required this.shadeOrder,
  });

  factory DbShade.fromMap(Map<String, dynamic> map) => DbShade(
    productKey: map['product_key']?.toString() ?? '',
    shadeKey: map['shade_key']?.toString() ?? '',
    shadeName: map['shade_name']?.toString() ?? '',
    shadeHex: map['shade_hex']?.toString() ?? '#000000',
    shadeOrder: (map['shade_order'] as num?)?.toInt() ?? 0,
  );

  Color get color {
    final cleaned = shadeHex.replaceAll('#', '').trim();
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}

class DbLashConfig {
  final String productKey;
  final String baseMaskType;
  final String lashColor;
  final double opacity;
  final double scaleY;
  final double scaleX;

  DbLashConfig({
    required this.productKey,
    required this.baseMaskType,
    required this.lashColor,
    required this.opacity,
    required this.scaleY,
    required this.scaleX,
  });

  factory DbLashConfig.fromMap(Map<String, dynamic> map) => DbLashConfig(
    productKey: map['product_key']?.toString() ?? '',
    baseMaskType: map['base_mask_type']?.toString() ?? 'sexy',
    lashColor: map['lash_color']?.toString() ?? '#000000',
    opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
    scaleY: (map['scale_y'] as num?)?.toDouble() ?? 1.0,
    scaleX: (map['scale_x'] as num?)?.toDouble() ?? 1.0,
  );

  Color get color {
    final cleaned = lashColor.replaceAll('#', '').trim();
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}

// ── ENUMS ────────────────────────────────────────────────────────────────────

enum TryOnCategory {
  eyelashes,
  lipstick,
  lipGloss,
  foundation,
  blush,
  mascara,
  highlighter,
  eyeliner,
  eyeshadow,
}

// ── SCREEN ───────────────────────────────────────────────────────────────────

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen>
    with TickerProviderStateMixin {
  late final DeepArController _deepArController;
  bool _isInitialized = false;
  bool _isSaving = false;

  final String androidKey =
      "2952b3fa8af974da37a4802986a2b95c7383ea2f999dc94e83646b7ecab03d9c68e6232e888e8333";
  final String iosKey = "YAHAN_APNI_IOS_LICENSE_KEY_DALEIN";

  List<DbShade> _allDbShades = [];
  Map<String, DbLashConfig> _lashConfigs = {};
  TryOnCategory _currentCategory = TryOnCategory.lipstick;

  final Map<TryOnCategory, DbShade?> _selectedShades = {
    for (var cat in TryOnCategory.values) cat: null,
  };

  final Map<TryOnCategory, double> _intensities = {
    TryOnCategory.eyelashes: 1.0,
    TryOnCategory.lipstick: 0.7,
    TryOnCategory.lipGloss: 0.6,
    TryOnCategory.foundation: 0.5,
    TryOnCategory.blush: 0.4,
    TryOnCategory.mascara: 1.0,
    TryOnCategory.highlighter: 0.6,
    TryOnCategory.eyeliner: 0.9,
    TryOnCategory.eyeshadow: 0.6,
  };

  late AnimationController _panelController;
  late AnimationController _topBarController;
  late Animation<Offset> _panelSlide;
  late Animation<double> _panelFade;
  late Animation<Offset> _topBarSlide;
  late Animation<double> _topBarFade;

  // ── INIT ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _panelSlide = Tween<Offset>(begin: const Offset(0, 0.22), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
        );
    _panelFade = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOut,
    );

    _topBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _topBarSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _topBarController,
            curve: Curves.easeOutCubic,
          ),
        );
    _topBarFade = CurvedAnimation(
      parent: _topBarController,
      curve: Curves.easeOut,
    );

    _initializeDeepAR();
    _loadDataFromDb();
  }

  @override
  void dispose() {
    if (_isInitialized) _deepArController.destroy();
    _panelController.dispose();
    _topBarController.dispose();
    super.dispose();
  }

  // ── CATEGORY HELPERS ──────────────────────────────────────────────────────

  String _getGameObject(TryOnCategory category) {
    switch (category) {
      case TryOnCategory.lipstick:
      case TryOnCategory.lipGloss:
        return 'Lips';
      case TryOnCategory.blush:
        return 'Blush';
      case TryOnCategory.eyeshadow:
        return 'EyeShadow';
      case TryOnCategory.eyeliner:
        return 'Eyeliner';
      case TryOnCategory.eyelashes:
      case TryOnCategory.mascara:
        return 'EyeLashes';
      case TryOnCategory.foundation:
        return 'Foundation';
      case TryOnCategory.highlighter:
        return 'Highlighter';
    }
  }

  String get _currentPrefix {
    switch (_currentCategory) {
      case TryOnCategory.eyelashes:
        return 'lsh_';
      case TryOnCategory.lipstick:
        return 'lip_';
      case TryOnCategory.lipGloss:
        return 'gloss_';
      case TryOnCategory.foundation:
        return 'fnd_';
      case TryOnCategory.blush:
        return 'blu_';
      case TryOnCategory.mascara:
        return 'mas_';
      case TryOnCategory.highlighter:
        return 'hgl_';
      case TryOnCategory.eyeliner:
        return 'eln_';
      case TryOnCategory.eyeshadow:
        return 'esh_';
    }
  }

  String _getCategoryName(TryOnCategory cat) {
    switch (cat) {
      case TryOnCategory.eyelashes:
        return 'Lashes';
      case TryOnCategory.lipstick:
        return 'Lipstick';
      case TryOnCategory.lipGloss:
        return 'Lip Gloss';
      case TryOnCategory.foundation:
        return 'Foundation';
      case TryOnCategory.blush:
        return 'Blush';
      case TryOnCategory.mascara:
        return 'Mascara';
      case TryOnCategory.highlighter:
        return 'Highlighter';
      case TryOnCategory.eyeliner:
        return 'Eyeliner';
      case TryOnCategory.eyeshadow:
        return 'Eyeshadow';
    }
  }

  IconData _getCategoryIcon(TryOnCategory cat) {
    switch (cat) {
      case TryOnCategory.eyelashes:
        return Icons.remove;
      case TryOnCategory.lipstick:
        return Icons.water_drop_outlined;
      case TryOnCategory.lipGloss:
        return Icons.auto_awesome_outlined;
      case TryOnCategory.foundation:
        return Icons.circle_outlined;
      case TryOnCategory.blush:
        return Icons.blur_circular_outlined;
      case TryOnCategory.mascara:
        return Icons.minimize_rounded;
      case TryOnCategory.highlighter:
        return Icons.flare_outlined;
      case TryOnCategory.eyeliner:
        return Icons.edit_outlined;
      case TryOnCategory.eyeshadow:
        return Icons.palette_outlined;
    }
  }

  List<DbShade> get _currentShades => _allDbShades
      .where((s) => s.productKey.startsWith(_currentPrefix))
      .toList();

  // ── DEEP AR INIT ──────────────────────────────────────────────────────────

  Future<void> _initializeDeepAR() async {
    _deepArController = DeepArController();
    await _deepArController.initialize(
      androidLicenseKey: androidKey,
      iosLicenseKey: iosKey,
      resolution: Resolution.high,
    );
    await _deepArController.switchEffect('assets/effects/makeup.deepar');
    setState(() => _isInitialized = true);
    _panelController.forward();
    _topBarController.forward();
  }

  // ── DB LOAD ───────────────────────────────────────────────────────────────

  Future<void> _loadDataFromDb() async {
    try {
      final shadeRes = await Supabase.instance.client
          .from('product_shades')
          .select()
          .order('shade_order', ascending: true);
      final allFetched = (shadeRes as List<dynamic>)
          .map((e) => DbShade.fromMap(e))
          .toList();
      final uniqueShades = <String, DbShade>{};
      for (var shade in allFetched) {
        final key = '${shade.productKey}_${shade.shadeHex}';
        if (!uniqueShades.containsKey(key)) uniqueShades[key] = shade;
      }
      setState(() => _allDbShades = uniqueShades.values.toList());
    } catch (e) {
      debugPrint("❌ Error loading shades: $e");
    }

    try {
      final lashRes = await Supabase.instance.client
          .from('ar_lash_configs')
          .select();
      final configsMap = <String, DbLashConfig>{};
      for (var row in (lashRes as List<dynamic>)) {
        final config = DbLashConfig.fromMap(row);
        configsMap[config.productKey] = config;
      }
      setState(() => _lashConfigs = configsMap);
    } catch (e) {
      debugPrint("❌ Error loading lash configs: $e");
    }
  }

  // ── ASSET HELPER ─────────────────────────────────────────────────────────

  Future<String> _getAssetPath(String assetName) async {
    final byteData = await rootBundle.load('assets/textures/$assetName');
    final file = File('${(await getTemporaryDirectory()).path}/$assetName');
    await file.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    return file.path;
  }

  // ── LOGIN PROMPT ──────────────────────────────────────────────────────────

  void _showLoginPrompt(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () {
                messenger.clearSnackBars();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthScreen(isLoginMode: true),
                  ),
                );
              },
              child: Text(
                'Sign In',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.textMain.withOpacity(0.92),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.only(left: 16, right: 8),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── APPLY COLOR ───────────────────────────────────────────────────────────

  Future<void> _applyColorToDeepAR(
    DbShade? shade,
    TryOnCategory category,
  ) async {
    if (!_isInitialized) return;
    final gameObject = _getGameObject(category);

    if (shade == null) {
      _deepArController.changeParameter(
        gameObject: gameObject,
        component: 'MeshRenderer',
        parameter: 'u_color',
        newParameter: vector.Vector4(0, 0, 0, 0),
      );
      return;
    }

    if (category == TryOnCategory.eyelashes ||
        category == TryOnCategory.mascara) {
      final config = _lashConfigs[shade.productKey];
      if (config != null) {
        try {
          final textureName = config.baseMaskType == 'gorgeous'
              ? 'gorgeous.png'
              : 'sexy.png';
          final texturePath = await _getAssetPath(textureName);
          _deepArController.changeParameter(
            gameObject: gameObject,
            component: 'MeshRenderer',
            parameter: 's_texColor',
            newParameter: texturePath,
          );
          _deepArController.changeParameter(
            gameObject: gameObject,
            component: 'Transform',
            parameter: 'scale',
            newParameter: vector.Vector3(config.scaleX, config.scaleY, 1.0),
          );
          final lashColor = config.color;
          final finalAlpha = config.opacity * (_intensities[category] ?? 1.0);
          _deepArController.changeParameter(
            gameObject: gameObject,
            component: 'MeshRenderer',
            parameter: 'u_color',
            newParameter: vector.Vector4(
              lashColor.red / 255.0,
              lashColor.green / 255.0,
              lashColor.blue / 255.0,
              finalAlpha,
            ),
          );
        } catch (e) {
          debugPrint("❌ Failed to apply Lash Config: $e");
        }
      }
      return;
    }

    final color = shade.color;
    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;
    double a = _intensities[category] ?? 0.5;
    if (category == TryOnCategory.eyeshadow)
      a *= 0.9;
    else if (category != TryOnCategory.eyeliner)
      a *= 0.7;

    final colorVector = vector.Vector4(r, g, b, a);

    try {
      if (category == TryOnCategory.lipstick ||
          category == TryOnCategory.lipGloss) {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_ambientColor',
          newParameter: vector.Vector4(1.0, 1.0, 1.0, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_diffuseColor',
          newParameter: colorVector,
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_specularColor',
          newParameter: vector.Vector4(0.2, 0.2, 0.2, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_shininess',
          newParameter: category == TryOnCategory.lipGloss ? 60.0 : 25.0,
        );
      } else {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_color',
          newParameter: colorVector,
        );
      }
    } catch (e) {
      debugPrint("❌ Apply failed for $gameObject: $e");
    }
  }

  // ── LOAD SAVED LOOK ───────────────────────────────────────────────────────

  void _loadAndApplySavedLook(List<dynamic> items) {
    for (var cat in TryOnCategory.values) {
      setState(() => _selectedShades[cat] = null);
      _applyColorToDeepAR(null, cat);
    }
    for (var item in items) {
      final productKey = item['product_key'] as String;
      final shadeKey = item['shade_key'] as String;
      final intensity = (item['intensity'] as num).toDouble() / 100.0;
      TryOnCategory? cat;
      if (productKey.startsWith('lsh_'))
        cat = TryOnCategory.eyelashes;
      else if (productKey.startsWith('lip_'))
        cat = TryOnCategory.lipstick;
      else if (productKey.startsWith('gloss_'))
        cat = TryOnCategory.lipGloss;
      else if (productKey.startsWith('fnd_'))
        cat = TryOnCategory.foundation;
      else if (productKey.startsWith('blu_'))
        cat = TryOnCategory.blush;
      else if (productKey.startsWith('mas_'))
        cat = TryOnCategory.mascara;
      else if (productKey.startsWith('hgl_'))
        cat = TryOnCategory.highlighter;
      else if (productKey.startsWith('eln_'))
        cat = TryOnCategory.eyeliner;
      else if (productKey.startsWith('esh_'))
        cat = TryOnCategory.eyeshadow;
      if (cat != null) {
        try {
          final shade = _allDbShades.firstWhere(
            (s) => s.productKey == productKey && s.shadeKey == shadeKey,
          );
          setState(() {
            _selectedShades[cat!] = shade;
            _intensities[cat] = intensity;
          });
          _applyColorToDeepAR(shade, cat);
        } catch (e) {
          debugPrint("⚠️ Shade not found: $productKey - $shadeKey");
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '✨ Look applied!',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── SAVE LOOK ─────────────────────────────────────────────────────────────

  Future<void> _saveLookToDb(String lookName) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save looks.')),
      );
      return;
    }
    if (!_selectedShades.values.any((s) => s != null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please apply some makeup first!')),
      );
      return;
    }
    setState(() => _isSaving = true);
    String? previewUrl;
    try {
      final File? screenshot = await _deepArController.takeScreenshot();
      if (screenshot != null) {
        final fileName =
            '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final bytes = await screenshot.readAsBytes();
        await Supabase.instance.client.storage
            .from('looks')
            .uploadBinary(fileName, bytes);
        previewUrl = Supabase.instance.client.storage
            .from('looks')
            .getPublicUrl(fileName);
      }
    } catch (e) {
      debugPrint("❌ Screenshot/Upload error: $e");
    }
    try {
      final lookRes = await Supabase.instance.client
          .from('saved_looks')
          .insert({
            'user_id': userId,
            'look_name': lookName.isEmpty ? 'My Custom Look' : lookName,
            'preview_image_url': previewUrl,
          })
          .select('id')
          .single();
      final String lookId = lookRes['id'];
      final List<Map<String, dynamic>> itemsToInsert = [];
      int layerOrder = 1;
      for (var entry in _selectedShades.entries) {
        final shade = entry.value;
        if (shade != null) {
          itemsToInsert.add({
            'look_id': lookId,
            'product_key': shade.productKey,
            'shade_key': shade.shadeKey,
            'intensity': ((_intensities[entry.key] ?? 0.5) * 100).toInt(),
            'layer_order': layerOrder++,
          });
        }
      }
      if (itemsToInsert.isNotEmpty) {
        await Supabase.instance.client
            .from('saved_look_items')
            .insert(itemsToInsert);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Look saved! 💖',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── SAVE DIALOG ───────────────────────────────────────────────────────────

  void _showSaveLookDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.60),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.96),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.7),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header icon + text
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.15),
                              AppColors.primary.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.bookmark_add_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Save Your Look',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textMain,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Give it a name to find it later',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Text field
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border, width: 1.2),
                    ),
                    child: TextField(
                      controller: nameController,
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'E.g. Glam Night, Everyday Nude…',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        prefixIcon: Icon(
                          Icons.auto_fix_high_outlined,
                          color: AppColors.primary.withOpacity(0.5),
                          size: 20,
                        ),
                      ),
                      cursorColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.border,
                                width: 1.2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _isSaving
                              ? null
                              : () => _saveLookToDb(nameController.text),
                          child: Container(
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withRed(
                                    (AppColors.primary.red + 30).clamp(0, 255),
                                  ),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.38),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(
                                          Icons.bookmark_added_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 7),
                                        Text(
                                          'Save Look',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                      ],
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
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentSelectedShade = _selectedShades[_currentCategory];
    final currentIntensity = _intensities[_currentCategory] ?? 0.5;
    final bool isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // Panel height: fixed so camera always gets ~55% of screen
    const double panelHeight = 320.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── CAMERA — fills the full screen behind everything ───────────
            if (_isInitialized)
              SizedBox.expand(child: DeepArPreview(_deepArController))
            else
              const _LoadingView(),

            // ── SUBTLE TOP GRADIENT — only for top bar legibility ──────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad + 100,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── SUBTLE BOTTOM GRADIENT — blends camera into panel ─────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: panelHeight + 60,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── TOP BAR ───────────────────────────────────────────────────
            Positioned(
              top: topPad + 10,
              left: 18,
              right: 18,
              child: FadeTransition(
                opacity: _topBarFade,
                child: SlideTransition(
                  position: _topBarSlide,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button
                      _TopBarButton(
                        onTap: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          Navigator.pop(context);
                        },
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),

                      // Center title badge
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.22),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withOpacity(
                                          0.7,
                                        ),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Try-On Studio',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Right side actions
                      Row(
                        children: [
                          _TopBarPill(
                            onTap: isLoggedIn
                                ? () async {
                                    final items = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SavedLooksScreen(),
                                      ),
                                    );
                                    if (items != null && items is List) {
                                      _loadAndApplySavedLook(items);
                                    }
                                  }
                                : () => _showLoginPrompt(
                                    'Sign in to view your saved looks!',
                                  ),
                            icon: Icons.favorite_border_rounded,
                            label: 'Saved',
                          ),
                          const SizedBox(width: 8),
                          _TopBarButton(
                            onTap: () {
                              if (isLoggedIn) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ProfileScreen(), // Apni Profile Screen ka class name yahan likhein
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AuthScreen(isLoginMode: true),
                                  ),
                                );
                              }
                            },
                            child: Icon(
                              isLoggedIn
                                  ? Icons.person_outline_rounded
                                  : Icons.login_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── BOTTOM PANEL ──────────────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FadeTransition(
                opacity: _panelFade,
                child: SlideTransition(
                  position: _panelSlide,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(36),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        decoration: BoxDecoration(
                          // Subtle warm-tinted glass
                          color: Colors.white.withOpacity(0.91),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(36),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withOpacity(0.80),
                              width: 1.2,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 30,
                              offset: const Offset(0, -8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag handle
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 14,
                                bottom: 2,
                              ),
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                botPad + 18,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ── Header row ───────────────────────
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Virtual Try-On',
                                              style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.textMain,
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Row(
                                              children: [
                                                Container(
                                                  width: 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  _getCategoryName(
                                                    _currentCategory,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: AppColors.primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Save button
                                      GestureDetector(
                                        onTap: isLoggedIn
                                            ? _showSaveLookDialog
                                            : () => _showLoginPrompt(
                                                'Sign in to save your look!',
                                              ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            gradient: isLoggedIn
                                                ? LinearGradient(
                                                    colors: [
                                                      AppColors.primary,
                                                      AppColors.primary.withRed(
                                                        (AppColors.primary.red +
                                                                28)
                                                            .clamp(0, 255),
                                                      ),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  )
                                                : null,
                                            color: isLoggedIn
                                                ? null
                                                : Colors.black.withOpacity(
                                                    0.06,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              50,
                                            ),
                                            boxShadow: isLoggedIn
                                                ? [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withOpacity(0.35),
                                                      blurRadius: 16,
                                                      offset: const Offset(
                                                        0,
                                                        5,
                                                      ),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.bookmark_add_outlined,
                                                color: isLoggedIn
                                                    ? Colors.white
                                                    : AppColors.textMuted,
                                                size: 15,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Save',
                                                style: TextStyle(
                                                  color: isLoggedIn
                                                      ? Colors.white
                                                      : AppColors.textMuted,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.5,
                                                  letterSpacing: 0.1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // ── Category Tabs ─────────────────────
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      children: TryOnCategory.values
                                          .map((cat) => _buildCategoryTab(cat))
                                          .toList(),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // ── Shade label + dot ─────────────────
                                  Row(
                                    children: [
                                      Container(
                                        width: 3,
                                        height: 14,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: currentSelectedShade != null
                                              ? AppColors.primary
                                              : AppColors.border,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          currentSelectedShade != null
                                              ? currentSelectedShade.shadeName
                                              : 'Choose a shade below',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: currentSelectedShade != null
                                                ? AppColors.textMain
                                                : AppColors.textMuted,
                                            fontWeight:
                                                currentSelectedShade != null
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (currentSelectedShade != null)
                                        _MiniColorDot(
                                          color: currentSelectedShade.color,
                                        ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // ── Shades List ───────────────────────
                                  SizedBox(
                                    height: 52,
                                    child: _currentShades.isEmpty
                                        ? Center(
                                            child: Text(
                                              'No shades available',
                                              style: TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 13,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            physics:
                                                const BouncingScrollPhysics(),
                                            itemCount:
                                                _currentShades.length + 1,
                                            itemBuilder: (context, index) {
                                              if (index == 0) {
                                                final cleared =
                                                    currentSelectedShade ==
                                                    null;
                                                return GestureDetector(
                                                  onTap: () {
                                                    setState(
                                                      () =>
                                                          _selectedShades[_currentCategory] =
                                                              null,
                                                    );
                                                    _applyColorToDeepAR(
                                                      null,
                                                      _currentCategory,
                                                    );
                                                  },
                                                  child: _ShadeCircle(
                                                    isSelected: cleared,
                                                    child: Icon(
                                                      Icons.block_rounded,
                                                      color:
                                                          AppColors.textMuted,
                                                      size: 18,
                                                    ),
                                                  ),
                                                );
                                              }

                                              final shade =
                                                  _currentShades[index - 1];
                                              final isSelected =
                                                  currentSelectedShade !=
                                                      null &&
                                                  shade.productKey ==
                                                      currentSelectedShade
                                                          .productKey;

                                              Color displayColor = shade.color;
                                              if ((_currentCategory ==
                                                          TryOnCategory
                                                              .eyelashes ||
                                                      _currentCategory ==
                                                          TryOnCategory
                                                              .mascara) &&
                                                  _lashConfigs.containsKey(
                                                    shade.productKey,
                                                  )) {
                                                displayColor =
                                                    _lashConfigs[shade
                                                            .productKey]!
                                                        .color;
                                              }

                                              return GestureDetector(
                                                onTap: () {
                                                  setState(
                                                    () =>
                                                        _selectedShades[_currentCategory] =
                                                            shade,
                                                  );
                                                  _applyColorToDeepAR(
                                                    shade,
                                                    _currentCategory,
                                                  );
                                                },
                                                child: _ShadeCircle(
                                                  color: displayColor,
                                                  isSelected: isSelected,
                                                ),
                                              );
                                            },
                                          ),
                                  ),

                                  const SizedBox(height: 12),

                                  // ── Intensity Row ─────────────────────
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(
                                        0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.primary.withOpacity(
                                          0.10,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.water_drop_outlined,
                                          color: AppColors.primary.withOpacity(
                                            0.7,
                                          ),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 7),
                                        Text(
                                          'Intensity',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderTheme.of(context).copyWith(
                                              activeTrackColor:
                                                  AppColors.primary,
                                              inactiveTrackColor: AppColors
                                                  .primary
                                                  .withOpacity(0.12),
                                              thumbColor: Colors.white,
                                              overlayColor: AppColors.primary
                                                  .withOpacity(0.12),
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                    enabledThumbRadius: 8,
                                                  ),
                                              trackHeight: 2.5,
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                    overlayRadius: 18,
                                                  ),
                                            ),
                                            child: Slider(
                                              value: currentIntensity,
                                              min: 0.1,
                                              max: 1.0,
                                              onChanged:
                                                  currentSelectedShade == null
                                                  ? null
                                                  : (val) {
                                                      setState(
                                                        () =>
                                                            _intensities[_currentCategory] =
                                                                val,
                                                      );
                                                      _applyColorToDeepAR(
                                                        currentSelectedShade,
                                                        _currentCategory,
                                                      );
                                                    },
                                            ),
                                          ),
                                        ),
                                        Container(
                                          width: 42,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${(currentIntensity * 100).toInt()}%',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CATEGORY TAB ──────────────────────────────────────────────────────────

  Widget _buildCategoryTab(TryOnCategory cat) {
    final isSelected = _currentCategory == cat;
    final hasShade = _selectedShades[cat] != null;

    return GestureDetector(
      onTap: () => setState(() => _currentCategory = cat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : hasShade
                ? AppColors.primary.withOpacity(0.35)
                : Colors.black.withOpacity(0.10),
            width: isSelected ? 0 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.30),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getCategoryIcon(cat),
              size: 12,
              color: isSelected
                  ? Colors.white
                  : hasShade
                  ? AppColors.primary
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              _getCategoryName(cat),
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : hasShade
                    ? AppColors.primary
                    : AppColors.textMuted,
                fontWeight: isSelected || hasShade
                    ? FontWeight.w700
                    : FontWeight.w500,
                fontSize: 12.5,
              ),
            ),
            if (hasShade && !isSelected) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _selectedShades[cat]!.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.4),
                    width: 0.8,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── HELPER WIDGETS ────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 1.5,
            ),
            const SizedBox(height: 18),
            Text(
              'Preparing AR experience…',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 12.5,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted glass circular icon button for the top bar
class _TopBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TopBarButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass pill button for top bar (Saved)
class _TopBarPill extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  const _TopBarPill({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.white.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 15),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShadeCircle extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final Widget? child;
  const _ShadeCircle({this.color, required this.isSelected, this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 10),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.white,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? AppColors.primary.withOpacity(0.45)
                : Colors.black.withOpacity(0.12),
            blurRadius: isSelected ? 14 : 5,
            spreadRadius: isSelected ? 1 : 0,
          ),
        ],
      ),
      child: child != null
          ? Center(child: child)
          : isSelected
          ? Center(
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _MiniColorDot extends StatelessWidget {
  final Color color;
  const _MiniColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.45),
            blurRadius: 7,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
