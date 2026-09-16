// lib/screens/post_history_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item.dart';
import '../services/supabase_service.dart' as services;
import '../theme/app_theme.dart';
import '../widgets/item_card.dart';
import 'item_detail_screen.dart';

/// The signed-in user's own past reports — reached from Profile's "History"
/// tile instead of living inline on the main Profile page.
class PostHistoryScreen extends StatefulWidget {
  const PostHistoryScreen({super.key});

  @override
  State<PostHistoryScreen> createState() => _PostHistoryScreenState();
}

class _PostHistoryScreenState extends State<PostHistoryScreen> {
  List<Item> myItems = [];
  bool loading = true;
  bool tabOpen = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => loading = true);
    try {
      final items = await services.SupabaseService.fetchItemsByUser(user.id);
      if (mounted) setState(() => myItems = items);
    } catch (e) {
      debugPrint('history load error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = tabOpen
        ? myItems.where((i) => !i.returned).toList()
        : myItems.where((i) => i.returned).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  PillTabBar(
                    items: [
                      PillTabItem(
                        label: 'My Reports',
                        selected: tabOpen,
                        onTap: () => setState(() => tabOpen = true),
                      ),
                      PillTabItem(
                        label: 'Resolved',
                        selected: !tabOpen,
                        onTap: () => setState(() => tabOpen = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (visibleItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          tabOpen
                              ? 'No open reports yet.'
                              : 'Nothing resolved yet.',
                          style: const TextStyle(color: AppColors.neutralGrey),
                        ),
                      ),
                    )
                  else
                    ...visibleItems.map(
                      (it) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ItemListCard(
                          item: it,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItemDetailScreen(item: it),
                            ),
                          ).then((_) => _load()),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
