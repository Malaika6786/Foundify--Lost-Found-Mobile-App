// lib/screens/safe_meetup_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';

/// Lets the proposer pick from previously-added community spots or add
/// their own — no fixed/hardcoded suggestions. Custom spots start
/// unverified and are labeled as such; there's no vetting step built yet.
class SafeMeetupScreen extends StatefulWidget {
  final String itemId;
  const SafeMeetupScreen({super.key, required this.itemId});

  @override
  State<SafeMeetupScreen> createState() => _SafeMeetupScreenState();
}

class _SafeMeetupScreenState extends State<SafeMeetupScreen> {
  List<Map<String, dynamic>> spots = [];
  int? selected;
  bool loading = true;
  bool submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await SupabaseService.listSafeSpots();
      if (mounted) {
        setState(() {
          spots = data;
          selected = data.isNotEmpty ? 0 : null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _addCustomSpot() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a Meetup Spot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Main Library entrance',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Well-lit, staffed until 9pm',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added != true || nameCtrl.text.trim().isEmpty) return;

    try {
      final spot = await SupabaseService.createSafeSpot(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty
            ? 'Added by you'
            : descCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          spots = [spot, ...spots];
          selected = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _propose() async {
    if (selected == null) return;
    setState(() => submitting = true);
    try {
      await SupabaseService.proposeMeetup(
        itemId: widget.itemId,
        safeSpotId: spots[selected!]['id'] as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Proposed ${spots[selected!]['name']} to the reporter.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Safe Meetup Spot')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: AppColors.primary500,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Pick a well-lit, public spot — or add your own below.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (spots.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No spots added yet — be the first.',
                            style: TextStyle(color: AppColors.neutralGrey),
                          ),
                        ),
                      ...spots.asMap().entries.map((e) {
                        final active = selected == e.key;
                        final verified = e.value['verified'] as bool;
                        return GestureDetector(
                          onTap: () => setState(() => selected = e.key),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary50
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary500
                                    : Colors.grey.shade300,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.neutral100,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    verified
                                        ? Icons.shield_outlined
                                        : Icons.storefront_outlined,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              e.value['name'] as String,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (!verified) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.neutral100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Unverified',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        e.value['description'] as String,
                                        style: const TextStyle(
                                          color: AppColors.neutralGrey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (active)
                                  const CircleAvatar(
                                    radius: 12,
                                    backgroundColor: AppColors.primary500,
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: _addCustomSpot,
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add a New Spot'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (selected == null || submitting)
                          ? null
                          : _propose,
                      child: Text(
                        submitting ? 'Proposing…' : 'Propose This Spot',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
