// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _avatarUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await SupabaseService.getProfile(user.id);
      if (!mounted) return;
      if (profile != null) {
        _usernameCtrl.text = profile['username'] ?? '';
        _phoneCtrl.text = profile['phone'] ?? '';
        setState(() => _avatarUrl = profile['avatar_url'] as String?);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await SupabaseService.pickImageFromGallery();
    if (picked == null) return;
    final (bytes, ext) = picked;

    setState(() => _saving = true);

    try {
      final url = await SupabaseService.uploadAvatar(bytes, ext);
      if (url != null) {
        await SupabaseService.updateProfile(avatarUrl: url);
        if (!mounted) return;
        setState(() => _avatarUrl = url);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Avatar updated')));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload avatar')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final name = _usernameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await SupabaseService.updateProfile(
        username: name,
        phone: _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAndUpload,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary500,
                    backgroundImage: _avatarUrl != null
                        ? NetworkImage(_avatarUrl!)
                        : null,
                    child: _avatarUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 48,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.accent500,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Username', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(hintText: 'Your display name'),
          ),
          const SizedBox(height: 16),
          const Text('Phone', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Shown to a finder/reporter only when they tap "Call" on a report of yours.',
            style: TextStyle(fontSize: 12, color: AppColors.neutralGrey),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '+1 555 0100'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
