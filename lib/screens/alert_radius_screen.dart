// lib/screens/alert_radius_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';

class AlertRadiusScreen extends StatefulWidget {
  const AlertRadiusScreen({super.key});

  @override
  State<AlertRadiusScreen> createState() => _AlertRadiusScreenState();
}

class _AlertRadiusScreenState extends State<AlertRadiusScreen> {
  double radius = 3;
  Set<String> watched = {'Bags', 'Wallet'};
  bool push = true;
  bool aiOnly = false;
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SupabaseService.getAlertPrefs();
      if (mounted) {
        setState(() {
          radius = (prefs['radius_km'] as num).toDouble();
          watched = Set<String>.from(prefs['categories'] as List);
          push = prefs['push_enabled'] as bool;
          aiOnly = prefs['ai_only'] as bool;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await SupabaseService.saveAlertPrefs(
        radiusKm: radius,
        categories: watched.toList(),
        pushEnabled: push,
        aiOnly: aiOnly,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
      setState(() => saving = false);
      return;
    }
    if (mounted) {
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Alert saved')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Alert Radius')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.primary50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary100),
                  ),
                  child: Center(
                    child: Container(
                      width: 40 + radius * 12,
                      height: 40 + radius * 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary500,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        color: AppColors.primary100.withOpacity(0.4),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 6,
                          backgroundColor: AppColors.primary500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "You'll be alerted the instant a matching item is posted inside this circle.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.neutralGrey),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'Radius',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${radius.round()} km',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary500,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: radius,
                  min: 1,
                  max: 25,
                  divisions: 24,
                  activeColor: AppColors.primary500,
                  onChanged: (v) => setState(() => radius = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Watch Categories',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kItemCategories.map((c) {
                    final selected = watched.contains(c);
                    return CategoryChip(
                      label: c,
                      selected: selected,
                      onTap: () => setState(
                        () => selected ? watched.remove(c) : watched.add(c),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_none),
                  title: const Text(
                    'Push notifications',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  value: push,
                  activeThumbColor: AppColors.primary500,
                  onChanged: (v) => setState(() => push = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.auto_awesome),
                  title: const Text(
                    'Include AI-matched items only',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  value: aiOnly,
                  activeThumbColor: AppColors.primary500,
                  onChanged: (v) => setState(() => aiOnly = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Saving…' : 'Save Alert'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
