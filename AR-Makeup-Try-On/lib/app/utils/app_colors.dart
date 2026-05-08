import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Ye package import karein

class AppColors {
  // Theme state ko globally manage karne ke liye Notifier
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

  // Helper method check karne ke liye ke dark mode on hai ya nahi
  static bool get isDark => themeNotifier.value == ThemeMode.dark;

  // 🔴 NAYA FUNCTION: Jo app start hote hi memory read karega
  static Future<void> initTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }

  // Main Brand Colors
  static const Color primary = Color(0xFFC06C84);
  static const Color secondary = Color(0xFFF4C2C2);

  // Background aur Text colors
  static Color get background => isDark ? const Color(0xFF121212) : const Color(0xFFFAF7F5);
  static Color get surface => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get textMain => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1F1F1F);
  static Color get textMuted => isDark ? const Color(0xFFA0A0A0) : const Color(0xFF8A8A8A);
  static Color get border => isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);
}