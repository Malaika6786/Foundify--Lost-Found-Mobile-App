// lib/screens/comments_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart' show timeAgo;

class CommentsScreen extends StatefulWidget {
  final String itemId;
  const CommentsScreen({super.key, required this.itemId});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> comments = [];
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final data = await SupabaseService.listComments(widget.itemId);
      if (mounted) setState(() => comments = data);
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

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await SupabaseService.addComment(widget.itemId, text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : comments.isEmpty
                ? const Center(
                    child: Text(
                      'No comments yet',
                      style: TextStyle(color: AppColors.neutralGrey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final c = comments[index];
                      final profile =
                          c['profiles'] as Map<String, dynamic>? ?? {};
                      final username =
                          profile['username'] as String? ?? 'Unknown';
                      final avatar = profile['avatar_url'] as String?;
                      final createdAt = DateTime.tryParse(
                        c['created_at'] as String? ?? '',
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary100,
                              backgroundImage:
                                  (avatar != null && avatar.isNotEmpty)
                                  ? NetworkImage(avatar)
                                  : null,
                              child: (avatar == null || avatar.isEmpty)
                                  ? const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: AppColors.primary700,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        username,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        timeAgo(createdAt),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.neutralGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(c['content'] as String? ?? ''),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
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
                      tooltip: 'Post comment',
                      icon: sending
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
                      onPressed: sending ? null : _submit,
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
