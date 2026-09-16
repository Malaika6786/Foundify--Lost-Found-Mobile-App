// lib/screens/home_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item.dart';
import '../services/supabase_service.dart' as services;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/feed_post_card.dart';
import 'notifications_screen.dart';
import 'post_item_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  String tab = 'lost'; // lost | found
  List<Item> items = [];
  Map<String, services.ItemEngagement> engagement = {};
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  int returnedCount = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notifSub;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<AppState>().refreshUnreadCount();
    _loadReturnedCount();
    _scrollController.addListener(_onScroll);
    _subscribeToNotifications();
  }

  /// Live-updates the bell badge the instant a like/comment/message/match/
  /// new-post notification is inserted, instead of only refreshing on app
  /// start or after visiting the Notifications screen — see the note on
  /// AppState.setUnreadCount for why that was silently going stale.
  void _subscribeToNotifications() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    _notifSub = supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((rows) {
          if (!mounted) return;
          final unread = rows.where((r) => r['read'] != true).length;
          context.read<AppState>().setUnreadCount(unread);
        });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _notifSub?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!hasMore || isLoadingMore || isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      isLoading = true;
      hasMore = true;
    });
    try {
      final data = await services.SupabaseService.fetchItems(
        status: tab,
        limit: services.SupabaseService.defaultPageSize,
      );
      final eng = await services.SupabaseService.fetchEngagementForItems(
        data.map((i) => i.id).toList(),
      );
      if (mounted) {
        setState(() {
          items = data;
          engagement = eng;
          hasMore = data.length >= services.SupabaseService.defaultPageSize;
        });
      }
    } catch (e) {
      debugPrint('Error loading items: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => isLoadingMore = true);
    try {
      final data = await services.SupabaseService.fetchItems(
        status: tab,
        limit: services.SupabaseService.defaultPageSize,
        offset: items.length,
      );
      final eng = await services.SupabaseService.fetchEngagementForItems(
        data.map((i) => i.id).toList(),
      );
      if (mounted) {
        setState(() {
          items = [...items, ...data];
          engagement = {...engagement, ...eng};
          hasMore = data.length >= services.SupabaseService.defaultPageSize;
        });
      }
    } catch (e) {
      debugPrint('Error loading more items: $e');
    } finally {
      if (mounted) setState(() => isLoadingMore = false);
    }
  }

  Future<void> _loadReturnedCount() async {
    try {
      final count = await services.SupabaseService.countReturnedItems();
      if (mounted) setState(() => returnedCount = count);
    } catch (e) {
      debugPrint('Error loading returned count: $e');
    }
  }

  /// A genuinely compact Lost/Found toggle — sized to its own text content,
  /// not a full-width pill. Built directly (no `Expanded` inside) rather
  /// than reusing `PillTabBar` wrapped in `IntrinsicWidth`: that combination
  /// is a real Flutter layout conflict (`Expanded` needs a bounded width
  /// from its parent, `IntrinsicWidth` needs to measure content first),
  /// and produced exactly the squished/overlapping toggle seen in testing.
  Widget _compactToggle() {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary500 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? Colors.white : AppColors.neutralGrey,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('Lost', tab == 'lost', () => _switchTab('lost')),
          segment('Found', tab == 'found', () => _switchTab('found')),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      // Tightened from 20 to 14 — on a 320dp-wide phone (a real,
      // still-common budget device size, not just an edge case), the
      // previous fixed-width budget here (logo + toggle + two icon
      // buttons + this padding) left less than the brand name's own
      // rendered width, truncating it to "Foun…" even with the ellipsis
      // safety net doing its job. Every measurement in this header was
      // re-budgeted against a 320dp target, not just the 360dp one
      // checked before.
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          const FoundifyLogo(size: 24),
          const SizedBox(width: 4),
          // Expanded so the brand name is never the thing that gets
          // clipped off-screen — falls back to ellipsis only if a device
          // is narrower than the 320dp this is now budgeted for.
          Expanded(
            child: Text(
              'Foundify',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 17),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 2),
          _compactToggle(),
          const SizedBox(width: 2),
          _headerIconButton(
            tooltip: 'Search',
            icon: Icons.search,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 2),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _headerIconButton(
                tooltip: 'Notifications',
                icon: Icons.notifications_none,
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  );
                  if (context.mounted) {
                    context.read<AppState>().refreshUnreadCount();
                  }
                },
              ),
              if (context.watch<AppState>().unreadNotifications > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.accent500,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Same look as a default `IconButton` (white circle, light border) but
  /// sized to fit its icon (34x34) instead of Material's default 48x48
  /// minimum touch target — that extra padding on two adjacent buttons was
  /// the original cause of the header overflowing on narrow phones, and
  /// even 38x38 wasn't tight enough for a real 320dp-wide device.
  Widget _headerIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade200),
        ),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Caps the feed to a readable column width on tablet/Chromebook
        // instead of stretching one full-width mobile card across a 10-inch
        // screen — a no-op on phones (see lib/theme/responsive.dart).
        child: ResponsiveCenter(
          child: Column(
          children: [
            // Fixed — brand, tab toggle, search and notifications never
            // scroll away, unlike before where they lived inside the
            // scrolling list and disappeared as soon as you scrolled down.
            _buildHeader(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => Future.wait([_load(), _loadReturnedCount()]),
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.primary500,
                                    AppColors.primary700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.emoji_events_outlined,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$returnedCount item${returnedCount == 1 ? '' : 's'} reunited with their owners',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Center(child: BannerAdWidget()),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    if (isLoading)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => const _FeedCardSkeleton(),
                            childCount: 3,
                          ),
                        ),
                      )
                    else if (items.isEmpty)
                      SliverFillRemaining(child: _EmptyState(tab: tab))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            if (index == items.length) {
                              return hasMore
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }
                            final item = items[index];
                            return FeedPostCard(
                              item: item,
                              onChanged: () {
                                _load();
                                _loadReturnedCount();
                              },
                              engagement: engagement[item.id],
                            );
                          }, childCount: items.length + 1),
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent500,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PostItemScreen()),
          );
          _load();
          _loadReturnedCount();
        },
        icon: const Icon(Icons.add),
        label: const Text('Report Item'),
      ),
    );
  }

  void _switchTab(String value) {
    if (tab == value) return;
    setState(() => tab = value);
    _load();
  }
}

/// Loading placeholder matching FeedPostCard's layout, shown while the first
/// page of the feed loads — replaces a bare spinner with something that
/// reads as "content is coming" rather than "something might be broken".
class _FeedCardSkeleton extends StatelessWidget {
  const _FeedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block({double? width, double height = 14, double radius = 6}) {
      return Container(
        width: width,
        height: height,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                CircleAvatar(radius: 18, backgroundColor: AppColors.neutral100),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [block(width: 100), block(width: 60, height: 10)],
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 1,
            child: Container(color: AppColors.neutral100),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: block(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String tab;
  const _EmptyState({required this.tab});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No ${tab == 'lost' ? 'lost' : 'found'} items yet',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Be the first to report one — pull down to refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.neutralGrey),
            ),
          ],
        ),
      ),
    );
  }
}
