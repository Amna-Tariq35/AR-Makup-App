import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/utils/app_colors.dart';
import 'app/cache/looks_cache.dart';
import 'app/screens/welcome_screen.dart';
import 'app/screens/camera_permission_screen.dart';
import 'app/screens/try_on_screen.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Supabase.initialize(
    url: 'https://gzyjcfwcjibtrdhmojcn.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd6eWpjZndjamlidHJkaG1vamNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwODA4NjgsImV4cCI6MjA4NDY1Njg2OH0.D50ErvGX0Sif9n-EvwS9NYTxK08zZU-4TIIZm0UwhGM',
  );

  await _waitForInitialSession();

  final session = Supabase.instance.client.auth.currentSession;

  Widget initialScreen;
  if (session != null) {
    LooksCache.instance.prefetch(session.user.id);
    final cameraStatus = await Permission.camera.status;
    initialScreen = cameraStatus.isGranted
        ? const TryOnScreen()
        : const CameraPermissionScreen();
  } else {
    initialScreen = const WelcomeScreen();
  }

  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedOut) {
      LooksCache.instance.clear();
    }
  });

  await AppColors.initTheme();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          AppColors.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          AppColors.isDark ? Brightness.light : Brightness.dark,
    ),
  );

  // Sab resolve — ab splash hatao aur app dikhaо
  FlutterNativeSplash.remove();

  runApp(ProviderScope(child: MyApp(initialScreen: initialScreen)));
}

Future<void> _waitForInitialSession() async {
  final completer = Completer<void>();

  final sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.initialSession) {
      if (!completer.isCompleted) completer.complete();
    }
  });

  await completer.future.timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );

  await sub.cancel();
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return AppRoot(initialScreen: initialScreen);
  }
}