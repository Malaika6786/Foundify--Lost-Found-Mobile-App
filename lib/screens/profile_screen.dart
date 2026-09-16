// lib/screens/profile_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/push_service.dart';
import '../services/supabase_service.dart' as services;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import 'edit_profile_screen.dart';
import 'alert_radius_screen.dart';
import 'item_tags_screen.dart';
import 'onboarding_screen.dart';
import 'post_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = Supabase.instance.client;
  bool loading = true;
  bool notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => loading = true);
    try {
      await context.read<AppState>().loadProfile(user.id);
      final p = context.read<AppState>().profile;
      if (mounted) {
        setState(() {
          notificationsEnabled = (p?['notifications_enabled'] as bool?) ?? true;
        });
      }
    } catch (e) {
      debugPrint('profile load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signOut() async {
    await PushService.unregisterCurrentDevice();
    await services.SupabaseService.signOut();
    if (mounted) {
      context.read<AppState>().clear();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (r) => false,
      );
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will submit a request to permanently delete your account and reports. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error500),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await services.SupabaseService.deleteAccount();
      if (!mounted) return;
      context.read<AppState>().clear();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (r) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final profile = context.watch<AppState>().profile;
    final username =
        profile?['username'] ??
        profile?['full_name'] ??
        user?.email?.split('@').first ??
        'User';
    final avatarUrl = profile?['avatar_url'] as String?;

    return Scaffold(
      body: SafeArea(
        child: ResponsiveCenter(child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  // Extra bottom inset so "Delete Account" isn't hidden
                  // behind the floating bottom nav bar (HomeShell uses
                  // extendBody: true).
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  children: [
                    Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: AppColors.primary500,
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? CachedNetworkImageProvider(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(
                                      username.toString().isNotEmpty
                                          ? username.toString()[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EditProfileScreen(),
                                  ),
                                ).then((_) => _load()),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent500,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username.toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '',
                                style: const TextStyle(
                                  color: AppColors.neutralGrey,
                                ),
                              ),
                              if (user?.createdAt != null)
                                Text(
                                  'Member since ${DateTime.tryParse(user!.createdAt)?.year ?? ''}',
                                  style: const TextStyle(
                                    color: AppColors.neutralGrey,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _settingsTile(
                      icon: Icons.history,
                      label: 'History',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PostHistoryScreen(),
                        ),
                      ),
                    ),
                    _settingsTile(
                      icon: Icons.notifications_none,
                      label: 'Notifications',
                      trailing: Switch(
                        value: notificationsEnabled,
                        activeThumbColor: AppColors.primary500,
                        onChanged: (v) async {
                          setState(() => notificationsEnabled = v);
                          await services.SupabaseService.updateProfile(
                            notificationsEnabled: v,
                          );
                        },
                      ),
                    ),
                    _settingsTile(
                      icon: Icons.gps_fixed,
                      label: 'Alert Radius',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AlertRadiusScreen(),
                        ),
                      ),
                    ),
                    _settingsTile(
                      icon: Icons.qr_code_2,
                      label: 'My Item Tags',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ItemTagsScreen(),
                        ),
                      ),
                    ),
                    _settingsTile(
                      icon: Icons.logout,
                      label: 'Log Out',
                      onTap: _signOut,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _confirmDeleteAccount,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              color: AppColors.error500,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Delete Account',
                              style: TextStyle(
                                color: AppColors.error500,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right, color: AppColors.neutralGrey),
          ],
        ),
      ),
    );
  }
}
