import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_colors.dart';
import 'camera_permission_screen.dart';
import 'dart:async';

class AuthScreen extends StatefulWidget {
  final bool isLoginMode;
  const AuthScreen({super.key, this.isLoginMode = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool isSignIn;
  bool isLoading = false;
  bool isGoogleLoading = false;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  StreamSubscription<AuthState>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    isSignIn = widget.isLoginMode;
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        if (mounted) {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (_) => const CameraPermissionScreen())
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleAuth() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    setState(() => isLoading = true);
    try {
      if (isSignIn) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      } else {
        await Supabase.instance.client.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        if (!isSignIn && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Check your email for confirmation link!"), backgroundColor: Colors.green),
          );
        }
      }
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CameraPermissionScreen()));
      }
    } on AuthException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("An unexpected error occurred")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() => isGoogleLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.flutter://login-callback/',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Google Sign-In Error: $e")));
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textMain),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSignIn ? 'Welcome Back' : 'Create Account',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textMain),
                ),
                const SizedBox(height: 8),
                Text(
                  isSignIn ? 'Sign in to access your saved looks.' : 'Join us to save your favorite AR makeup looks.',
                  style: TextStyle(fontSize: 16, color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 40),

                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailController, 
                        keyboardType: TextInputType.emailAddress, 
                        style: TextStyle(color: AppColors.textMain),
                        decoration: _inputDecoration('you@example.com')
                      ),
                      const SizedBox(height: 20),
                      
                      Text('Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: passwordController, 
                        obscureText: true, 
                        style: TextStyle(color: AppColors.textMain),
                        decoration: _inputDecoration('••••••••')
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(isSignIn ? 'Sign In' : 'Sign Up', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.border)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text("OR", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: AppColors.border)),
                        ],
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: isGoogleLoading ? null : signInWithGoogle,
                          icon: isGoogleLoading 
                            ? const SizedBox.shrink()
                            : Image.network('https://img.icons8.com/color/48/000000/google-logo.png', width: 24, height: 24),
                          label: isGoogleLoading
                              ? const CircularProgressIndicator(color: AppColors.primary)
                              : Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            side: BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isSignIn ? "Don't have an account? " : "Already have an account? ", style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
                    GestureDetector(
                      onTap: () => setState(() => isSignIn = !isSignIn),
                      child: const Text('Sign Up', style: TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    );
  }
}