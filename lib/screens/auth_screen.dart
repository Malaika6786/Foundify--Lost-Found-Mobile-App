// lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'home_shell.dart';

class AuthScreen extends StatefulWidget {
  final bool startOnLogin;
  const AuthScreen({super.key, this.startOnLogin = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  late bool isLogin = widget.startOnLogin;
  bool loading = false;
  bool obscurePassword = true;
  String? emailError;
  String? phoneError;
  String? passwordError;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) =>
      RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$').hasMatch(value);

  /// Format-only validation (E.164-ish: optional +, 8-15 digits). This is
  /// not SMS/OTP verification that the number is actually reachable or
  /// belongs to the signer — that needs a paid SMS provider (e.g. Twilio)
  /// wired through Supabase phone auth, which requires an account only you
  /// can set up. This at least stops obviously-fake input like "123".
  bool _isValidPhone(String value) => RegExp(
    r'^\+?[0-9]{8,15}$',
  ).hasMatch(value.replaceAll(RegExp(r'[\s\-()]'), ''));

  Future<void> submit() async {
    setState(() {
      emailError = null;
      phoneError = null;
      passwordError = null;
    });
    final emailText = email.text.trim();
    if (emailText.isNotEmpty && !_isValidEmail(emailText)) {
      setState(() => emailError = 'Enter a valid email address');
      return;
    }

    if (!isLogin) {
      final phoneText = phone.text.trim();
      if (phoneText.isEmpty || !_isValidPhone(phoneText)) {
        setState(() => phoneError = 'Enter a valid phone number (8-15 digits)');
        return;
      }
      if (pass.text.length < 6) {
        setState(
          () => passwordError = 'Password must be at least 6 characters',
        );
        return;
      }
    }

    setState(() => loading = true);
    try {
      if (isLogin) {
        final res = await SupabaseService.signIn(emailText, pass.text.trim());
        if (res.session != null) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeShell()),
          );
        } else {
          _showSnack('Login failed');
        }
      } else {
        final res = await SupabaseService.signUp(
          emailText,
          pass.text.trim(),
          name: name.text.trim(),
          phone: phone.text.trim(),
        );

        if (res.user == null) {
          _showSnack('Registration failed. Please try again.');
        } else if (res.session != null) {
          // Email confirmation is off for this project (or was
          // auto-satisfied) — a session already exists, so there's no need
          // to make the user log in again right after signing up.
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeShell()),
          );
        } else {
          // Email confirmation is required — there's no session yet and
          // nothing the app can do to skip that step, so say so clearly
          // instead of a vague "check your email (if enabled)".
          _showSnack(
            'Account created! Please verify your email — check your inbox for a confirmation link, then log in.',
          );
          setState(() => isLogin = true);
        }
      }
    } catch (e) {
      _showSnack(friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _forgotPassword() async {
    final emailText = email.text.trim();
    if (emailText.isEmpty || !_isValidEmail(emailText)) {
      setState(
        () => emailError =
            'Enter your email above first, then tap Forgot password?',
      );
      return;
    }
    try {
      await SupabaseService.sendPasswordResetEmail(emailText);
      _showSnack('Password reset email sent to $emailText.');
    } catch (e) {
      _showSnack(friendlyError(e));
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => loading = true);
    try {
      final signedIn = await SupabaseService.signInWithGoogle();
      if (signedIn) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeShell()),
        );
      }
      // false just means the user dismissed the account picker — no error
      // to show, they simply landed back on this screen.
    } catch (e) {
      _showSnack(friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FoundifyLogo(size: 56),
              const SizedBox(height: 20),
              Text(
                isLogin ? 'Welcome back' : 'Create your account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                isLogin
                    ? 'Log in to continue helping reunite lost items.'
                    : 'Join Foundify to report and recover lost items.',
                style: const TextStyle(
                  color: AppColors.neutralGrey,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),

              // Login / Sign Up segmented toggle
              PillTabBar(
                items: [
                  PillTabItem(
                    label: 'Log In',
                    selected: isLogin,
                    onTap: () => setState(() => isLogin = true),
                  ),
                  PillTabItem(
                    label: 'Sign Up',
                    selected: !isLogin,
                    onTap: () => setState(() => isLogin = false),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (!isLogin) ...[
                _label('Full name'),
                const SizedBox(height: 8),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: 16),
                _label('Phone'),
                const SizedBox(height: 4),
                const Text(
                  'Lets someone who finds your item call you directly.',
                  style: TextStyle(fontSize: 12, color: AppColors.neutralGrey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '+1 555 0100',
                    prefixIcon: const Icon(Icons.call_outlined),
                    errorText: phoneError,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              _label('Email'),
              const SizedBox(height: 8),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@mail.com',
                  prefixIcon: const Icon(Icons.mail_outline),
                  errorText: emailError,
                ),
              ),
              const SizedBox(height: 16),

              _label('Password'),
              const SizedBox(height: 8),
              TextField(
                controller: pass,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: passwordError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
              ),

              if (isLogin) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
              ] else
                const SizedBox(height: 16),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : submit,
                  child: Text(
                    loading
                        ? 'Please wait…'
                        : (isLogin ? 'Log In' : 'Create account'),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.neutralGrey,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : _continueWithGoogle,
                  icon: const _GoogleLogo(size: 18),
                  label: const Text('Continue with Google'),
                ),
              ),

              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => isLogin = !isLogin),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.neutralGrey,
                        fontSize: 14,
                      ),
                      children: [
                        TextSpan(
                          text: isLogin
                              ? "Don't have an account? "
                              : 'Already have an account? ',
                        ),
                        TextSpan(
                          text: isLogin ? 'Sign Up' : 'Log In',
                          style: const TextStyle(
                            color: AppColors.primary500,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
  );
}

/// A minimal, dependency-free rendering of Google's four-color "G" mark
/// (brand colors only, no wordmark) — replaces the generic
/// `Icons.g_mobiledata` font glyph, which isn't Google's actual logo.
class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final stroke = radius * 0.42;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    Paint arcPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four brand-color quadrant arcs approximating the Google "G".
    canvas.drawArc(rect, -0.35, 1.7, false, arcPaint(const Color(0xFF4285F4)));
    canvas.drawArc(rect, 1.35, 1.6, false, arcPaint(const Color(0xFF34A853)));
    canvas.drawArc(rect, 2.95, 1.2, false, arcPaint(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 4.15, 1.7, false, arcPaint(const Color(0xFFEA4335)));

    // Horizontal bar of the "G".
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx,
        center.dy - stroke / 2,
        radius - stroke * 0.15,
        stroke,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
