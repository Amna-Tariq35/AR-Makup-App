import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;
import 'package:path_provider/path_provider.dart';
import 'package:deepar_flutter/deepar_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../utils/app_colors.dart';
import 'saved_looks_screen.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';

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

// ── INTENSITY MAPPING ─────────────────────────────────────────────────────────
//
// UI shows 0–100 % to the user.
// _intensities stores 0.0–1.0 (the "user slider" value).
//
// _mapIntensityToBackend() maps the user's 0–1 value to the REAL
// backend alpha that makes each category look natural and realistic.
//
// Design constraints per category
// ────────────────────────────────
// Lipstick    : semi-matte; 100% alpha = plastic. Range 0.30 → 0.68
// Lip Gloss   : translucency IS the effect; high alpha kills shimmer. Range 0.38 → 0.60
// Foundation  : skin coverage, never opaque mask. Range 0.12 → 0.44
// Blush       : soft flush, easy to over-apply. Range 0.10 → 0.38  (+6% ceiling vs v1)
// Eyeshadow   : artistic; raised ceiling for dramatic looks. Range 0.15 → 0.82  (+7% ceiling vs v1)
// Eyeliner    : must be opaque even at low slider. Range 0.55 → 0.95
// Highlighter : subtle shimmer; ghost-white at high values. Range 0.10 → 0.44
// Lashes/Mascara: controlled via lash-config opacity × factor. Range 0.70 → 1.00
//
double _mapIntensityToBackend(TryOnCategory category, double userValue) {
  double lo, hi;
  switch (category) {
    case TryOnCategory.lipstick:
      lo = 0.30;
      hi = 0.68;
    case TryOnCategory.lipGloss:
      lo = 0.38;
      hi = 0.60;
    case TryOnCategory.foundation:
      lo = 0.12;
      hi = 0.44; // +0.02 → slightly more buildable coverage
    case TryOnCategory.blush:
      lo = 0.10;
      hi = 0.38; // was 0.08→0.32; raised ceiling so rosy flush reads clearly
    case TryOnCategory.eyeshadow:
      lo = 0.15;
      hi = 0.82; // was 0.15→0.75; raised for dramatic / smoky looks
    case TryOnCategory.eyeliner:
      lo = 0.55;
      hi = 0.95;
    case TryOnCategory.highlighter:
      lo = 0.10;
      hi = 0.44; // +0.02 → more visible glow at high slider
    case TryOnCategory.eyelashes:
    case TryOnCategory.mascara:
      lo = 0.70;
      hi = 1.00;
  }
  return lo + userValue * (hi - lo);
}

