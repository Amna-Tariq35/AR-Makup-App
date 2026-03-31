import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Apni files ke correct paths yahan dalein:
import './utils/app_colors.dart';
import './screens/welcome_screen.dart';
import './screens/camera_permission_screen.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    // Check karein ke user ka session pehle se majood hai ya nahi
    final session = null;
    // Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'AR Makeup Try-On',
      debugShowCheckedModeBanner: false,
      
      // Global Theme Setup (Soft Rose & Light Elegant)
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        // Agar ap Google Fonts use kar rai hain toh yahan define kar sakti hain
        // fontFamily: 'Inter', 
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.textMain),
        ),
      ),
      
      // Routing Logic:
      // Agar user logged in NAHI hai -> Welcome Screen (Get Started / Sign In)
      // Agar user logged in HAI -> Camera Permission Screen
      home: session == null ? const WelcomeScreen() : const CameraPermissionScreen(),
    );
  }
}