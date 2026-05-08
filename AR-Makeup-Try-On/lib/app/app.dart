import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Ye line lazmi honi chahiye:
import './utils/app_colors.dart'; 
import './screens/welcome_screen.dart';
import './screens/camera_permission_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    // THEME BUILDER
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppColors.themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        
        return MaterialApp(
          title: 'AR Makeup Try-On',
          debugShowCheckedModeBanner: false,
          
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.background,
            primaryColor: AppColors.primary,
            colorScheme: AppColors.isDark 
                ? ColorScheme.dark(
                    primary: AppColors.primary,
                    secondary: AppColors.secondary,
                    surface: AppColors.surface,
                  )
                : ColorScheme.light(
                    primary: AppColors.primary,
                    secondary: AppColors.secondary,
                    surface: AppColors.surface,
                  ),
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: AppColors.textMain),
            ),
          ),
          
          home: session == null ? const WelcomeScreen() : const CameraPermissionScreen(),
        );
      },
    );
  }
}