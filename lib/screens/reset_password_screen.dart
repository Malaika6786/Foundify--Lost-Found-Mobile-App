// lib/screens/reset_password_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'home_shell.dart';

/// Shown when the user follows the "reset your password" link from their
/// email. Supabase signs them into a temporary recovery session and fires
/// AuthChangeEvent.passwordRecovery (see main.dart), which routes here —
/// this is where they actually set a new password to finish the flow.
/// Previously there was no such screen at all: sendPasswordResetEmail()
/// could send the email, but clicking its link had nowhere useful to land
/// and the password could never actually be changed.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password updated. You're all set!")),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FoundifyLogo(size: 56),
              const SizedBox(height: 20),
              Text(
                'Set a new password',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a new password for your account.',
                style: TextStyle(color: AppColors.neutralGrey, fontSize: 15),
              ),
              const SizedBox(height: 28),
              const Text(
                'New password',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirm password',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Saving…' : 'Update password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
