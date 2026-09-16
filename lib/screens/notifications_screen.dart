// lib/screens/notifications_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart';
import 'chat_screen.dart';
import 'item_detail_screen.dart';

IconData _iconForType(String type) {
  switch (type) {
    case 'match':
      return Icons.auto_awesome;
    case 'message':
      return Icons.chat_bubble_outline;
    case 'resolved':
      return Icons.check_circle_outline;
    case 'flag':
      return Icons.flag_outlined;
    case 'like':
      return Icons.favorite_outline;
    case 'comment':
      return Icons.mode_comment_outlined;
    case 'new_post':
      return Icons.dynamic_feed_outlined;
    default:
      return Icons.notifications_none;
  }
}

Color _colorForType(String type) {
  switch (type) {
    case 'match':
      return AppColors.accent500;
    case 'resolved':
      return AppColors.success500;
    case 'message':
      return AppColors.success500;
    case 'like':
      return AppColors.error500;
    case 'comment':
      return AppColors.primary500;
    default:
      return AppColors.neutralGrey;
  }
}

/// One row rendered on this screen — either a single notification (like,
/// comment, match, resolved, new post) or a whole group of "message" rows
/// from the same sender folded into one WhatsApp-style entry ("3 messages
/// from Jordan"), so a burst of chat messages doesn't flood the list with
/// duplicate rows.
class _DisplayEntry {
  final bool isMessageGroup;
  final List<Map<String, dynamic>> rows; // 1 for non-message, N for a group
  final DateTime sortDate;
  final bool unread;
  String? senderUsername;
  String? senderAvatarUrl;

  _DisplayEntry({
    required this.isMessageGroup,
    required this.rows,
    required this.sortDate,
    required this.unread,
  });

  Map<String, dynamic> get latest => rows.first;
  String? get senderId => latest['related_user_id'] as String?;
}

