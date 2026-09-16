// lib/screens/claim_item_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';

/// Institution drop-off pickup flow, backed by the real `claims` and
/// `institution_partners` tables. The claimant picks from real,
/// user-submitted drop-off locations (or adds their own) — no hardcoded
/// "the" partner. The pickup code is generated server-side and stored per
/// item so it survives app restarts and is visible to both the claimant and
/// the item's owner (RLS-scoped).
class ClaimItemScreen extends StatefulWidget {
  final Item item;
  const ClaimItemScreen({super.key, required this.item});

  @override
  State<ClaimItemScreen> createState() => _ClaimItemScreenState();
}

class _ClaimItemScreenState extends State<ClaimItemScreen> {
  Map<String, dynamic>? claim;
  Map<String, dynamic>? partner;
  List<Map<String, dynamic>> partners = [];
  int? selectedPartner;
  bool loading = true;
  bool starting = false;
  bool confirming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final existing = await SupabaseService.getExistingClaim(widget.item.id);
      if (existing != null) {
        final res = await SupabaseService.supabase
            .from('institution_partners')
            .select()
            .eq('id', existing['partner_id'])
            .maybeSingle();
        if (mounted) {
          setState(() {
            claim = existing;
            partner = res == null
                ? null
                : Map<String, dynamic>.from(res as Map);
          });
        }
      } else {
        final list = await SupabaseService.listInstitutionPartners();
        if (mounted) {
          setState(() {
            partners = list;
            selectedPartner = list.isNotEmpty ? 0 : null;
          });
        }
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

  Future<void> _addCustomPartner() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add a Drop-off Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Central Library front desk',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressCtrl,
              decoration: const InputDecoration(
                hintText: 'Address or location description',
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
      final p = await SupabaseService.createInstitutionPartner(
        name: nameCtrl.text.trim(),
        address: addressCtrl.text.trim().isEmpty
            ? 'Added by you'
            : addressCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          partners = [p, ...partners];
          selectedPartner = 0;
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

  Future<void> _startClaim() async {
    if (selectedPartner == null) return;
    setState(() => starting = true);
    try {
      final c = await SupabaseService.createClaim(
        itemId: widget.item.id,
        partnerId: partners[selectedPartner!]['id'] as String,
      );
      if (mounted) {
        setState(() {
          claim = c;
          partner = partners[selectedPartner!];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> _confirmPickup() async {
    if (claim == null) return;
    setState(() => confirming = true);
    try {
      await SupabaseService.confirmPickup(
        claim!['id'] as String,
        widget.item.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup confirmed — item resolved.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  String get _formattedCode {
    final code = claim?['pickup_code'] as String? ?? '';
    return code.split('').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Claim Your Item')),
      body: claim == null ? _buildPickPartner() : _buildPickupSteps(),
    );
  }

  Widget _buildPickPartner() {
    return Column(
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
                    Icon(Icons.info_outline, color: AppColors.primary500),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Where will you meet to hand this item off? Pick a location, or add the desk/office where it's actually being held.",
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (partners.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No drop-off locations added yet — be the first.',
                    style: TextStyle(color: AppColors.neutralGrey),
                  ),
                ),
              ...partners.asMap().entries.map((e) {
                final active = selectedPartner == e.key;
                final verified = e.value['verified'] as bool;
                return GestureDetector(
                  onTap: () => setState(() => selectedPartner = e.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary50 : Colors.white,
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
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.neutral100,
                                        borderRadius: BorderRadius.circular(8),
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
                                e.value['address'] as String,
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
                onPressed: _addCustomPartner,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add a Drop-off Location'),
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
              onPressed: (selectedPartner == null || starting)
                  ? null
                  : _startClaim,
              child: Text(starting ? 'Starting…' : 'Start Claim'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPickupSteps() {
    final status = claim?['status'] as String? ?? 'pending';
    final isPickedUp = status == 'picked_up';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.neutral100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.inventory_2_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            partner?['name'] as String? ?? 'Drop-off location',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            partner?['address'] as String? ?? '',
                            style: const TextStyle(
                              color: AppColors.neutralGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (partner?['verified'] == true)
                      const Icon(
                        Icons.star,
                        color: AppColors.success500,
                        size: 18,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 56,
                      height: 56,
                      color: AppColors.primary100,
                      child:
                          (widget.item.imageUrl != null &&
                              widget.item.imageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: widget.item.imageUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 140,
                            )
                          : const Icon(
                              Icons.inventory_2_outlined,
                              color: AppColors.primary500,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'Show the code below at the location above',
                          style: TextStyle(
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
                'PICKUP STEPS',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.neutralGrey,
                ),
              ),
              const SizedBox(height: 12),
              _step(1, 'Claim started', 'Location confirmed', done: true),
              _stepConnector(),
              _step(
                2,
                'Show this pickup code at the desk',
                null,
                current: !isPickedUp,
              ),
              if (!isPickedUp)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 8, bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary100),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _formattedCode,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              _stepConnector(),
              _step(
                3,
                'Confirm pickup in the app',
                'Marks the item resolved',
                done: isPickedUp,
                pending: !isPickedUp,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isPickedUp || confirming ? null : _confirmPickup,
              child: Text(
                isPickedUp
                    ? 'Picked up'
                    : (confirming ? 'Confirming…' : 'Confirm Pickup'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _step(
    int n,
    String title,
    String? subtitle, {
    bool done = false,
    bool current = false,
    bool pending = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done
              ? AppColors.success500
              : (current ? AppColors.primary500 : AppColors.neutral100),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: current ? Colors.white : AppColors.neutralGrey,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pending ? AppColors.neutralGrey : AppColors.ink,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.neutralGrey,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepConnector() => Padding(
    padding: const EdgeInsets.only(left: 13.5),
    child: Container(width: 1, height: 20, color: Colors.grey.shade300),
  );
}
