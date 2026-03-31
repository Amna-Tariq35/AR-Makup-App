import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool cameraPermission = false;
  bool notifications = true;
  bool isLoading = true;

  // User Data Variables
  String userName = 'User';
  String userEmail = '';
  String avatarUrl = '';
  String initial = 'U';

  // Colors based on your rosy theme
  final Color primaryAccent = const Color(0xFFC06C84);
  final Color secondaryRose = const Color(0xFFF4C2C2);
  final Color bgColor = const Color(0xFFFAF7F5);
  final Color textColor = const Color(0xFF1F1F1F);
  final Color mutedText = const Color(0xFF8A8A8A);
  final Color borderColor = Colors.black.withOpacity(0.05);

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchUserData();
  }

  // 1. Fetch Real User Data from Supabase Auth (No profiles table)
  Future<void> _fetchUserData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          userEmail = user.email ?? 'No email';
          
          // Extract name from metadata (e.g., if signed in via Google)
          // Fallback to the part of the email before '@'
          final metadata = user.userMetadata;
          if (metadata != null && metadata.containsKey('full_name')) {
            userName = metadata['full_name'];
          } else if (metadata != null && metadata.containsKey('name')) {
            userName = metadata['name'];
          } else if (userEmail.contains('@')) {
            userName = userEmail.split('@')[0];
            // Capitalize first letter
            userName = userName[0].toUpperCase() + userName.substring(1);
          }

          // Extract avatar from metadata (e.g., Google profile picture)
          if (metadata != null && metadata.containsKey('avatar_url')) {
            avatarUrl = metadata['avatar_url'];
          } else if (metadata != null && metadata.containsKey('picture')) {
            avatarUrl = metadata['picture'];
          }

          // Set initial for fallback avatar
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

  // 2. Check Real Camera Permission
  Future<void> _checkPermissions() async {
    final status = await Permission.camera.status;
    setState(() {
      cameraPermission = status.isGranted;
    });
  }

  // 3. Toggle Camera Permission Logic
  Future<void> _toggleCameraPermission(bool value) async {
    if (value) {
      final status = await Permission.camera.request();
      setState(() => cameraPermission = status.isGranted);
    } else {
      // OS doesn't allow revoking permissions programmatically, so we open settings
      await openAppSettings();
    }
  }

  // 4. Launch Web URLs
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $urlString')),
        );
      }
    }
  }

  // 5. Logout Logic
  Future<void> _handleLogout() async {
    try {
      // Show loading indicator in dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator(color: primaryAccent)),
      );

      await Supabase.instance.client.auth.signOut();
      
      if (mounted) {
        // Close loading dialog
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Signed out successfully'),
            backgroundColor: primaryAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        
        // Navigate to TryOnScreen (assuming it's the main/home screen)
        // Adjust the route name based on your app's routing setup
        Navigator.of(context).pushNamedAndRemoveUntil('/try_on', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Navigation Helpers
  void _navigateToTryOn() {
    // Assuming '/try_on' is your route name for TryOnScreen
    Navigator.of(context).pushReplacementNamed('/try_on');
  }

  void _navigateToGallery() {
    // Assuming '/saved_looks' is your route name for SavedLooksScreen
    Navigator.of(context).pushReplacementNamed('/saved_looks');
  }

  void _openSettings() {
    // Placeholder for general settings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening General Settings...')),
    );
  }

  void _openPrivacySecurity() {
    // Placeholder for privacy settings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening Privacy & Security Settings...')),
    );
  }

  void _navigateToEditProfile() {
    // Navigate to Edit Profile Screen
    // Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfileScreen()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Navigating to Edit Profile...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: isLoading 
          ? Center(child: CircularProgressIndicator(color: primaryAccent))
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
              color: textColor,
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
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Icon(icon, color: textColor, size: 20),
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
                  colors: [primaryAccent, secondaryRose],
                ),
              ),
              child: CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white,
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty 
                    ? Text(
                        initial, 
                        style: TextStyle(color: primaryAccent, fontSize: 32, fontWeight: FontWeight.bold)
                      ) 
                    : null,
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.camera_alt_outlined, color: primaryAccent, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          userName,
          style: TextStyle(
            color: textColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          userEmail,
          style: TextStyle(color: mutedText, fontSize: 14),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _navigateToEditProfile,
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryAccent,
            side: BorderSide(color: primaryAccent.withOpacity(0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            backgroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text(
            'Edit Profile',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: secondaryRose.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.image_outlined, color: primaryAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Saved Looks',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'View your AR try-on gallery',
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: mutedText),
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
            style: TextStyle(
              color: mutedText,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Skin Analysis Banner -> Opens Ngrok URL
        GestureDetector(
          onTap: () => _launchUrl('https://tommie-mushy-noumenally.ngrok-free.dev/skin-analysis'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryAccent, const Color(0xFFD88A9F)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: primaryAccent.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI Skin Analysis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Get personalized routines',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, color: Colors.white.withOpacity(0.8), size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Web Store Banner -> Opens Ngrok URL
        GestureDetector(
          onTap: () => _launchUrl('https://tommie-mushy-noumenally.ngrok-free.dev/products'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shopping_bag_outlined, color: primaryAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Web Store',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Shop products & saved looks',
                        style: TextStyle(color: mutedText, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, color: mutedText, size: 16),
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
            style: TextStyle(
              color: mutedText,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
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
              Divider(height: 1, color: borderColor),
              _buildSettingTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Updates on saved looks',
                hasToggle: true,
                toggleValue: notifications,
                onToggle: (val) => setState(() => notifications = val),
              ),
              Divider(height: 1, color: borderColor),
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
    required IconData icon,
    required String title,
    String? subtitle,
    required bool hasToggle,
    bool toggleValue = false,
    ValueChanged<bool>? onToggle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: hasToggle ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: mutedText, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: mutedText, fontSize: 10),
                    ),
                  ]
                ],
              ),
            ),
            if (hasToggle)
              _buildCustomToggle(toggleValue, onToggle!)
            else
              Icon(Icons.chevron_right, color: mutedText, size: 20),
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
          color: value ? primaryAccent : Colors.grey.shade300,
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
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
        icon: Icon(Icons.logout, size: 18, color: primaryAccent),
        label: Text(
          'Sign Out',
          style: TextStyle(
            color: primaryAccent,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: primaryAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: borderColor)),
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
            Icon(
              icon,
              color: isActive ? primaryAccent : mutedText,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? primaryAccent : mutedText,
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