// lib/widgets/item_card.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/item.dart';
import '../theme/app_theme.dart';

/// The published preview page shared items link to. A `foundify://` custom
/// scheme used to be the whole link, but custom schemes aren't auto-linked
/// (made tappable) by WhatsApp, SMS, Telegram, email, or almost any other
/// app's text renderer — only real http(s) links are, universally. This is
/// a real hosted page instead, so the link actually works wherever it's
/// shared; it also has no server behind it (it reads everything it shows
/// out of the URL's own query string, filled in by [itemShareLink] below),
/// so it works with no network call and no risk of showing stale data.
const String _shareLandingPageUrl =
    'https://claude.ai/code/artifact/ccde5d37-f810-40a3-a66a-a0c2352b6c55';

/// Builds a real, universally-clickable link for sharing one item — used by
/// the Share button on the feed card and item detail screen. Bakes the
/// item's own details into the URL so the landing page has something to
/// show immediately, with no fetch required.
String itemShareLink(Item item) {
  String trimmed(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  final params = <String, String>{
    'id': item.id,
    'title': trimmed(item.title, 120),
    'status': item.status,
    'state': item.returned ? 'resolved' : 'open',
    if ((item.category ?? '').isNotEmpty) 'category': item.category!,
    if (item.description.isNotEmpty) 'desc': trimmed(item.description, 300),
    if ((item.locationLabel ?? '').isNotEmpty) 'loc': item.locationLabel!,
    if (item.reward != null && item.reward! > 0)
      'reward': item.reward!.toStringAsFixed(0),
    if (item.createdAt != null) 't': item.createdAt!.toUtc().toIso8601String(),
  };

  final query = params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  return '$_shareLandingPageUrl?$query';
}

/// The actual message text put into the share sheet — a clear title line,
/// then the description, then the link, each its own paragraph rather than
/// run together, so it reads as a proper message in WhatsApp/SMS/etc
/// instead of a wall of text with a link stuck on the end.
String buildShareText(Item item) {
  final statusWord = item.status == 'lost' ? 'Lost' : 'Found';
  final parts = <String>['$statusWord: ${item.title}'];
  if (item.description.trim().isNotEmpty) {
    parts.add(item.description.trim());
  }
  parts.add(itemShareLink(item));
  return parts.join('\n\n');
}

String timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

const List<Color> _thumbColors = [
  AppColors.primary100,
  Color(0xFFDCEBFB),
  AppColors.accent100,
  AppColors.success100,
];

Color thumbColorFor(String id) =>
    _thumbColors[id.hashCode.abs() % _thumbColors.length];

/// List-style item card matching the Foundify home/search feed design.
class ItemListCard extends StatelessWidget {
  final Item item;
  final VoidCallback? onTap;
  const ItemListCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayImage = (item.imageUrls != null && item.imageUrls!.isNotEmpty)
        ? item.imageUrls!.first
        : item.imageUrl;
    final status = item.returned ? 'Resolved' : 'Open';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: thumbColorFor(item.id),
                  child: (displayImage != null && displayImage.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: displayImage,
                          fit: BoxFit.cover,
                          // This thumbnail only ever displays at 64x64 —
                          // decoding it at full upload resolution wastes
                          // memory and time for no visible gain.
                          memCacheWidth: 160,
                          placeholder: (_, __) => const SizedBox.shrink(),
                          errorWidget: (_, __, ___) => Icon(
                            categoryIcon(item.category ?? ''),
                            color: AppColors.primary500,
                          ),
                        )
                      : Icon(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if ((item.category ?? '').isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.category!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.neutralGrey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${item.locationLabel ?? (item.latitude != null ? 'Nearby' : 'Unknown location')} · ${timeAgo(item.createdAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.neutralGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
