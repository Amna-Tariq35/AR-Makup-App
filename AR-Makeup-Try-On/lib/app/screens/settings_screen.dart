import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; 
import '../utils/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String selectedLanguage = 'English (US)';
  bool isDarkMode = false;
  // Notifications abhi functional nahi hain toh flag hata diya hai

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = prefs.getString('app_language') ?? 'English (US)';
      isDarkMode = prefs.getBool('is_dark_mode') ?? false;
      AppColors.themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  Future<void> _launchHelpCenter() async {
    final Uri url = Uri.parse('https://www.google.com'); // Abhi testing ke liye google
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open browser. Check your internet connection.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Select Language', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['English (US)', 'Urdu (Coming Soon)', 'Hindi (Coming Soon)'].map((lang) {
            bool isComingSoon = lang.contains('Coming Soon');
            return ListTile(
              title: Text(lang, style: TextStyle(
                color: isComingSoon ? AppColors.textMuted : AppColors.textMain,
                fontStyle: isComingSoon ? FontStyle.italic : FontStyle.normal,
              )),
              trailing: selectedLanguage == lang ? Icon(Icons.check_circle, color: AppColors.primary) : null,
              onTap: isComingSoon ? null : () {
                setState(() => selectedLanguage = lang);
                _saveSetting('app_language', lang);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppColors.themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.textMain),
            title: Text('Settings', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600)),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('PREFERENCES', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    _buildInteractiveTile(Icons.language, 'Language', selectedLanguage, _showLanguageDialog),
                    Divider(height: 1, color: AppColors.border),
                    ListTile(
                      leading: Icon(Icons.dark_mode_outlined, color: AppColors.textMain),
                      title: Text('Dark Theme', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMain)),
                      trailing: Switch(
                        value: isDarkMode,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          AppColors.themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                          setState(() => isDarkMode = val);
                          _saveSetting('is_dark_mode', val);
                        },
                      ),
                    ),
                    Divider(height: 1, color: AppColors.border),
                    // Notifications par alert laga diya hai
                    _buildInteractiveTile(Icons.notifications_active_outlined, 'Notifications', 'Coming Soon', () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Notification settings will be available in the next update!', style: TextStyle(color: Colors.white)),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              Text('SUPPORT & ABOUT', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    _buildInteractiveTile(Icons.help_outline, 'Help Center', 'FAQs & Contact Support', _launchHelpCenter),
                    Divider(height: 1, color: AppColors.border),
                    _buildInteractiveTile(Icons.info_outline, 'About App', 'Version 1.0.0', () {
                      showAboutDialog(
                        context: context, 
                        applicationName: 'AR Makeup App', 
                        applicationVersion: 'v1.0.0', 
                        applicationLegalese: '© 2026 Your Company Name',
                        applicationIcon: Icon(Icons.auto_awesome, color: AppColors.primary, size: 40)
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInteractiveTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textMain),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMain)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}