// ── SCREEN ───────────────────────────────────────────────────────────────────

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── DeepAR controller is created once and NEVER destroyed except in dispose().
  // Destroying on lifecycle-paused breaks navigation (Android treats route push
  // as a brief pause, which fires paused before the new surface is ready).
  late DeepArController _deepArController;
  Key _deepArKey = UniqueKey();

  bool _isInitialized = false;
  bool _initFailed = false;
  bool _isSaving = false;
  bool _surfaceReady = false;
  // Guards against concurrent init calls (navigation races, resumed events)
  bool _initInProgress = false;

  final String androidKey =
      "2952b3fa8af974da37a4802986a2b95c7383ea2f999dc94e83646b7ecab03d9c68e6232e888e8333";
  final String iosKey = "YAHAN_APNI_IOS_LICENSE_KEY_DALEIN";

  List<DbShade> _allDbShades = [];
  Map<String, DbLashConfig> _lashConfigs = {};
  TryOnCategory _currentCategory = TryOnCategory.lipstick;

  final Map<TryOnCategory, DbShade?> _selectedShades = {
    for (var cat in TryOnCategory.values) cat: null,
  };

  // User-facing slider values: 0.0 → 1.0 (shown as 0–100 %)
  // Defaults produce a realistic "first impression" look:
  //   lipstick   65 % → backend 0.509  (natural semi-matte)
  //   lip gloss  60 % → backend 0.492  (translucent gloss)
  //   foundation 40 % → backend 0.248  (light coverage)
  //   blush      52 % → backend 0.248  (natural flush, maps to new 0.10–0.38)
  //   eyeshadow  55 % → backend 0.467  (wearable, maps to new 0.15–0.82)
  //   eyeliner   80 % → backend 0.870  (crisp line)
  //   highlighter 45% → backend 0.247  (subtle glow)
  //   lashes/mas 85 % → backend 0.955  (full lash)
  final Map<TryOnCategory, double> _intensities = {
    TryOnCategory.eyelashes: 0.85,
    TryOnCategory.lipstick: 0.65,
    TryOnCategory.lipGloss: 0.60,
    TryOnCategory.foundation: 0.40,
    TryOnCategory.blush: 0.52,
    TryOnCategory.mascara: 0.85,
    TryOnCategory.highlighter: 0.45,
    TryOnCategory.eyeliner: 0.80,
    TryOnCategory.eyeshadow: 0.55,
  };

  // Cached temp-file paths for asset textures (avoids re-writing on every tap)
  final Map<String, String> _assetPathCache = {};

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
    WidgetsBinding.instance.addObserver(this);

    _deepArController = DeepArController();

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

    _loadDataFromDb();

    // 🆕 CHANGE: 300ms ki jagah ab hum surface ready hone ka wait karenge
    // Pehla frame paint hone ke baad surface ready guard set karo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Android SurfaceHolder.surfaceCreated() ko time do
      // 0.0.5 version mein koi callback nahi hai isliye
      // hum ek reliable multi-frame wait use karenge
      _waitForSurfaceThenInit();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Always destroy — this is the only place we tear down the controller.
    try {
      _deepArController.destroy();
    } catch (_) {}
    _panelController.dispose();
    _topBarController.dispose();
    super.dispose();
  }

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────
  //
  // KEY RULE: do NOT destroy/reinitialize on paused.
  // Android fires AppLifecycleState.paused during route push (e.g. opening
  // AuthScreen or SavedLooksScreen from TryOnScreen). Destroying the controller
  // there tears down the EGL surface, causing EGL_BAD_NATIVE_WINDOW on resume.
  // We only re-init on resumed IF the controller was already destroyed (which
  // only happens in dispose, i.e. the screen was fully popped).
  //
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _teardownDeepAR();
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && !_isInitialized && !_initInProgress) {
        // 🆕 Resume pe bhi surface wait karo
        setState(() => _surfaceReady = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _waitForSurfaceThenInit();
        });
      }
    }
  }

  // 🆕 YE POORA METHOD ADD KARO
  // Ye method ensure karta hai ki Android ka EGL surface
  // fully ready ho initialize karne se pehle.
  // deepar_flutter 0.0.5 mein surface callback nahi hai
  // isliye hum frame-based polling use karte hain.
  Future<void> _waitForSurfaceThenInit() async {
  if (!mounted) return;

  // ✅ FIX: Navigation se wapis aane pe _surfaceReady reset karo
  // (teardown mein already reset hoti hai, lekin double-safety ke liye)
  if (mounted && !_surfaceReady) {
    // Already false hai — theek hai
  }

  // 5 frames wait
  for (int i = 0; i < 5; i++) {
    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
  }

  // ✅ FIX: 600ms → 800ms
  // Navigation se wapis aane pe Android surface re-attach slow hoti hai
  await Future.delayed(const Duration(milliseconds: 800));
  if (!mounted) return;

  if (mounted) setState(() => _surfaceReady = true);
  await _initializeDeepAR();
}
  // ── CATEGORY HELPERS ──────────────────────────────────────────────────────
  Future<void> _teardownDeepAR() async {
    if (!_isInitialized && !_initInProgress) return;

    _initInProgress = false;

    // 🆕 Surface flag bhi reset karo
    if (mounted)
      setState(() {
        _isInitialized = false;
        _surfaceReady = false; // 🆕
      });

    try {
      await _deepArController.destroy();
    } catch (_) {}

    _deepArController = DeepArController();
    _deepArKey = UniqueKey();
  }

  String _getGameObject(TryOnCategory category) {
    switch (category) {
      case TryOnCategory.lipstick:
      case TryOnCategory.lipGloss:
        return 'lips';
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
        return 'face_makeup';
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

  String _prefixForKey(String productKey) {
    if (productKey.startsWith('lsh_')) return 'lsh_';
    if (productKey.startsWith('lip_')) return 'lip_';
    if (productKey.startsWith('gloss_')) return 'gloss_';
    if (productKey.startsWith('fnd_')) return 'fnd_';
    if (productKey.startsWith('blu_')) return 'blu_';
    if (productKey.startsWith('mas_')) return 'mas_';
    if (productKey.startsWith('hgl_')) return 'hgl_';
    if (productKey.startsWith('eln_')) return 'eln_';
    if (productKey.startsWith('esh_')) return 'esh_';
    return '';
  }

  TryOnCategory? _categoryForPrefix(String prefix) {
    switch (prefix) {
      case 'lsh_':
        return TryOnCategory.eyelashes;
      case 'lip_':
        return TryOnCategory.lipstick;
      case 'gloss_':
        return TryOnCategory.lipGloss;
      case 'fnd_':
        return TryOnCategory.foundation;
      case 'blu_':
        return TryOnCategory.blush;
      case 'mas_':
        return TryOnCategory.mascara;
      case 'hgl_':
        return TryOnCategory.highlighter;
      case 'eln_':
        return TryOnCategory.eyeliner;
      case 'esh_':
        return TryOnCategory.eyeshadow;
      default:
        return null;
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

  // ── DEEPAR INIT ───────────────────────────────────────────────────────────
  //
  // Uses _initInProgress flag to prevent concurrent calls (lifecycle races).
  // Retries up to 3 times with exponential back-off.
  // Shows a retry dialog on total failure.
  //
  Future<void> _initializeDeepAR() async {
    // 🆕 Surface ready nahi toh bilkul mat chalao
    if (!_surfaceReady || _initInProgress || !mounted) return;
    _initInProgress = true;

    // Agar pehle se initialized tha toh destroy karke fresh start karo
    if (_isInitialized) {
      try {
        await _deepArController.destroy();
      } catch (e) {
        debugPrint("Destroy error: $e");
      }
      _deepArController = DeepArController();
      _deepArKey = UniqueKey();
      if (mounted) setState(() => _isInitialized = false);

      // 🆕 Naye controller ke liye surface re-attach ka wait
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) {
        _initInProgress = false;
        return;
      }
    }

    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted) {
        _initInProgress = false;
        return;
      }
      debugPrint('DeepAR: init attempt $attempt/$maxAttempts');

      try {
        await _deepArController.initialize(
          androidLicenseKey: androidKey,
          iosLicenseKey: iosKey,
          resolution: Resolution.high,
        );

        if (!mounted) {
          _initInProgress = false;
          return;
        }

        await _deepArController.switchEffect('assets/effects/makeup.deepar');

        if (!mounted) {
          _initInProgress = false;
          return;
        }

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _initFailed = false;
          });
        }

        // Previously selected shades restore karo
        for (var cat in TryOnCategory.values) {
          if (_selectedShades[cat] != null) {
            await _applyColorToDeepAR(_selectedShades[cat], cat);
          }
        }

        _panelController.forward();
        _topBarController.forward();
        _initInProgress = false;
        debugPrint('DeepAR: ready ✓');
        return;
      } catch (e) {
        debugPrint('DeepAR: attempt $attempt failed: $e');
        if (attempt < maxAttempts && mounted) {
          // 🆕 Exponential backoff — surface settle hone ka waqt do
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    _initInProgress = false;
    if (mounted) setState(() => _initFailed = true);
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
      // Deduplicate by productKey + hex
      final uniqueShades = <String, DbShade>{};
      for (var shade in allFetched) {
        final key = '${shade.productKey}_${shade.shadeHex}';
        uniqueShades.putIfAbsent(key, () => shade);
      }
      if (mounted) setState(() => _allDbShades = uniqueShades.values.toList());
    } catch (e) {
      debugPrint('❌ Error loading shades: $e');
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
      if (mounted) setState(() => _lashConfigs = configsMap);
    } catch (e) {
      debugPrint('❌ Error loading lash configs: $e');
    }
  }

  // ── ASSET HELPER (cached) ─────────────────────────────────────────────────

  Future<String> _getAssetPath(String assetName) async {
    if (_assetPathCache.containsKey(assetName)) {
      return _assetPathCache[assetName]!;
    }
    final byteData = await rootBundle.load('assets/textures/$assetName');
    final file = File('${(await getTemporaryDirectory()).path}/$assetName');
    await file.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );
    _assetPathCache[assetName] = file.path;
    return file.path;
  }

  // ── LOGIN PROMPT ──────────────────────────────────────────────────────────

  void _showLoginPrompt(String message) {
    if (!mounted) return;
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
              onPressed: () async {
                // 🟢 1. async add kiya
                messenger.clearSnackBars();

                // 🟢 2. Navigation se pehle camera destroy karein
                await _teardownDeepAR();

                if (!mounted) return;

                // 🟢 3. await ke sath push karein
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AuthScreen(isLoginMode: true),
                  ),
                );

                // 🟢 4. Wapis aane par camera dobara initialize karein
                if (mounted) {
                  _waitForSurfaceThenInit();
                }
              },
              child: const Text(
                'Sign In',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(
          seconds: 4,
        ), // Thoda extra time taake user click kar sake
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.only(left: 16, right: 8),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── APPLY COLOR ───────────────────────────────────────────────────────────
  //
  // _intensities[category] is the USER'S 0.0–1.0 value (shown as 0–100 % in UI).
  // Before sending to DeepAR we ALWAYS call _mapIntensityToBackend() which
  // remaps to the physically realistic range for that product category.
  //
  Future<void> _applyColorToDeepAR(
    DbShade? shade,
    TryOnCategory category,
  ) async {
    if (!_isInitialized) return;
    final gameObject = _getGameObject(category);

    // ── CLEAR / NULL ──────────────────────────────────────────────────────
    if (shade == null) {
      if (category == TryOnCategory.foundation) {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'foundationColor',
          newParameter: vector.Vector4(0.9, 0.88, 0.80, 0.0),
        );
      } else if (category == TryOnCategory.lipstick ||
          category == TryOnCategory.lipGloss) {
        for (final param in [
          'u_diffuseColor',
          'u_ambientColor',
          'u_specularColor',
        ]) {
          _deepArController.changeParameter(
            gameObject: gameObject,
            component: 'MeshRenderer',
            parameter: param,
            newParameter: vector.Vector4(0, 0, 0, 0),
          );
        }
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_shininess',
          newParameter: 0.0,
        );
      } else {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_color',
          newParameter: vector.Vector4(0, 0, 0, 0),
        );
      }
      return;
    }

    final color = shade.color;
    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;

    final userIntensity = _intensities[category] ?? 0.5;
    final backendIntensity = _mapIntensityToBackend(category, userIntensity);

    // ── EYELASHES / MASCARA ───────────────────────────────────────────────
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
          final finalAlpha = (config.opacity * backendIntensity).clamp(
            0.0,
            1.0,
          );
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
          debugPrint('❌ Failed to apply Lash Config: $e');
        }
      }
      return;
    }

    // ── FOUNDATION ────────────────────────────────────────────────────────
    //
    // backendIntensity range: 0.12 → 0.44
    // Passed directly as alpha — keeps coverage skin-blended always.
    //
    if (category == TryOnCategory.foundation) {
      try {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'foundationColor',
          newParameter: vector.Vector4(r, g, b, backendIntensity),
        );
      } catch (e) {
        debugPrint('❌ Foundation apply failed: $e');
      }
      return;
    }

    // ── LIPSTICK ──────────────────────────────────────────────────────────
    //
    // Semi-matte physics:
    //   Ambient 0.40  — colour fills shadow areas
    //   Diffuse alpha: backendIntensity (0.30 → 0.68)
    //   Specular (0.08, 0.08, 0.09) — very subtle; lipstick is not shiny
    //   Shininess 18  — wide soft lobe = satin (not glass / plastic)
    //
    if (category == TryOnCategory.lipstick) {
      try {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_ambientColor',
          newParameter: vector.Vector4(0.40, 0.40, 0.40, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_diffuseColor',
          newParameter: vector.Vector4(r, g, b, backendIntensity),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_specularColor',
          newParameter: vector.Vector4(0.08, 0.08, 0.09, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_shininess',
          newParameter: 18.0,
        );
      } catch (e) {
        debugPrint('❌ Lipstick apply failed: $e');
      }
      return;
    }

    // ── LIP GLOSS ─────────────────────────────────────────────────────────
    //
    // Glossy physics:
    //   Diffuse alpha: backendIntensity (0.38 → 0.60) — low = translucency
    //   Ambient 0.55  — enough fill to show tint in shadow
    //   Specular (0.85, 0.87, 0.90) near-white, blue-shifted = "wet" look
    //   Shininess 72  — tight but not glass-like
    //
    if (category == TryOnCategory.lipGloss) {
      try {
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_ambientColor',
          newParameter: vector.Vector4(0.55, 0.55, 0.55, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_diffuseColor',
          newParameter: vector.Vector4(r, g, b, backendIntensity),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_specularColor',
          newParameter: vector.Vector4(0.85, 0.87, 0.90, 1.0),
        );
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_shininess',
          newParameter: 72.0,
        );
      } catch (e) {
        debugPrint('❌ Lip Gloss apply failed: $e');
      }
      return;
    }

    // ── EYESHADOW / EYELINER / BLUSH / HIGHLIGHTER ────────────────────────
    // backendIntensity is the physically correct alpha for each category.
    try {
      _deepArController.changeParameter(
        gameObject: gameObject,
        component: 'MeshRenderer',
        parameter: 'u_color',
        newParameter: vector.Vector4(r, g, b, backendIntensity),
      );
    } catch (e) {
      debugPrint('❌ Apply failed for $gameObject: $e');
    }
  }

  // ── LOAD SAVED LOOK ───────────────────────────────────────────────────────

  void _loadAndApplySavedLook(List<dynamic> items) {
    // Batch all state mutations into a single setState
    final Map<TryOnCategory, DbShade?> newShades = {
      for (var cat in TryOnCategory.values) cat: null,
    };
    final Map<TryOnCategory, double> newIntensities = Map.from(_intensities);

    // Clear AR first
    for (var cat in TryOnCategory.values) {
      _applyColorToDeepAR(null, cat);
    }

    for (var item in items) {
      final productKey = item['product_key'] as String;
      final shadeKey = item['shade_key'] as String;
      // DB stores 0–100; convert to 0.0–1.0 for slider
      final intensity = (item['intensity'] as num).toDouble() / 100.0;

      final prefix = _prefixForKey(productKey);
      final cat = _categoryForPrefix(prefix);
      if (cat == null) {
        debugPrint('⚠️ Unknown product prefix: $productKey');
        continue;
      }

      try {
        final shade = _allDbShades.firstWhere(
          (s) => s.productKey == productKey && s.shadeKey == shadeKey,
        );
        newShades[cat] = shade;
        newIntensities[cat] = intensity;
        _applyColorToDeepAR(shade, cat);
      } catch (_) {
        debugPrint('⚠️ Shade not found: $productKey - $shadeKey');
      }
    }

    setState(() {
      for (var cat in TryOnCategory.values) {
        _selectedShades[cat] = newShades[cat];
        _intensities[cat] = newIntensities[cat]!;
      }
    });

    if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please sign in to save looks.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }
    if (!_selectedShades.values.any((s) => s != null)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please apply some makeup first!',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
        ),
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
      debugPrint('❌ Screenshot/Upload error: $e');
    }

    try {
      final lookRes = await Supabase.instance.client
          .from('saved_looks')
          .insert({
            'user_id': userId,
            'look_name': lookName.trim().isEmpty
                ? 'My Custom Look'
                : lookName.trim(),
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
            // Save user-facing 0–100 value (NOT the backend-mapped value)
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

      if (!mounted) return;
      Navigator.pop(context); // dismiss dialog
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── SAVE DIALOG ───────────────────────────────────────────────────────────

  void _showSaveLookDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.60),
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
                color: AppColors.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
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
                          color: AppColors.primary.withValues(alpha: 0.5),
                          size: 20,
                        ),
                      ),
                      cursorColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        child: StatefulBuilder(
                          builder: (context, setDialogState) {
                            return GestureDetector(
                              onTap: _isSaving
                                  ? null
                                  : () => _saveLookToDb(nameController.text),
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.38,
                                      ),
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
                                      : const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
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
                            );
                          },
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── CAMERA ────────────────────────────────────────────────────
            // CRITICAL: DeepArPreview must ALWAYS be in the widget tree from
            // the very first frame, even before initialize() is called.
            // Conditionally removing it causes Android to destroy and recreate
            // the SurfaceView, producing EGL_BAD_NATIVE_WINDOW errors.
            // The loading overlay is stacked on top until _isInitialized.
            // ── CAMERA ────────────────────────────────────────────────────
            // Build mein ye section dhundho aur replace karo:
            // 🆕 Surface ready hone se pehle DeepArPreview mount mat karo
            // Ye CRITICAL hai — 0.0.5 version mein agar widget mount hone se
            // pehle initialize() call ho jaaye toh EGL_BAD_NATIVE_WINDOW aata hai.
            // Isliye hum pehle ek black container dikhate hain, phir widget swap karte hain.
            SizedBox.expand(
              child: _surfaceReady
                  ? DeepArPreview(_deepArController, key: _deepArKey)
                  : const ColoredBox(color: Colors.black),
            ),
            // Loading / error overlay — shown until AR is ready
            if (!_isInitialized)
              Positioned.fill(
                child: _initFailed
                    ? _ErrorView(
                        onRetry: () {
                          setState(() {
                            _isInitialized = false;
                            _initFailed = false;
                          });
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (mounted) _initializeDeepAR();
                          });
                        },
                      )
                    : const _LoadingView(),
              ),

            // ── TOP GRADIENT ──────────────────────────────────────────────
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
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── BOTTOM GRADIENT ───────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 380,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
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
                      

                      // Centre title pill
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
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
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
                                        color: AppColors.primary.withValues(
                                          alpha: 0.7,
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

                      Row(
                        children: [
                          _TopBarPill(
                            onTap: isLoggedIn
                                ? () async {
                                    // 1. Camera band karein
                                    await _teardownDeepAR();

                                    final items = await Navigator.push(
                                      // 🟢 await already tha yahan
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SavedLooksScreen(),
                                      ),
                                    );

                                    // 2. Wapis aane par camera dobara on karein
                                    if (mounted) {
                                       await _waitForSurfaceThenInit();
                                      

                                      // 3. Agar user ne koi look select kiya hai toh apply karein
                                      if (items != null && items is List) {
                                        _loadAndApplySavedLook(items);
                                      }
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
                            onTap: () async {
                              // 🟢 async add kiya
                              // 1. Navigation se pehle camera safely destroy karein
                              await _teardownDeepAR();

                              if (isLoggedIn) {
                                await Navigator.push(
                                  // 🟢 await add kiya
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ProfileScreen(),
                                  ),
                                );
                              } else {
                                await Navigator.push(
                                  // 🟢 await add kiya
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AuthScreen(isLoginMode: true),
                                  ),
                                );
                              }

                              // 2. Jab user wapis is screen par aaye, toh camera dobara on karein
                              if (mounted) {
                                _waitForSurfaceThenInit();
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
                          color: AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(36),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: AppColors.border,
                              width: 1.2,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
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
                                top: 12,
                                bottom: 2,
                              ),
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.25,
                                  ),
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
                                            const SizedBox(height: 2),
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
                                            color: isLoggedIn
                                                ? AppColors.primary
                                                : AppColors.border,
                                            borderRadius: BorderRadius.circular(
                                              50,
                                            ),
                                            boxShadow: isLoggedIn
                                                ? [
                                                    BoxShadow(
                                                      color: AppColors.primary
                                                          .withValues(
                                                            alpha: 0.35,
                                                          ),
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

                                  // ── Category tabs ────────────────────
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      children: TryOnCategory.values
                                          .map(_buildCategoryTab)
                                          .toList(),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // ── Shade label row ──────────────────
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

                                  // ── Shades list ──────────────────────
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

                                  // ── Intensity slider ─────────────────
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.10,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.water_drop_outlined,
                                          color: AppColors.primary.withValues(
                                            alpha: 0.7,
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
                                                  .withValues(alpha: 0.12),
                                              thumbColor: Colors.white,
                                              overlayColor: AppColors.primary
                                                  .withValues(alpha: 0.12),
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
                                              min: 0.0,
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
                                            '${(currentIntensity * 100).round()}%',
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
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
            width: isSelected ? 0 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
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
                    color: AppColors.primary.withValues(alpha: 0.4),
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
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Preparing AR experience…',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This takes just a moment',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.55),
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.20),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Camera unavailable',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Could not start the AR camera.\nPlease try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
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
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
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
    // Inner dot color: white on dark shades, dark primary on light shades
    final bool isDarkShade = color != null
        ? (color!.computeLuminance() < 0.35)
        : false;
    final Color innerDotColor = isDarkShade
        ? Colors.white.withValues(alpha: 0.88)
        : AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 10),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.surface,
          width: isSelected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.12),
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
                  color: innerDotColor,
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
            color: color.withValues(alpha: 0.45),
            blurRadius: 7,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
