// lib/widgets/feed_post_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../screens/comments_screen.dart';
import '../screens/item_detail_screen.dart';
import 'item_card.dart' show timeAgo, thumbColorFor, buildShareText;

/// Instagram-style feed post: header, full-width photo, like/comment/share
/// row, caption, comment count — used by the Home feed.
class FeedPostCard extends StatefulWidget {
  final Item item;
  final VoidCallback? onChanged;

  /// Pre-fetched like/comment state for this item, batched by the parent
  /// screen (see SupabaseService.fetchEngagementForItems) so each card
  /// doesn't fire its own 3 queries. Falls back to per-card fetching if
  /// omitted, for callers that don't batch.
  final ItemEngagement? engagement;
  const FeedPostCard({
    super.key,
    required this.item,
    this.onChanged,
    this.engagement,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  bool liked = false;
  int likeCount = 0;
  int commentCount = 0;
  bool loadingCounts = true;

  @override
  void initState() {
    super.initState();
    final e = widget.engagement;
    if (e != null) {
      liked = e.liked;
      likeCount = e.likeCount;
      commentCount = e.commentCount;
      loadingCounts = false;
    } else {
      _loadCounts();
    }
  }

  @override
  void didUpdateWidget(covariant FeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final e = widget.engagement;
    if (e != null && e != oldWidget.engagement) {
      setState(() {
        liked = e.liked;
        likeCount = e.likeCount;
        commentCount = e.commentCount;
        loadingCounts = false;
      });
    }
  }

  Future<void> _loadCounts() async {
    try {
      final results = await Future.wait([
        SupabaseService.hasUserLiked(widget.item.id),
        SupabaseService.countLikes(widget.item.id),
        SupabaseService.countComments(widget.item.id),
      ]);
      if (mounted) {
        setState(() {
          liked = results[0] as bool;
          likeCount = results[1] as int;
          commentCount = results[2] as int;
          loadingCounts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadingCounts = false);
    }
  }

  Future<void> _toggleLike() async {
    setState(() {
      liked = !liked;
      likeCount += liked ? 1 : -1;
    });
    try {
      await SupabaseService.toggleLike(widget.item.id);
    } catch (e) {
      // Roll back on failure.
      if (mounted) {
        setState(() {
          liked = !liked;
          likeCount += liked ? 1 : -1;
        });
      }
    }
  }

  void _openComments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CommentsScreen(itemId: widget.item.id)),
    );
    _loadCounts();
  }

  void _share() {
    Share.share(buildShareText(widget.item), subject: widget.item.title);
  }

  void _openDetail() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: widget.item)),
    );
    widget.onChanged?.call();
    _loadCounts();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final images = (item.imageUrls != null && item.imageUrls!.isNotEmpty)
        ? item.imageUrls!
        : (item.imageUrl != null && item.imageUrl!.isNotEmpty
              ? [item.imageUrl!]
              : <String>[]);
    final status = item.returned ? 'Resolved' : 'Open';

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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: thumbColorFor(item.id),
                  backgroundImage:
                      (item.avatarUrl != null && item.avatarUrl!.isNotEmpty)
                      ? CachedNetworkImageProvider(item.avatarUrl!)
                      : null,
                  child: (item.avatarUrl == null || item.avatarUrl!.isEmpty)
                      ? const Icon(
                          Icons.person,
                          size: 18,
                          color: AppColors.primary700,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.username ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${item.locationLabel ?? 'Nearby'} · ${timeAgo(item.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.neutralGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                // The status pill looks like a button (pill shape, color,
                // shadow) but used to do nothing when tapped. Wrapped so it
                // actually responds — opening the post, same as tapping the
                // photo — instead of sitting there inert.
                GestureDetector(
                  onTap: _openDetail,
                  child: StatusBadge(status: status),
                ),
              ],
            ),
          ),
          // Photo
          GestureDetector(
            onTap: _openDetail,
            child: AspectRatio(
              aspectRatio: 1,
              child: images.isEmpty
                  ? Container(
                      color: thumbColorFor(item.id),
                      child: Center(
                        child: Icon(
                          categoryIcon(item.category ?? ''),
                          size: 64,
                          color: AppColors.primary500,
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: images.first,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      // Capped to a realistic feed-card render size — this
                      // is what actually made scrolling feel slow, since
                      // every card was decoding a full-resolution upload
                      // just to show it at phone-screen width.
                      memCacheWidth: 800,
                      placeholder: (_, __) =>
                          Container(color: thumbColorFor(item.id)),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image, size: 48),
                        ),
                      ),
                    ),
            ),
          ),
          // Action row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: liked ? 'Unlike' : 'Like',
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? AppColors.error500 : AppColors.ink,
                  ),
                  onPressed: _toggleLike,
                ),
                Text(
                  '$likeCount',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Comments',
                  icon: const Icon(Icons.mode_comment_outlined),
                  onPressed: _openComments,
                ),
                Text(
                  '$commentCount',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _share,
                ),
                const Spacer(),
                if ((item.category ?? '').isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.category!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Caption
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(color: AppColors.ink, fontSize: 14),
                    children: [
                      TextSpan(
                        text: '${item.title}  ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: item.description),
                    ],
                  ),
                ),
                if (commentCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GestureDetector(
                      onTap: _openComments,
                      child: Text(
                        'View all $commentCount comments',
                        style: const TextStyle(
                          color: AppColors.neutralGrey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
