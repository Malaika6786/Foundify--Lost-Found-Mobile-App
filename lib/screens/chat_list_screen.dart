// lib/screens/chat_list_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/item_card.dart';
import 'chat_screen.dart';
import 'new_message_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> conversations = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = supabase.auth.currentUser;
    if (me == null) return;
    setState(() => isLoading = true);

    // Fire-and-forget: opening/refreshing the chat list means this device
    // has synced, so every incoming message is now "delivered" — this is
    // what lets the sender's ticks progress from one grey check to two,
    // even before the recipient opens that specific conversation.
    SupabaseService.markAllMessagesDelivered();

    try {
      final chats = await supabase
          .from('chats')
          .select('id, user1, user2')
          .or('user1.eq.${me.id},user2.eq.${me.id}');

      final chatList = chats as List;
      if (chatList.isEmpty) {
        if (mounted) setState(() => conversations = []);
        return;
      }

      // Figure out the "other" participant + chat id for each conversation
      // up front, then fetch profiles and last-messages in two batch calls
      // instead of two round trips PER conversation (was previously up to
      // 2N sequential awaits — visibly slow once you have more than a
      // couple of chats).
      final chatIds = <String>[];
      final otherIds = <String>[];
      final chatToOther = <String, String>{};
      for (final chat in chatList) {
        final chatId = chat['id'].toString();
        final otherId = (chat['user1'] == me.id ? chat['user2'] : chat['user1'])
            ?.toString();
        if (otherId == null) continue;
        chatIds.add(chatId);
        otherIds.add(otherId);
        chatToOther[chatId] = otherId;
      }

      final profilesFuture = otherIds.isEmpty
          ? Future.value(<Map<String, dynamic>>[])
          : supabase
                .from('profiles_public')
                .select('id, username, avatar_url')
                .inFilter('id', otherIds);
      final messagesFuture = chatIds.isEmpty
          ? Future.value(<Map<String, dynamic>>[])
          : supabase
                .from('messages')
                .select('chat_id, content, created_at, attachment_url, sender_id, read')
                .inFilter('chat_id', chatIds)
                .order('created_at', ascending: false);

      final results = await Future.wait([profilesFuture, messagesFuture]);
      final profilesById = {
        for (final p in (results[0] as List))
          (p['id']).toString(): p as Map<String, dynamic>,
      };
      // Messages are ordered newest-first, so the first one seen per chat is
      // that chat's latest message. The same pass also tallies how many of
      // the OTHER person's messages in each chat are still unread, since
      // this query already pulls every message across all these chats
      // anyway — no extra round trip needed.
      final latestMessageByChatId = <String, Map<String, dynamic>>{};
      final unreadCountByChatId = <String, int>{};
      for (final m in (results[1] as List)) {
        final cid = m['chat_id'].toString();
        latestMessageByChatId.putIfAbsent(cid, () => m as Map<String, dynamic>);
        final senderId = m['sender_id']?.toString();
        if (senderId != me.id && m['read'] != true) {
          unreadCountByChatId[cid] = (unreadCountByChatId[cid] ?? 0) + 1;
        }
      }

      final result = <Map<String, dynamic>>[];
      for (final chatId in chatIds) {
        final otherId = chatToOther[chatId]!;
        final profile = profilesById[otherId];
        final lastMsg = latestMessageByChatId[chatId];
        final lastContent = (lastMsg?['content'] as String?) ?? '';
        final lastAttachment = lastMsg?['attachment_url'] as String?;
        final lastSenderId = lastMsg?['sender_id']?.toString();
        result.add({
          'chatId': chatId,
          'otherId': otherId,
          'username': profile?['username'] ?? 'Unknown',
          'avatarUrl': profile?['avatar_url'],
          'lastMessage': lastContent,
          'lastAttachmentUrl': lastAttachment,
          'lastIsMine': lastMsg != null && lastSenderId == me.id,
          'lastAt': lastMsg?['created_at'],
          'unreadCount': unreadCountByChatId[chatId] ?? 0,
        });
      }

      result.sort((a, b) {
        final aAt = a['lastAt'] as String?;
        final bAt = b['lastAt'] as String?;
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        return bAt.compareTo(aAt);
      });

      if (mounted) setState(() => conversations = result);
    } catch (e) {
      debugPrint('Error loading conversations: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveCenter(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Messages',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'New message',
                        icon: const Icon(Icons.search),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NewMessageScreen(),
                            ),
                          );
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (isLoading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (conversations.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 56,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No conversations yet',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Message a reporter from an item to start chatting.',
                          style: TextStyle(color: AppColors.neutralGrey),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  // Extra bottom inset so the last conversation isn't hidden
                  // behind the floating bottom nav bar (HomeShell uses
                  // extendBody: true).
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final c = conversations[index];
                      final avatarUrl = c['avatarUrl'] as String?;
                      final username = c['username'] as String;
                      final lastAt = c['lastAt'] != null
                          ? DateTime.tryParse(c['lastAt'])
                          : null;
                      final unreadCount = c['unreadCount'] as int;
                      final isUnread = unreadCount > 0;
                      final hasAttachment =
                          (c['lastAttachmentUrl'] as String?)?.isNotEmpty ==
                          true;
                      final lastText = c['lastMessage'] as String;
                      final lastIsMine = c['lastIsMine'] as bool;
                      // "You: " / photo prefix so the list reads like a real
                      // chat app instead of a bare snippet with no sense of
                      // who sent it or that it was a photo, not text.
                      final preview = lastText.isEmpty && !hasAttachment
                          ? 'Say hello 👋'
                          : '${lastIsMine ? 'You: ' : ''}${hasAttachment && lastText.isEmpty ? '📷 Photo' : lastText}';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: thumbColorFor(
                              c['otherId'].toString(),
                            ),
                            backgroundImage:
                                (avatarUrl != null && avatarUrl.isNotEmpty)
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: (avatarUrl == null || avatarUrl.isEmpty)
                                ? Text(
                                    username.isNotEmpty
                                        ? username[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary700,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            username,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isUnread ? AppColors.ink : null,
                            ),
                          ),
                          subtitle: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: isUnread
                                  ? AppColors.ink
                                  : AppColors.neutralGrey,
                            ),
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                lastAt != null ? timeAgo(lastAt) : '',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isUnread
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: isUnread
                                      ? AppColors.primary500
                                      : AppColors.neutralGrey,
                                ),
                              ),
                              if (isUnread) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary500,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(10),
                                    ),
                                  ),
                                  child: Text(
                                    unreadCount > 9 ? '9+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  receiverId: c['otherId'],
                                  receiverName: username,
                                ),
                              ),
                            ).then((_) => _load());
                          },
                        ),
                      );
                    }, childCount: conversations.length),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
