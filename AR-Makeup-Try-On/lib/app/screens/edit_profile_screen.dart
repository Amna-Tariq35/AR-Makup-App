import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/app_colors.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String? _avatarUrl;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && user.userMetadata != null) {
      _nameController.text = user.userMetadata!['full_name'] ?? '';
      setState(() {
        _avatarUrl = user.userMetadata!['avatar_url'];
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      String finalAvatarUrl = _avatarUrl ?? '';

      if (_imageFile != null) {
        final fileExt = _imageFile!.path.split('.').last;
        final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final filePath = fileName;

        await Supabase.instance.client.storage.from('avatars').upload(filePath, _imageFile!);
        finalAvatarUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(filePath);
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {
          'full_name': _nameController.text.trim(),
          'avatar_url': finalAvatarUrl,
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.primary));
        Navigator.pop(context, true); 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating profile: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textMain),
        title: Text('Edit Profile', style: TextStyle(color: AppColors.textMain, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
               child: GestureDetector(
                 onTap: _pickImage,
                 child: Stack(
                   children: [
                     CircleAvatar(
                       radius: 55,
                       backgroundColor: AppColors.secondary.withOpacity(0.5),
                       backgroundImage: _imageFile != null 
                           ? FileImage(_imageFile!) as ImageProvider
                           : (_avatarUrl != null && _avatarUrl!.isNotEmpty ? NetworkImage(_avatarUrl!) : null),
                       child: (_imageFile == null && (_avatarUrl == null || _avatarUrl!.isEmpty)) 
                           ? const Icon(Icons.person, size: 55, color: AppColors.primary) 
                           : null,
                     ),
                     Positioned(
                       bottom: 0,
                       right: 0,
                       child: Container(
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                         child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                       ),
                     )
                   ],
                 ),
               ),
            ),
            const SizedBox(height: 40),
            Text('Full Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(color: AppColors.textMain),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: _isLoading 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}