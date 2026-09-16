// lib/screens/new_message_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart' show thumbColorFor;
import 'chat_screen.dart';

/// Search for a user by username to start a new chat — reached from the
/// search icon on the Chat List screen. Previously there was no way to
/// message someone except from an item's contact sheet.
class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  bool searched = false;
  bool opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      loading = true;
      searched = true;
    });
    try {
      final data = await SupabaseService.searchUsersByUsername(query);
      if (mounted) setState(() => results = data);
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

  Future<void> _openChat(Map<String, dynamic> user) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      // Confirm the chat can actually be created/found before navigating —
      // ChatScreen looks it up again itself, but this way a failure shows
      // an error here instead of inside a freshly-opened chat screen.
      await SupabaseService.getOrCreatePrivateChat(user['id'] as String);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            receiverId: user['id'] as String,
            receiverName: (user['username'] as String?) ?? 'User',
          ),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Message')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                fillColor: AppColors.neutral100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : !searched
                ? const Center(
                    child: Text(
                      'Search for someone by username to start chatting.',
                      style: TextStyle(color: AppColors.neutralGrey),
                      textAlign: TextAlign.center,
                    ),
                  )
                : results.isEmpty
                ? const Center(
                    child: Text(
                      'No users found.',
                      style: TextStyle(color: AppColors.neutralGrey),
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final u = results[index];
                      final username = u['username'] as String? ?? 'User';
                      final avatarUrl = u['avatar_url'] as String?;
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: thumbColorFor(u['id'].toString()),
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: opening ? null : () => _openChat(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
