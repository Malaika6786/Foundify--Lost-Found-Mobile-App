// lib/screens/item_detail_screen.dart
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/item.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/friendly_error.dart';
import '../widgets/item_card.dart';
import 'chat_screen.dart';
import 'claim_item_screen.dart';
import 'safe_meetup_screen.dart';

class ItemDetailScreen extends StatefulWidget {
  final Item item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  final supabase = Supabase.instance.client;
  late final PageController _pageController;
  int _pageIndex = 0;
  bool _savingReturned = false;
  bool _returned = false;
  late final bool isOwner;

  @override
  void initState() {
    super.initState();
    final me = Supabase.instance.client.auth.currentUser;
    isOwner =
        (me != null &&
        widget.item.userId != null &&
        me.id == widget.item.userId);
    _pageController = PageController();
    _returned = widget.item.returned;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text(
          "You'll have a few seconds to undo this after confirming.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _savingReturned = true);
    try {
      final imagesToRemove =
          (widget.item.imageUrls != null && widget.item.imageUrls!.isNotEmpty)
          ? widget.item.imageUrls!
          : (widget.item.imageUrl != null
                ? [widget.item.imageUrl!]
                : const <String>[]);
      await SupabaseService.deletePost(widget.item.id);
      if (!mounted) return;

      final closedReason = await ScaffoldMessenger.of(context)
          .showSnackBar(
            SnackBar(
              content: const Text('Post deleted'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {}, // handled by checking closedReason below
              ),
            ),
          )
          .closed;

      if (closedReason == SnackBarClosedReason.action) {
        // Undo tapped — restore and stay on the post.
        await SupabaseService.restorePost(widget.item.id);
        if (mounted) setState(() => _savingReturned = false);
        return;
      }

      // Undo window passed — the item stays soft-deleted; clean up its
      // photos now that it's really gone.
      unawaited(SupabaseService.purgeDeletedPostImages(imagesToRemove));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _savingReturned = false);
    }
  }

  Future<void> _markAsReturned() async {
    setState(() => _savingReturned = true);
    try {
      await SupabaseService.markItemResolved(widget.item.id);
      if (mounted) setState(() => _returned = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _savingReturned = false);
    }
  }

