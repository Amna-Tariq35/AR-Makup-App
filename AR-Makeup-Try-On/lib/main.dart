import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/utils/app_colors.dart'; // 🔴 NAYA IMPORT: AppColors ke liye

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://gzyjcfwcjibtrdhmojcn.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd6eWpjZndjamlidHJkaG1vamNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwODA4NjgsImV4cCI6MjA4NDY1Njg2OH0.D50ErvGX0Sif9n-EvwS9NYTxK08zZU-4TIIZm0UwhGM',
  );

  // 🔴 NAYI LINE: Ye app start hote hi Theme load kar legi
  await AppColors.initTheme();

  // Edge-to-edge UI for a modern, elegant look
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // UPDATED: Theme ke hisaab se status bar icons ko adjust karega
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Agar Dark mode hai toh white icons (light), warna black icons (dark)
      statusBarIconBrightness: AppColors.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: AppColors.isDark ? Brightness.light : Brightness.dark,
    ),
  );

  // ProviderScope ko root par wrap karna best practice hai
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppRoot();
  }
}