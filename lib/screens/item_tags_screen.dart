// lib/screens/item_tags_screen.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart';

/// The link a tag's QR code points to. Uses the current web origin when
/// this build is actually served on the web. On native (the actual
/// distribution channel for this app), there's no hosted domain, so this
/// encodes the `foundify://` custom scheme instead — registered in
/// AndroidManifest.xml / Info.plist and handled in main.dart, so scanning
/// the QR on a phone with Foundify installed opens straight into the tag's
/// landing page with no website required.
String tagUrl(String code) {
  if (kIsWeb) return '${Uri.base.origin}/#/tag/$code';
  return 'foundify://open/tag/$code';
}

class ItemTagsScreen extends StatefulWidget {
  const ItemTagsScreen({super.key});

  @override
  State<ItemTagsScreen> createState() => _ItemTagsScreenState();
}

class _ItemTagsScreenState extends State<ItemTagsScreen> {
  List<Map<String, dynamic>> tags = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final t = await SupabaseService.listItemTags();
      if (mounted) setState(() => tags = t);
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

  Future<void> _linkNewTag() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Link a New Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. House Keys'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Link Tag'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;

    try {
      await SupabaseService.createItemTag(label: label);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> tag) async {
    final newValue = !(tag['active'] as bool);
    setState(() => tag['active'] = newValue);
    try {
      await SupabaseService.setItemTagActive(tag['id'] as String, newValue);
    } catch (e) {
      setState(() => tag['active'] = !newValue);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _openTagDetails(Map<String, dynamic> tag) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TagDetailsSheet(tag: tag),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Item Tags')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary700, AppColors.primary500],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tag it. No app needed to return it.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Stick a Foundify QR tag on your keys, bag, or laptop. Anyone who scans it opens a page to message you — no account required.',
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.qr_code_2, size: 36),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primary500,
                                  minimumSize: const Size(0, 44),
                                ),
                                onPressed: _linkNewTag,
                                child: const Text('Link a Tag'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'LINKED TAGS',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.neutralGrey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No tags linked yet.',
                        style: const TextStyle(color: AppColors.neutralGrey),
                      ),
                    ),
                  ...tags.map(
                    (t) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: () => _openTagDetails(t),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.qr_code,
                            color: AppColors.primary500,
                          ),
                        ),
                        title: Text(
                          t['label'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Tag #${t['code']} · ${(t['active'] as bool) ? 'Active' : 'Inactive'}',
                        ),
                        trailing: Semantics(
                          label: (t['active'] as bool)
                              ? 'Active, tap to deactivate tag'
                              : 'Inactive, tap to activate tag',
                          button: true,
                          child: GestureDetector(
                            onTap: () => _toggleActive(t),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: (t['active'] as bool)
                                      ? AppColors.success500
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.success100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppColors.success500,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Scans never reveal your phone number or address — finders reach you through a private in-app link.",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TagDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> tag;
  const _TagDetailsSheet({required this.tag});

  @override
  State<_TagDetailsSheet> createState() => _TagDetailsSheetState();
}

class _TagDetailsSheetState extends State<_TagDetailsSheet> {
  List<Map<String, dynamic>> messages = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await SupabaseService.listTagMessages(
        widget.tag['id'] as String,
      );
      if (mounted) setState(() => messages = m);
    } catch (e) {
      debugPrint('failed to load tag messages: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final removedIndex = messages.indexOf(message);
    setState(() => messages.remove(message));
    try {
      await SupabaseService.deleteTagMessage(message['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() => messages.insert(removedIndex, message));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.tag['code'] as String;
    final url = tagUrl(code);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              widget.tag['label'] as String,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: QrImageView(
                  data: url,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            if (!kIsWeb)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Scanning this QR opens Foundify directly on a phone that has it installed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.neutralGrey),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'MESSAGES FROM FINDERS',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.neutralGrey,
              ),
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No one has scanned this tag yet.',
                  style: TextStyle(color: AppColors.neutralGrey),
                ),
              )
            else
              ...messages.map(
                (m) => Dismissible(
                  key: ValueKey(m['id']),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteMessage(m),
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: AppColors.error500,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (m['finder_name'] as String?) ??
                                      'Anonymous finder',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                timeAgo(
                                  DateTime.tryParse(
                                    m['created_at'] as String? ?? '',
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.neutralGrey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(m['message'] as String),
                          if ((m['finder_contact'] as String?)?.isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.call_outlined,
                                  size: 14,
                                  color: AppColors.primary500,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  m['finder_contact'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary500,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
