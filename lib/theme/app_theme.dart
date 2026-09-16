// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Foundify design tokens — color palette, type scale, spacing and shared
/// component styling, matching the Foundify design system.
class AppColors {
  AppColors._();

  // Primary (pink)
  static const primary50 = Color(0xFFFDF2F8);
  static const primary100 = Color(0xFFFCE7F3);
  static const primary300 = Color(0xFFEC4899);
  static const primary500 = Color(0xFFD6247A);
  static const primary700 = Color(0xFFA6134F);
  static const primary900 = Color(0xFF6B0F38);

  // Accent (warm/orange) & status
  static const accent100 = Color(0xFFFEEBC8);
  static const accent500 = Color(0xFFF5820D);
  static const success100 = Color(0xFFDDF5E6);
  static const success500 = Color(0xFF1FA34D);
  static const error100 = Color(0xFFFCE1E1);
  static const error500 = Color(0xFFDA342E);
  static const neutral100 = Color(0xFFF1F1F4);
  static const neutralGrey = Color(0xFF6B7280);
  static const ink = Color(0xFF14151A);

  // A near-white background reads as flat/unfinished against the brand's
  // pink; this carries a soft, deliberate pink tint instead while staying
  // light enough for body text to read cleanly on top of it.
  static const background = Color(0xFFFDF6F8);
}

class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(TextTheme base) {
    return GoogleFonts.manropeTextTheme(base).copyWith(
      displaySmall: GoogleFonts.manrope(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      labelSmall: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.neutralGrey,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary500,
        secondary: AppColors.accent500,
        error: AppColors.error500,
        surface: Colors.white,
      ),
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: GoogleFonts.manrope(
          color: AppColors.neutralGrey,
          fontSize: 15,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary500, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error500),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary500,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary500,
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
      // Every SnackBar in the app (errors, confirmations, etc.) goes
      // through ScaffoldMessenger with no per-call styling, so it was
      // falling back to Flutter's plain default — a flat black bar with
      // the system font, which reads as unfinished/broken rather than
      // part of the app. Themed once here instead of touching every
      // individual showSnackBar call site.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: GoogleFonts.manrope(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        actionTextColor: AppColors.primary300,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        margin: EdgeInsets.zero,
      ),
      useMaterial3: true,
    );
  }
}

/// Foundify's brand mark — a single consistent widget instead of the same
/// "pink circle + check icon" combination hand-copied at slightly different
/// sizes/colors across Home, Auth, and the public landing pages. Pass
/// [onTap] to make it act as a "go to Home" control where that makes sense
/// (public pages reached with no login); omit it where the mark is purely
/// decorative (e.g. already on the Home tab).
class FoundifyLogo extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;
  const FoundifyLogo({super.key, this.size = 32, this.onTap});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.primary500,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.5),
    );
    if (onTap == null) return mark;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: mark,
    );
  }
}

/// Small pill-shaped status badge used across item cards & details.
class StatusBadge extends StatelessWidget {
  final String status; // open, resolved, flagged, pending...
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color bg;
    Color fg;
    switch (s) {
      case 'resolved':
      case 'returned':
        bg = AppColors.neutral100;
        fg = AppColors.neutralGrey;
        break;
      case 'flagged':
      case 'pending':
        bg = AppColors.error100;
        fg = AppColors.error500;
        break;
      default: // open
        bg = AppColors.primary100;
        fg = AppColors.primary500;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Category chip pill (e.g. "Bags", "Wallet") used on cards & filters.
class CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const CategoryChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary500 : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? AppColors.primary500 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// One segment of a [PillTabBar].
class PillTabItem {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// When set, the selected segment fills with this color (white text) —
  /// used for e.g. Lost/Found status toggles. When null, the selected
  /// segment is a plain white "elevated" pill with primary-colored text —
  /// used for e.g. Login/Signup or Reports/Resolved toggles.
  final Color? activeColor;

  const PillTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeColor,
  });
}

/// Shared pill-shaped segmented toggle — the same rounded, animated
/// two-or-more-option switcher used across Home (Lost/Found), Profile
/// (Reports/Resolved), Auth (Log In/Sign Up) and Post Item (I Lost
/// This/I Found This), previously reimplemented separately in each screen.
class PillTabBar extends StatelessWidget {
  final List<PillTabItem> items;
  const PillTabBar({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: items.map((item) => Expanded(child: _segment(item))).toList(),
      ),
    );
  }

  Widget _segment(PillTabItem item) {
    final filled = item.activeColor != null;
    return GestureDetector(
      onTap: item.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: item.selected
              ? (item.activeColor ?? Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: (item.selected && !filled)
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          item.label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: item.selected
                ? (filled ? Colors.white : AppColors.primary500)
                : AppColors.neutralGrey,
          ),
        ),
      ),
    );
  }
}

const List<String> kItemCategories = [
  'Electronics',
  'Bags',
  'Wallet',
  'Keys',
  'Jewelry',
  'Pets',
  'Documents',
  'Other',
];

IconData categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'electronics':
      return Icons.phone_iphone_outlined;
    case 'bags':
      return Icons.work_outline;
    case 'wallet':
    case 'wallets':
      return Icons.credit_card_outlined;
    case 'keys':
      return Icons.key_outlined;
    case 'jewelry':
      return Icons.diamond_outlined;
    case 'pets':
      return Icons.pets_outlined;
    case 'documents':
      return Icons.description_outlined;
    default:
      return Icons.category_outlined;
  }
}
