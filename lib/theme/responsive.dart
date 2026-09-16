// lib/theme/responsive.dart
import 'package:flutter/material.dart';

/// Screen-width breakpoints shared across the app. Below [tablet], the app
/// looks exactly as it always has on a phone — nothing here changes that
/// layout. At or above it (a tablet in portrait, a resized Chromebook
/// window, a foldable unfolded, etc.) screens switch to the wider-screen
/// treatment: a side navigation rail instead of a bottom bar, and content
/// capped to a readable width instead of one mobile-designed column
/// stretching edge-to-edge across a 10-inch display.
class Breakpoints {
  Breakpoints._();
  static const double tablet = 700;
}

bool isWideScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

/// Centers [child] and caps its width once the window is tablet-sized or
/// wider. A no-op on phones (child gets the full width, exactly as before).
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 640});

  @override
  Widget build(BuildContext context) {
    if (!isWideScreen(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
