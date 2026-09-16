// lib/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary50, Colors.white],
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: () => _goToAuth(context),
                    child: const Text('Skip'),
                  ),
                ),
                const Spacer(flex: 3),
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: const BoxDecoration(
                      color: AppColors.primary100,
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.translate(
                          offset: const Offset(-20, -10),
                          child: Icon(
                            Icons.mail_outline,
                            size: 90,
                            color: AppColors.primary500,
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(45, 40),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.search,
                              size: 46,
                              color: AppColors.accent500,
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: const Offset(58, 55),
                          child: const Icon(
                            Icons.check,
                            size: 18,
                            color: AppColors.success500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Dot(active: false),
                    const SizedBox(width: 6),
                    _Dot(active: false),
                    const SizedBox(width: 6),
                    _Dot(active: true),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  "Reunite people with\nwhat they've lost",
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  'Post a lost item, browse found items nearby, and connect safely to get it back.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.neutralGrey,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _goToAuth(context),
                    child: const Text('Get Started'),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? '),
                      GestureDetector(
                        onTap: () => _goToAuth(context, login: true),
                        child: const Text(
                          'Log In',
                          style: TextStyle(
                            color: AppColors.primary500,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToAuth(BuildContext context, {bool login = false}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AuthScreen(startOnLogin: login)),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primary500 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