/// Real notification feed, backed by the `notifications` table. Rows are
/// inserted server-side by Postgres triggers (new match, new message, new
/// like, new comment, new post, item resolved) — see
/// supabase/migrations/0001_findit_full_backend.sql and
/// supabase/migrations/0015_notifications_upgrade_and_claim_fix.sql.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  List<_DisplayEntry> entries = [];
  bool loading = true;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await SupabaseService.listNotifications();
      final built = await _buildEntries(data);
      if (mounted) {
        setState(() {
          items = data;
          entries = built;
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

  Future<List<_DisplayEntry>> _buildEntries(
    List<Map<String, dynamic>> data,
  ) async {
    final result = <_DisplayEntry>[];
    final messagesBySender = <String, List<Map<String, dynamic>>>{};

    for (final n in data) {
      if (n['type'] == 'message' && n['related_user_id'] != null) {
        messagesBySender
            .putIfAbsent(n['related_user_id'] as String, () => [])
            .add(n);
      } else {
        final dt =
            DateTime.tryParse(n['created_at'] as String? ?? '') ??
            DateTime.now();
        result.add(
          _DisplayEntry(
            isMessageGroup: false,
            rows: [n],
            sortDate: dt,
            unread: n['read'] != true,
          ),
        );
      }
    }

    for (final rows in messagesBySender.values) {
      // Rows already come newest-first from listNotifications' ordering.
      final latestDt =
          DateTime.tryParse(rows.first['created_at'] as String? ?? '') ??
          DateTime.now();
      result.add(
        _DisplayEntry(
          isMessageGroup: true,
          rows: rows,
          sortDate: latestDt,
          unread: rows.any((r) => r['read'] != true),
        ),
      );
    }

    // Look up real usernames/avatars for message senders (the title text
    // already has a name baked in, but a proper lookup avoids parsing it
    // back out of a sentence and gives us an avatar too).
    final senderIds = result
        .where((e) => e.isMessageGroup && e.senderId != null)
        .map((e) => e.senderId!)
        .toSet()
        .toList();
    if (senderIds.isNotEmpty) {
      try {
        final profiles = await SupabaseService.supabase
            .from('profiles_public')
            .select('id, username, avatar_url')
            .inFilter('id', senderIds);
        final byId = {
          for (final p in (profiles as List))
            (p['id']).toString(): Map<String, dynamic>.from(p as Map),
        };
        for (final e in result) {
          if (e.isMessageGroup && e.senderId != null) {
            final p = byId[e.senderId];
            e.senderUsername = p?['username'] as String?;
            e.senderAvatarUrl = p?['avatar_url'] as String?;
          }
        }
      } catch (_) {
        // Falls back to the title's embedded name below if this fails.
      }
    }

    result.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return result;
  }

  Future<void> _markAllRead() async {
    await SupabaseService.markAllNotificationsRead();
    setState(() {
      for (final n in items) {
        n['read'] = true;
      }
      entries = entries
          .map(
            (e) =>
                _DisplayEntry(
                    isMessageGroup: e.isMessageGroup,
                    rows: e.rows,
                    sortDate: e.sortDate,
                    unread: false,
                  )
                  ..senderUsername = e.senderUsername
                  ..senderAvatarUrl = e.senderAvatarUrl,
          )
          .toList();
    });
  }

  String _group(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inHours < 24 && dt.day == now.day) return 'TODAY';
    if (diff.inDays < 2) return 'YESTERDAY';
    return 'EARLIER';
  }

  Future<void> _openEntry(_DisplayEntry entry) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      if (entry.isMessageGroup) {
        final senderId = entry.senderId;
        if (senderId != null) {
          await SupabaseService.markMessageNotificationsReadForSender(senderId);
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                receiverId: senderId,
                receiverName:
                    entry.senderUsername ?? _senderNameFromTitle(entry),
              ),
            ),
          );
          _load();
        }
        return;
      }

      final n = entry.latest;
      if (n['read'] != true) {
        await SupabaseService.markNotificationRead(n['id'] as String);
      }
      final itemId = n['related_item_id'] as String?;
      if (itemId == null) {
        setState(() => n['read'] = true);
        return;
      }
      final item = await SupabaseService.getItemById(itemId);
      if (!mounted) return;
      if (item == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This post is no longer available.')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  /// Fallback when the profiles_public lookup didn't return anything: pull
  /// the sender's name back out of the trigger-written title, e.g. "Jordan
  /// sent you a message" -> "Jordan".
  String _senderNameFromTitle(_DisplayEntry entry) {
    final title = entry.latest['title'] as String? ?? '';
    const suffix = ' sent you a message';
    return title.endsWith(suffix)
        ? title.substring(0, title.length - suffix.length)
        : 'User';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_DisplayEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(_group(e.sortDate), () => []).add(e);
    }
    final order = ['TODAY', 'YESTERDAY', 'EARLIER'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: ResponsiveCenter(child: loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 56,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final g in order)
                    if (groups[g] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          g,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.neutralGrey,
                          ),
                        ),
                      ),
                      ...groups[g]!.map((e) => _buildTile(e)),
                    ],
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildTile(_DisplayEntry e) {
    final n = e.latest;
    final type = e.isMessageGroup ? 'message' : (n['type'] as String);
    final isRead = !e.unread;
    final count = e.rows.length;

    String title;
    String body;
    if (e.isMessageGroup) {
      final name = e.senderUsername ?? _senderNameFromTitle(e);
      title = count > 1 ? '$name · $count messages' : name;
      body = (n['body'] as String?) ?? '';
    } else {
      title = n['title'] as String;
      body = n['body'] as String;
    }

    return InkWell(
      onTap: () => _openEntry(e),
      child: Container(
        color: isRead
            ? Colors.transparent
            : AppColors.success100.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: _colorForType(type).withValues(alpha: 0.15),
              backgroundImage:
                  (e.senderAvatarUrl != null && e.senderAvatarUrl!.isNotEmpty)
                  ? NetworkImage(e.senderAvatarUrl!)
                  : null,
              child: (e.senderAvatarUrl == null || e.senderAvatarUrl!.isEmpty)
                  ? Icon(
                      _iconForType(type),
                      color: _colorForType(type),
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(color: AppColors.neutralGrey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo(e.sortDate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.neutralGrey,
                    ),
                  ),
                ],
              ),
            ),
            if (e.unread)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accent500,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
