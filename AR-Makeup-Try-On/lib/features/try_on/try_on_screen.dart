import 'package:flutter/material.dart';
import 'package:deepar_flutter/deepar_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class DbShade {
  final String productKey;
  final String shadeName;
  final String shadeHex;
  final int shadeOrder;

  DbShade({
    required this.productKey,
    required this.shadeName,
    required this.shadeHex,
    required this.shadeOrder,
  });

  factory DbShade.fromMap(Map<String, dynamic> map) {
    return DbShade(
      productKey: map['product_key'] as String? ?? '',
      shadeName: map['shade_name'] as String? ?? '',
      shadeHex: map['shade_hex'] as String? ?? '#000000',
      shadeOrder: (map['shade_order'] as num?)?.toInt() ?? 0,
    );
  }

  Color get color {
    final cleaned = shadeHex.replaceAll('#', '').trim();
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}

// 🔴 1. Yahan 'eyeshadow' category add ki hai
enum TryOnCategory { lipstick, blush, eyeshadow }

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  late final DeepArController _deepArController;
  bool _isInitialized = false;

  // YAHAN APNI KEYS DALEIN
  final String androidKey = "2952b3fa8af974da37a4802986a2b95c7383ea2f999dc94e83646b7ecab03d9c68e6232e888e8333";
  final String iosKey = "YAHAN_APNI_IOS_LICENSE_KEY_DALEIN";

  List<DbShade> _allDbShades = [];
  TryOnCategory _currentCategory = TryOnCategory.lipstick;

  // 🔴 2. Eyeshadow ka default null set kiya
  final Map<TryOnCategory, Color?> _selectedShades = {
    TryOnCategory.lipstick: null,
    TryOnCategory.blush: null,
    TryOnCategory.eyeshadow: null,
  };

  // 🔴 3. Eyeshadow ki default intensity (opacity) set ki
  final Map<TryOnCategory, double> _intensities = {
    TryOnCategory.lipstick: 0.7, 
    TryOnCategory.blush: 0.4,    
    TryOnCategory.eyeshadow: 0.6, // Eyeshadow thora wazeh hona chahiye
  };

  // 🔴 4. Category ke hisaab se DeepAR ka node name
  String _getGameObject(TryOnCategory category) {
    switch (category) {
      case TryOnCategory.lipstick: return 'Lips';
      case TryOnCategory.blush: return 'Blush';
      // ⚠️ DHYAN RAHE: DeepAR Studio mein aapke eyeshadow wale node ka naam 'Eyeshadow' hona chahiye
      case TryOnCategory.eyeshadow: return 'EyeShadow'; 
    }
  }

  // 🔴 5. Category ke hisaab se database ka prefix ('esh_')
  String get _currentPrefix {
    switch (_currentCategory) {
      case TryOnCategory.lipstick: return 'lip_';
      case TryOnCategory.blush: return 'blu_';
      case TryOnCategory.eyeshadow: return 'esh_';
    }
  }

  // Current category ke shades filter karna
  List<DbShade> get _currentShades =>
      _allDbShades.where((s) => s.productKey.startsWith(_currentPrefix)).toList();

  @override
  void initState() {
    super.initState();
    _initializeDeepAR();
    _loadShadesFromDb();
  }

  Future<void> _initializeDeepAR() async {
    _deepArController = DeepArController();

    await _deepArController.initialize(
      androidLicenseKey: androidKey,
      iosLicenseKey: iosKey,
      resolution: Resolution.high,
    );

    await _deepArController.switchEffect('assets/effects/makeup.deepar');

    setState(() {
      _isInitialized = true;
    });
    debugPrint("✅ DeepAR initialized + effect loaded");
  }

  Future<void> _loadShadesFromDb() async {
    try {
      final response = await Supabase.instance.client
          .from('product_shades')
          .select('product_key, shade_name, shade_hex, shade_order')
          .order('shade_order', ascending: true);

      final rows = response as List<dynamic>;
      final allFetched = rows.map((e) => DbShade.fromMap(e as Map<String, dynamic>)).toList();

      // Duplicates remove karna
      final uniqueShades = <String, DbShade>{};
      for (var shade in allFetched) {
        if (!uniqueShades.containsKey(shade.shadeHex)) {
          uniqueShades[shade.shadeHex] = shade;
        }
      }

      setState(() {
        _allDbShades = uniqueShades.values.toList();
      });
    } catch (e) {
      debugPrint("❌ Error loading shades: $e");
    }
  }

  Future<void> _applyColorToDeepAR(Color? color, TryOnCategory category) async {
    if (!_isInitialized) return;

    final gameObject = _getGameObject(category);
    
    double r = 0.0, g = 0.0, b = 0.0, a = 0.0;

    if (color != null) {
      r = color.red / 255.0;
      g = color.green / 255.0;
      b = color.blue / 255.0;
      a = _intensities[category] ?? 0.5;
    }

    // Agar user slider 1.0 (100%) par bhi le jaye, toh DeepAR ko max 0.7 (70%) hi jayega
     if (category == TryOnCategory.eyeshadow){
        a = a * 0.9; // Eyeshadow ke liye thoda kam opacity, taake natural lage
     }else{
        a = a * 0.7; 
     }
   

    try {
      final colorVector = vector.Vector4(r, g, b, a);

      if (category == TryOnCategory.lipstick) {
        // 💄 LIPSTICK SETTINGS
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
          newParameter: 25.0, 
        );

      } else if (category == TryOnCategory.blush) {
        // 🌸 BLUSH SETTINGS
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_color',
          newParameter: colorVector, 
        );
        
      } else if (category == TryOnCategory.eyeshadow) {
        // 👁️ EYESHADOW SETTINGS
        // 🔴 Aapne bataya ke "Unlit Texture Color" shader use kiya hai.
        // Is shader mein color change karne ke liye parameter ka naam 'u_color' hota hai.
        _deepArController.changeParameter(
          gameObject: gameObject,
          component: 'MeshRenderer',
          parameter: 'u_color',
          newParameter: colorVector, 
        );
      }

      debugPrint("✅ Successfully applied realistic color to $gameObject");
    } catch (e) {
      debugPrint("❌ Apply failed for $gameObject: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSelectedColor = _selectedShades[_currentCategory];
    final currentIntensity = _intensities[_currentCategory] ?? 0.5;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── DEEP-AR CAMERA PREVIEW ──
          if (_isInitialized)
            DeepArPreview(_deepArController)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // ── TOP BAR ──
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // ── CATEGORY TABS ──
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _categoryTab("Lips", TryOnCategory.lipstick),
                _categoryTab("Blush", TryOnCategory.blush),
                // 🔴 6. Yahan Eyeshadow ka naya tab add kiya hai
                _categoryTab("EyeShadow", TryOnCategory.eyeshadow), 
              ],
            ),
          ),

          // ── BOTTOM PANEL (SHADES) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Intensity Slider
                  Row(
                    children: [
                      const Icon(Icons.opacity, color: Colors.white, size: 16),
                      Expanded(
                        child: Slider(
                          value: currentIntensity,
                          min: 0.1,
                          max: 1.0,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white30,
                          onChanged: currentSelectedColor == null
                              ? null 
                              : (val) {
                                  setState(() {
                                    _intensities[_currentCategory] = val;
                                  });
                                  _applyColorToDeepAR(currentSelectedColor, _currentCategory);
                                },
                        ),
                      ),
                    ],
                  ),

                  const Text(
                    "Select Shade",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 15),

                  // Shades List
                  SizedBox(
                    height: 60,
                    child: _currentShades.isEmpty
                        ? const Center(
                            child: Text("Loading shades...", style: TextStyle(color: Colors.white54)),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _currentShades.length + 1,
                            itemBuilder: (context, index) {
                              
                              // 🚫 Pehla Item: Clear Button
                              if (index == 0) {
                                final isCleared = currentSelectedColor == null;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedShades[_currentCategory] = null);
                                    _applyColorToDeepAR(null, _currentCategory);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 15),
                                    width: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isCleared ? Colors.white : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(Icons.block, color: Colors.white, size: 24),
                                  ),
                                );
                              }

                              // 🎨 Baqi Items: Database Shades
                              final shade = _currentShades[index - 1];
                              final isSelected = shade.color == currentSelectedColor;

                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedShades[_currentCategory] = shade.color);
                                  _applyColorToDeepAR(shade.color, _currentCategory);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 15),
                                  width: 50,
                                  decoration: BoxDecoration(
                                    color: shade.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? Colors.white : Colors.transparent,
                                      width: 3,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: shade.color.withOpacity(0.5),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTab(String label, TryOnCategory cat) {
    final isSelected = _currentCategory == cat;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentCategory = cat;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}