// lib/screens/possible_matches_screen.dart
import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart';
import 'home_shell.dart';
import 'item_detail_screen.dart';

/// Shows matches computed server-side by the `findit_score_new_item`
/// Postgres trigger (title similarity via pg_trgm + category match), stored
/// in `item_matches`. See supabase/migrations/0001_findit_full_backend.sql.
class PossibleMatchesScreen extends StatefulWidget {
  final String lostItemId;
  const PossibleMatchesScreen({super.key, required this.lostItemId});

  @override
  State<PossibleMatchesScreen> createState() => _PossibleMatchesScreenState();
}

class _PossibleMatchesScreenState extends State<PossibleMatchesScreen> {
  bool loading = true;
  List<Map<String, dynamic>> matches = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await SupabaseService.listMatchesForLostItem(
        widget.lostItemId,
      );
      if (mounted) setState(() => matches = data);
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

  Future<void> _dismiss(String matchId) async {
    setState(() => matches.removeWhere((m) => m['id'] == matchId));
    try {
      await SupabaseService.dismissMatch(matchId);
    } catch (_) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeShell()),
            (r) => false,
          ),
        ),
        title: const Text('Possible Matches'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary500,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(
                                text: 'AI Match Scan ',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const TextSpan(
                                text:
                                    'compared your report against nearby found items. Review the closest matches below.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No matches yet',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "We'll notify you the instant a matching item is posted.",
                          style: TextStyle(color: AppColors.neutralGrey),
                        ),
                      ],
                    ),
                  )
                else
                  ...matches.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _MatchCard(
                        item: Item.fromMap(
                          Map<String, dynamic>.from(m['found'] as Map),
                        ),
                        score: m['score'] as int,
                        onNotAMatch: () => _dismiss(m['id'] as String),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        color: AppColors.neutralGrey,
                        fontSize: 13,
                      ),
                      children: [
                        TextSpan(
                          text: "No match yet? We'll keep scanning and ",
                        ),
                        TextSpan(
                          text: 'notify you automatically',
                          style: TextStyle(
                            color: AppColors.primary500,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Item item;
  final int score;
  final VoidCallback onNotAMatch;
  const _MatchCard({
    required this.item,
    required this.score,
    required this.onNotAMatch,
  });

  @override
  Widget build(BuildContext context) {
    final isStrong = score >= 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: thumbColorFor(item.id),
                    child: Icon(
                      categoryIcon(item.category ?? ''),
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
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Found · ${item.locationLabel ?? 'Nearby'} · ${timeAgo(item.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.neutralGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isStrong
                        ? AppColors.success100
                        : AppColors.accent100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      if (isStrong)
                        const Icon(
                          Icons.check,
                          size: 14,
                          color: AppColors.success500,
                        ),
                      if (isStrong) const SizedBox(width: 4),
                      Text(
                        '$score% match',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isStrong
                              ? AppColors.success500
                              : AppColors.accent500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onNotAMatch,
                    child: const Text('Not a Match'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: isStrong
                      ? ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          ),
                          child: const Text('This Is Mine'),
                        )
                      : OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: item),
                            ),
                          ),
                          child: const Text('View Item'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
