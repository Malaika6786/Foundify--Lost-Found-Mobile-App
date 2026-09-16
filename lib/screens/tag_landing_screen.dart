// lib/screens/tag_landing_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'home_shell.dart';
import 'onboarding_screen.dart';

/// Public "scan a tag" landing page — reached via a plain web link encoded
/// in the tag's QR code (see ItemTagsScreen). No account or app install is
/// required: a finder can leave a message straight from their phone's
/// browser, and the tag's owner is notified in Foundify.
class TagLandingScreen extends StatefulWidget {
  final String code;
  const TagLandingScreen({super.key, required this.code});

  @override
  State<TagLandingScreen> createState() => _TagLandingScreenState();
}

class _TagLandingScreenState extends State<TagLandingScreen> {
  Map<String, dynamic>? tag;
  bool loading = true;
  bool sending = false;
  bool sent = false;

  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await SupabaseService.lookupItemTagByCode(widget.code);
      if (mounted) setState(() => tag = t);
    } catch (e) {
      debugPrint('tag lookup failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _send() async {
    if (_messageCtrl.text.trim().isEmpty) return;
    setState(() => sending = true);
    try {
      await SupabaseService.submitTagMessage(
        tagId: tag!['id'] as String,
        finderName: _nameCtrl.text.trim().isEmpty
            ? null
            : _nameCtrl.text.trim(),
        finderContact: _contactCtrl.text.trim().isEmpty
            ? null
            : _contactCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
      );
      if (mounted) setState(() => sent = true);
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : tag == null
                  ? _NotFoundCard()
                  : (tag!['active'] == false)
                  ? _InactiveCard(label: tag!['label'] as String)
                  : sent
                  ? _SentCard(label: tag!['label'] as String)
                  : _MessageForm(
                      label: tag!['label'] as String,
                      nameCtrl: _nameCtrl,
                      contactCtrl: _contactCtrl,
                      messageCtrl: _messageCtrl,
                      sending: sending,
                      onSend: _send,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FoundifyLogo(
          size: 48,
          onTap: () => Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => SupabaseService.currentUser() == null
                  ? const OnboardingScreen()
                  : const HomeShell(),
            ),
            (r) => false,
          ),
        ),
        const SizedBox(height: 12),
        Text('Foundify', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _NotFoundCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Icon(Icons.qr_code_2, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text(
          'Tag not found',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          "This code doesn't match any Foundify tag. Double-check the link.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.neutralGrey),
        ),
      ],
    );
  }
}

class _InactiveCard extends StatelessWidget {
  final String label;
  const _InactiveCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        Icon(Icons.pause_circle_outline, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          'This tag ($label) is inactive',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          'The owner has paused this tag, so messages can\'t be delivered right now.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.neutralGrey),
        ),
      ],
    );
  }
}

class _SentCard extends StatelessWidget {
  final String label;
  const _SentCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Header(),
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.success100,
          child: Icon(Icons.check, color: AppColors.success500, size: 32),
        ),
        const SizedBox(height: 16),
        const Text(
          'Message sent!',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          "The owner of \"$label\" has been notified and will reach out using the contact info you left.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.neutralGrey),
        ),
      ],
    );
  }
}

class _MessageForm extends StatelessWidget {
  final String label;
  final TextEditingController nameCtrl;
  final TextEditingController contactCtrl;
  final TextEditingController messageCtrl;
  final bool sending;
  final VoidCallback onSend;

  const _MessageForm({
    required this.label,
    required this.nameCtrl,
    required this.contactCtrl,
    required this.messageCtrl,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: AppColors.primary100,
                child: Icon(Icons.key_outlined, color: AppColors.primary500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You found "$label"',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      'Leave a message for the owner below — no account needed.',
                      style: TextStyle(
                        color: AppColors.neutralGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Your name (optional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: 'e.g. Jordan'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Phone or email so they can reach you back',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: contactCtrl,
          decoration: const InputDecoration(
            hintText: 'Optional, but recommended',
          ),
        ),
        const SizedBox(height: 16),
        const Text('Message', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: messageCtrl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: "I found this near..."),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: sending ? null : onSend,
          child: Text(sending ? 'Sending…' : 'Send Message'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your contact info is only shared with the tag\'s owner — never published.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.neutralGrey),
        ),
      ],
    );
  }
}
