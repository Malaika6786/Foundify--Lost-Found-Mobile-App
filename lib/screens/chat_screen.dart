// lib/screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart' show thumbColorFor;
import 'item_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId; // other user's id
  final String receiverName; // display name
  final String? itemTitle; // optional item context shown under the header
  final String? itemStatus;

  /// Set when opened from an item's contact sheet — remembered on the chat
  /// itself (see SupabaseService.getOrCreatePrivateChat) so the item being
  /// discussed keeps showing up even when this chat is reopened later from
  /// the Messages list, not just this one time.
  final String? itemId;

  const ChatScreen({
    Key? key,
    required this.receiverId,
    required this.receiverName,
    this.itemTitle,
    this.itemStatus,
    this.itemId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _chatId;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  bool _loading = true;
  bool _sending = false;
  bool _attaching = false;
  Item? _relatedItem;
  String? _receiverAvatarUrl;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    try {
      final chatId = await SupabaseService.getOrCreatePrivateChat(
        widget.receiverId,
        itemId: widget.itemId,
      );
      if (!mounted) return;
      setState(() {
        _chatId = chatId;
        _loading = true;
      });

      // Look up the item this chat is about — whether it was just set
      // above (first time, from a contact sheet) or was already stored on
      // the chat from an earlier session — so the mention shows up however
      // this chat was reached.
      SupabaseService.getChatRelatedItem(chatId).then((item) {
        if (mounted && item != null) setState(() => _relatedItem = item);
      });

      // The AppBar previously only ever showed an initial-letter avatar —
      // callers that open ChatScreen (chat list, item detail, notifications,
      // new message) don't all have the receiver's avatar_url on hand, so
      // it's fetched here once instead, guaranteeing it's always correct
      // regardless of entry point.
      SupabaseService.getPublicProfile(widget.receiverId).then((profile) {
        final url = profile?['avatar_url'] as String?;
        if (mounted && url != null && url.isNotEmpty) {
          setState(() => _receiverAvatarUrl = url);
        }
      });

      final hist = await SupabaseService.fetchMessages(chatId);
      if (!mounted) return;
      setState(() {
        _messages = hist;
        _loading = false;
      });
      _scrollToBottomJump();
      SupabaseService.markMessagesRead(chatId);

      _sub = SupabaseService.messageStream(_chatId!).listen((rows) {
        if (!mounted) return;
        final hadFewer = rows.length > _messages.length;
        // Defensive merge, not a blind replace: if a message we just sent
        // is still in flight (optimistic, not yet confirmed by the
        // server) when a stream snapshot arrives that raced ahead of it,
        // a plain `_messages = rows` would wipe that pending message from
        // view until the next event — keep it until the server actually
        // confirms it.
        final myId = SupabaseService.supabase.auth.currentUser?.id;
        final serverIds = rows.map((r) => r['id'].toString()).toSet();
        final stillPending = _messages.where(
          (m) =>
              !serverIds.contains(m['id'].toString()) &&
              _messageSenderId(m) == myId,
        );
        final merged = [...rows, ...stillPending]..sort(
          (a, b) => (a['created_at'] ?? '').toString().compareTo(
            (b['created_at'] ?? '').toString(),
          ),
        );
        setState(() => _messages = merged);
        if (hadFewer) {
          _scrollToBottomAnimated();
          // A new incoming message while the chat is already open should
          // be marked read right away too, not just on the initial load.
          SupabaseService.markMessagesRead(chatId);
        }
      });
    } catch (e, st) {
      debugPrint('Failed to init chat: $e\n$st');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not open chat')));
      }
    }
  }

  Future<void> _pickAndSendAttachment() async {
    if (_chatId == null || _attaching) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      setState(() => _attaching = true);
      final bytes = await picked.readAsBytes();
      final url = await SupabaseService.uploadChatAttachment(bytes, _chatId!);
      final inserted = await SupabaseService.sendMessage(
        _chatId!,
        '',
        attachmentUrl: url,
      );
      if (mounted) {
        setState(() => _messages.add(Map<String, dynamic>.from(inserted)));
      }
      _scrollToBottomAnimated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _chatId == null || _sending) return;

    setState(() => _sending = true);

    final user = SupabaseService.supabase.auth.currentUser;
    if (user == null) {
      setState(() => _sending = false);
      return;
    }

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempMsg = {
      'id': tempId,
      'chat_id': _chatId!,
      'sender_id': user.id,
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      _messages.add(tempMsg);
      _controller.clear();
      _scrollToBottomAnimated();
    });

    try {
      final inserted = await SupabaseService.sendMessage(_chatId!, text);
      setState(() {
        final index = _messages.indexWhere((m) => m['id'] == tempId);
        if (index != -1) {
          if (inserted is List && inserted.isNotEmpty) {
            _messages[index] = Map<String, dynamic>.from(inserted[0]);
          } else if (inserted is Map<String, dynamic>) {
            _messages[index] = Map<String, dynamic>.from(inserted);
          }
        }
      });
      _scrollToBottomAnimated();
    } catch (e) {
      debugPrint('Send message error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      setState(() => _messages.removeWhere((m) => m['id'] == tempId));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottomJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _scrollToBottomAnimated() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _messageText(Map<String, dynamic> msg) =>
      (msg['content'] ?? msg['message'] ?? '').toString();

  String? _messageAttachmentUrl(Map<String, dynamic> msg) {
    final url = msg['attachment_url'] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  bool _messageRead(Map<String, dynamic> msg) => msg['read'] == true;
  bool _messageDelivered(Map<String, dynamic> msg) => msg['delivered'] == true;

  /// Full-screen, pinch-to-zoom view of a tapped chat photo — previously
  /// tapping an attachment did nothing at all.
  void _openImageViewer(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _messageSenderId(Map<String, dynamic> msg) {
    final s = msg['sender'] ?? msg['sender_id'] ?? msg['senderId'];
    return s?.toString();
  }

  String _messageTimestamp(Map<String, dynamic> msg) {
    final ts = msg['created_at'] ?? msg['createdAt'] ?? '';
    if (ts == '') return '';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  /// A persistent "you're talking about this" banner — shows the real
  /// item (with thumbnail) once `_relatedItem` loads, using the
  /// navigation-time hint (title/status passed in) as a placeholder before
  /// that resolves so there's no flash of nothing.
  Widget _buildItemMention() {
    final item = _relatedItem;
    final title = item?.title ?? widget.itemTitle ?? '';
    final status = item != null
        ? (item.returned ? 'Resolved' : 'Open')
        : (widget.itemStatus ?? 'Open');
    final thumbUrl = item?.imageUrl;

    return InkWell(
      onTap: item == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
            ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                color: item != null
                    ? thumbColorFor(item.id)
                    : AppColors.primary100,
                child: (thumbUrl != null && thumbUrl.isNotEmpty)
                    ? Image.network(thumbUrl, fit: BoxFit.cover)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'You\'re discussing this post',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.neutralGrey,
                    ),
                  ),
                ],
              ),
            ),
            StatusBadge(status: status),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary500,
              backgroundImage:
                  (_receiverAvatarUrl != null && _receiverAvatarUrl!.isNotEmpty)
                  ? NetworkImage(_receiverAvatarUrl!)
                  : null,
              child: (_receiverAvatarUrl == null || _receiverAvatarUrl!.isEmpty)
                  ? Text(
                      widget.receiverName.isNotEmpty
                          ? widget.receiverName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              // Just the name — no fake "Online" status. There's no real
              // presence tracking wired up, so showing one would just be
              // lying to the user about whether the other person is
              // actually there.
              child: Text(
                widget.receiverName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ResponsiveCenter(
        child: Column(
        children: [
          if (_relatedItem != null || widget.itemTitle != null)
            _buildItemMention(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet.\nSay hi to ${widget.receiverName} 👋',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.neutralGrey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final senderId = _messageSenderId(msg);
                      final currentUserId =
                          SupabaseService.supabase.auth.currentUser?.id;
                      final isMe =
                          senderId != null &&
                          currentUserId != null &&
                          senderId == currentUserId;

                      final text = _messageText(msg);
                      final ts = _messageTimestamp(msg);
                      final attachmentUrl = _messageAttachmentUrl(msg);

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: GestureDetector(
                            onLongPress: () async {
                              final shouldDelete = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Message'),
                                  content: const Text(
                                    'Do you want to delete this message?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text(
                                        'Delete',
                                        style: TextStyle(
                                          color: AppColors.error500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (shouldDelete == true) {
                                final messageId = msg['id'].toString();
                                try {
                                  await SupabaseService.deleteMessage(
                                    messageId,
                                  );
                                  if (!mounted) return;
                                  setState(
                                    () => _messages.removeWhere(
                                      (m) => m['id'].toString() == messageId,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not delete message'),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.primary500
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: isMe
                                    ? null
                                    : Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (attachmentUrl != null)
                                    GestureDetector(
                                      onTap: () =>
                                          _openImageViewer(context, attachmentUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          attachmentUrl,
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 180,
                                            height: 180,
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (attachmentUrl != null && text.isNotEmpty)
                                    const SizedBox(height: 6),
                                  if (text.isNotEmpty)
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white
                                            : AppColors.ink,
                                      ),
                                    ),
                                  if (ts.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            ts,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isMe
                                                  ? Colors.white70
                                                  : AppColors.neutralGrey,
                                            ),
                                          ),
                                          // WhatsApp-style tick progression
                                          // — only meaningful for messages
                                          // I sent; the other person's own
                                          // messages don't show a status
                                          // back to them. One grey check =
                                          // sent, two grey = delivered to
                                          // their device, two colored =
                                          // they've actually read it.
                                          if (isMe) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              _messageRead(msg) ||
                                                      _messageDelivered(msg)
                                                  ? Icons.done_all
                                                  : Icons.done,
                                              size: 13,
                                              color: _messageRead(msg)
                                                  ? const Color(0xFFFF6FB5)
                                                  : Colors.white70,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Attach a photo',
                    icon: _attaching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.attach_file,
                            color: AppColors.neutralGrey,
                          ),
                    onPressed: _attaching ? null : _pickAndSendAttachment,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.neutral100,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary500,
                    child: IconButton(
                      tooltip: 'Send',
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 18,
                            ),
                      onPressed: (_chatId == null || _sending) ? null : _send,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
