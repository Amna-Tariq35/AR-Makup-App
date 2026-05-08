import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/app_colors.dart'; // AppColors import zaroori hai
import './saved_looks_screen.dart';
import 'try_on_screen.dart';
import './settings_screen.dart';
import './privacy_security_screen.dart';
import './edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool cameraPermission = false;
  bool notifications = true;
  bool isLoading = true;

  String userName = 'User';
  String userEmail = '';
  String avatarUrl = '';
  String initial = 'U';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          userEmail = user.email ?? 'No email';
          final metadata = user.userMetadata;
          
          if (metadata != null && metadata.containsKey('full_name')) {
            userName = metadata['full_name'];
          } else if (metadata != null && metadata.containsKey('name')) {
            userName = metadata['name'];
          } else if (userEmail.contains('@')) {
            String namePart = userEmail.split('@')[0];
            namePart = namePart.replaceAll(RegExp(r'[^a-zA-Z]'), ''); 
            
            if (namePart.isEmpty) {
              userName = 'User'; 
            } else {
              userName = namePart[0].toUpperCase() + namePart.substring(1).toLowerCase();
            }
          }

          if (metadata != null && metadata.containsKey('avatar_url')) {
            avatarUrl = metadata['avatar_url'];
          }
          if (userName.isNotEmpty) {
            initial = userName[0].toUpperCase();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _navigateToTryOn() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const TryOnScreen()),
      (route) => false,
    );
  }

  void _navigateToGallery() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const SavedLooksScreen()),
    );
  }

  Future<void> _openSettings() async {
  // 1. Settings screen par jao aur wapas aane ka wait karo
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const SettingsScreen()),
  );

  // 2. Jab user wapas aa jaye, toh ye line chalegi
  // Yahan apna refresh logic dalo (jaise setState ya data fetch function)
  setState(() {
    // Isse UI rebuild ho jayegi aur naya data dikhega
    print("User settings se wapas aa gaya, profile refresh ho rahi hai...");
  });
}

  void _openPrivacySecurity() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivacySecurityScreen()));
  }

  void _navigateToEditProfile() async {
    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => const EditProfileScreen())
    );
    
    if (result == true) {
      setState(() => isLoading = true); 
      await _fetchUserData(); 
    }
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.camera.status;
    setState(() {
      cameraPermission = status.isGranted;
    });
  }

  Future<void> _toggleCameraPermission(bool value) async {
    if (value) {
      final status = await Permission.camera.request();
      setState(() => cameraPermission = status.isGranted);
    } else {
      await openAppSettings();
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch $urlString')));
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );

      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Signed out successfully'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _navigateToTryOn();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          children: [
                            const SizedBox(height: 24),
                            _buildProfileInfo(),
                            const SizedBox(height: 32),
                            _buildSavedLooksShortcut(),
                            const SizedBox(height: 32),
                            _buildWebIntegrations(),
                            const SizedBox(height: 32),
                            _buildSettings(),
                            const SizedBox(height: 24),
                            _buildLogoutButton(),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildBottomNav(),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildIconButton(Icons.chevron_left, () => Navigator.pop(context)),
          Text(
            'Profile',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          _buildIconButton(Icons.settings_outlined, _openSettings),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Icon(icon, color: AppColors.textMain, size: 20),
        ),
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.surface,
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initial,
                        style: TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(Icons.camera_alt_outlined, color: AppColors.primary, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          userName,
          style: TextStyle(color: AppColors.textMain, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        const SizedBox(height: 4),
        Text(userEmail, style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _navigateToEditProfile,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: AppColors.surface,
            elevation: 0,
          ),
          child: const Text('Edit Profile', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildSavedLooksShortcut() {
    return GestureDetector(
      onTap: _navigateToGallery,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.image_outlined, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Saved Looks', style: TextStyle(color: AppColors.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('View your AR try-on gallery', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildWebIntegrations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'EXPLORE ON WEB',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ),
        GestureDetector(
          onTap: () => _launchUrl('https://tommie-mushy-noumenally.ngrok-free.dev/skin-analysis'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary, const Color(0xFFD88A9F)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Skin Analysis', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('Get personalized routines', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 10)),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, color: Colors.white.withOpacity(0.8), size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _launchUrl('https://tommie-mushy-noumenally.ngrok-free.dev/products'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
                  child: Icon(Icons.shopping_bag_outlined, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Web Store', style: TextStyle(color: AppColors.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('Shop products & saved looks', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, color: AppColors.textMuted, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'APP SETTINGS',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              _buildSettingTile(
                icon: Icons.camera_alt_outlined,
                title: 'Camera Access',
                subtitle: 'Required for AR Try-On',
                hasToggle: true,
                toggleValue: cameraPermission,
                onToggle: (val) => _toggleCameraPermission(val),
              ),
              Divider(height: 1, color: AppColors.border),
              _buildSettingTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Updates on saved looks',
                hasToggle: true,
                toggleValue: notifications,
                onToggle: (val) => setState(() => notifications = val),
              ),
              Divider(height: 1, color: AppColors.border),
              _buildSettingTile(
                icon: Icons.shield_outlined,
                title: 'Privacy & Security',
                hasToggle: false,
                onTap: _openPrivacySecurity,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon, required String title, String? subtitle, required bool hasToggle, bool toggleValue = false, ValueChanged<bool>? onToggle, VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: hasToggle ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ],
              ),
            ),
            if (hasToggle) _buildCustomToggle(toggleValue, onToggle!) else Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomToggle(bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value ? AppColors.primary : Colors.grey.shade300,
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 2, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleLogout,
        icon: Icon(Icons.logout, size: 18, color: AppColors.primary),
        label: Text(
          'Sign Out',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavItem(Icons.camera_alt_outlined, 'Try-On', false, _navigateToTryOn),
          _buildNavItem(Icons.image_outlined, 'Gallery', false, _navigateToGallery),
          _buildNavItem(Icons.person_outline, 'Profile', true, () {}),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? AppColors.primary : AppColors.textMuted, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textMuted,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}