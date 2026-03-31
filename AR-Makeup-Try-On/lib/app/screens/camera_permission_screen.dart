import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/app_colors.dart';
import '../../features/try_on/try_on_screen.dart'; // Apni DeepAR wali screen import karein

class CameraPermissionScreen extends StatelessWidget {
  const CameraPermissionScreen({super.key});

 Future<void> requestCameraPermission(BuildContext context) async {
  // Camera permission request karein
  var status = await Permission.camera.request();

  if (status.isGranted) {
    // 2. Permission mil gayi! Ab redirect karein
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TryOnScreen()), // Apni screen ka sahi naam check kar lein
      );
    }
  } else if (status.isPermanentlyDenied) {
    // Agar user ne "Don't ask again" kiya ho toh settings khulwani parengi
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Camera permission is permanently denied. Please enable it in settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
  } else {
    // Normal deny
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera access is required for AR Try-On')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Soft Rose Icon Container
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined, size: 60, color: AppColors.primary),
                    ),
                    const SizedBox(height: 40),
                    
                    const Text(
                      'Allow Camera Access',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textMain),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'To apply virtual makeup and analyze your skin in real-time, we need access to your camera. Your video stream is processed locally and never stored.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: AppColors.textMuted, height: 1.5),
                    ),
                  ],
                ),
              ),
              
              // Footer Buttons
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => requestCameraPermission(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Allow Camera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
              
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can enable it later in settings.')));
                },
                child: const Text('Maybe Later', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}