  Future<void> _openMaps() async {
    if (widget.item.latitude == null || widget.item.longitude == null) return;
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${widget.item.latitude},${widget.item.longitude}',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      await launchUrl(url);
    }
  }

  void _openContactSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Reporter phone/email come from a scoped RPC, not a direct profiles
      // read — profiles RLS is owner-only by design (see
      // supabase/migrations/0009_secure_profiles_contact.sql), so this is
      // the only sanctioned way to see another user's contact info, and
      // only for the reporter of this specific item.
      builder: (_) => FutureBuilder<Map<String, dynamic>?>(
        future: SupabaseService.getItemReporterContact(widget.item.id),
        builder: (context, snapshot) {
          final contact = snapshot.data;
          final phone = contact?['phone'] as String?;
          final email = contact?['email'] as String?;
          return _buildContactSheet(context, phone: phone, email: email);
        },
      ),
    );
  }

  Widget _buildContactSheet(
    BuildContext context, {
    String? phone,
    String? email,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Text(
              'Contact Reporter',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 12),
            _contactTile(
              icon: Icons.chat_bubble_outline,
              label: 'Send In-App Message',
              highlighted: true,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      receiverId: widget.item.userId!,
                      receiverName: widget.item.username ?? 'User',
                      itemTitle: widget.item.title,
                      itemStatus: _returned ? 'Resolved' : 'Open',
                      itemId: widget.item.id,
                    ),
                  ),
                );
              },
            ),
            // Only shown when the reporter actually has a verified-format
            // phone on file — no dead "not available" dead end.
            if (phone != null && phone.isNotEmpty)
              _contactTile(
                icon: Icons.call_outlined,
                label: 'Call $phone',
                onTap: () async {
                  Navigator.pop(context);
                  final uri = Uri(scheme: 'tel', path: phone);
                  if (!await launchUrl(uri)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not start a call.'),
                        ),
                      );
                    }
                  }
                },
              ),
            _contactTile(
              icon: Icons.mail_outline,
              label: email != null && email.isNotEmpty
                  ? 'Email $email'
                  : 'Email (not available)',
              onTap: () async {
                Navigator.pop(context);
                if (email == null || email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No email on file for this reporter.'),
                    ),
                  );
                  return;
                }
                final uri = Uri(
                  scheme: 'mailto',
                  path: email,
                  queryParameters: {
                    'subject':
                        'About your Foundify report: ${widget.item.title}',
                  },
                );
                if (!await launchUrl(uri)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open an email client.'),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SafeMeetupScreen(itemId: widget.item.id),
                  ),
                );
              },
              icon: const Icon(Icons.shield_outlined),
              label: const Text('Propose a Safe Meetup Spot'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: highlighted ? AppColors.primary50 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: highlighted ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: highlighted ? AppColors.primary500 : AppColors.ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.neutralGrey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> images = <String>[];
    if (widget.item.imageUrls != null && widget.item.imageUrls!.isNotEmpty) {
      images.addAll(widget.item.imageUrls!);
    } else if (widget.item.imageUrl != null &&
        widget.item.imageUrl!.isNotEmpty) {
      images.add(widget.item.imageUrl!);
    }
    final reward = widget.item.reward;

    return Scaffold(
      body: ResponsiveCenter(
        child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 300,
            backgroundColor: AppColors.primary50,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _roundIcon(
                Icons.arrow_back,
                () => Navigator.pop(context),
                label: 'Back',
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: _roundIcon(Icons.share_outlined, () {
                  Share.share(
                    buildShareText(widget.item),
                    subject: widget.item.title,
                  );
                }, label: 'Share'),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: images.isEmpty
                  ? Container(
                      color: thumbColorFor(widget.item.id),
                      child: Center(
                        child: Icon(
                          categoryIcon(widget.item.category ?? ''),
                          size: 72,
                          color: AppColors.primary500,
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          onPageChanged: (i) => setState(() => _pageIndex = i),
                          itemCount: images.length,
                          itemBuilder: (context, index) => CachedNetworkImage(
                            imageUrl: images[index],
                            fit: BoxFit.cover,
                            memCacheWidth: 1080,
                            placeholder: (_, __) =>
                                Container(color: thumbColorFor(widget.item.id)),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 48),
                              ),
                            ),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(images.length, (i) {
                                final active = i == _pageIndex;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  width: active ? 18 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white
                                        : Colors.white54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      if ((widget.item.category ?? '').isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.item.category!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      StatusBadge(status: _returned ? 'Resolved' : 'Open'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.item.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Posted ${timeAgo(widget.item.createdAt)}',
                    style: const TextStyle(color: AppColors.neutralGrey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage:
                            (widget.item.avatarUrl != null &&
                                widget.item.avatarUrl!.isNotEmpty)
                            ? CachedNetworkImageProvider(widget.item.avatarUrl!)
                            : null,
                        child:
                            (widget.item.avatarUrl == null ||
                                widget.item.avatarUrl!.isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.item.username ?? 'Unknown reporter',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isOwner)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.neutral100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.item.description.isNotEmpty
                        ? widget.item.description
                        : 'No description provided.',
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (widget.item.status == 'lost' &&
                      reward != null &&
                      reward > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Reward offered: ₨ ${reward.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary500,
                        ),
                      ),
                    ),
                  if (widget.item.latitude != null &&
                      widget.item.longitude != null) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Location',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _openMaps,
                      child: Container(
                        height: 130,
                        // Missing before — with no explicit width, a Stack
                        // sizes itself to its largest non-positioned child
                        // (just the small pin icon here), so the box
                        // shrank to icon-width and the "Open in Google
                        // Maps" pill below it (a Positioned child, which
                        // doesn't count toward that sizing) overflowed and
                        // got clipped down to "Goog".
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary100),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.location_on,
                              color: AppColors.accent500,
                              size: 36,
                            ),
                            Positioned(
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Open in Google Maps',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!isOwner && widget.item.userId != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openContactSheet,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Contact Reporter'),
                      ),
                    ),
                  if (!isOwner &&
                      widget.item.status == 'found' &&
                      !_returned) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClaimItemScreen(item: widget.item),
                          ),
                        ),
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('This Is Mine — Start Claim'),
                      ),
                    ),
                  ],
                  if (isOwner)
                    _savingReturned
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _returned ? null : _markAsReturned,
                                icon: const Icon(Icons.verified_outlined),
                                label: Text(
                                  _returned
                                      ? 'Marked as resolved'
                                      : 'Mark as Resolved',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _returned
                                      ? Colors.grey
                                      : AppColors.success500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _deletePost,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.error500,
                                ),
                                label: const Text(
                                  'Delete Post',
                                  style: TextStyle(color: AppColors.error500),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.error500,
                                  ),
                                ),
                              ),
                            ],
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

  Widget _roundIcon(IconData icon, VoidCallback onTap, {String? label}) {
    return CircleAvatar(
      backgroundColor: Colors.black38,
      child: IconButton(
        tooltip: label,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}
