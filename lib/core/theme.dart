import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final class RodMaeColors {
  RodMaeColors._();

  // === DARK BACKGROUNDS ===
  static const Color background    = Color(0xFF04091A);  // deepest navy
  static const Color backgroundAlt = Color(0xFF070F2B);  // deep royal
  static const Color navy          = Color(0xFF0C1445);  // card surface dark
  static const Color navy2         = Color(0xFF0F1A55);  // elevated surface dark
  static const Color charcoal      = Color(0xFF111827);

  // === ROYAL BLUE PRIMARIES ===
  static const Color royalBlue     = Color(0xFF1D4ED8);  // blue-700
  static const Color sapphire      = Color(0xFF1E40AF);  // blue-800
  static const Color electricBlue  = Color(0xFF3B82F6);  // blue-500
  static const Color sky           = Color(0xFF93C5FD);  // blue-300
  static const Color powder        = Color(0xFFBFDBFE);  // blue-200

  // === GOLDEN YELLOW ACCENTS ===
  static const Color gold          = Color(0xFFF59E0B);  // amber-500
  static const Color accentGold    = gold;
  static const Color amber         = Color(0xFFD97706);  // amber-600
  static const Color lemon         = Color(0xFFFCD34D);  // amber-300 (glow)
  static const Color goldDeep      = Color(0xFFB45309);  // amber-700

  // === SEMANTIC COLORS ===
  static const Color coral         = Color(0xFFFF6B6B);
  static const Color rose          = Color(0xFFFF5E8D);
  static const Color mint          = Color(0xFF34D399);
  static const Color violet        = Color(0xFF7C3AED);
  static const Color textSoft      = Color(0xFFBFDBFE);  // powder blue for dark
  static const Color textMuted     = Color(0xFF64748B);

  // === LIGHT MODE COLORS (blue-tinted light) ===
  static const Color lightBackground  = Color(0xFFEFF6FF); // blue-50
  static const Color lightBackground2 = Color(0xFFDBEAFE); // blue-100
  static const Color lightCard        = Color(0xFFFFFFFF);
  static const Color lightCardTinted  = Color(0xFFF0F7FF);
  static const Color lightText        = Color(0xFF1E3A8A); // blue-900
  static const Color lightTextSoft    = Color(0xFF1D4ED8); // blue-700
  static const Color lightTextMuted   = Color(0xFF3B82F6); // blue-500

  // === GRADIENTS ===
  static LinearGradient getAppBackground(bool isDark) {
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
        colors: [
          Color(0xFF04091A), // deep navy
          Color(0xFF0A1540), // royal blue night
          Color(0xFF070F2B), // midnight royal
        ],
      );
    } else {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
        colors: [
          Color(0xFFEFF6FF), // blue-50
          Color(0xFFDBEAFE), // blue-100
          Color(0xFFEFF6FF), // blue-50
        ],
      );
    }
  }

  static LinearGradient getCardGradient(bool isDark) {
    if (isDark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF112070),
          Color(0xFF0C1650),
          Color(0xFF080F35),
        ],
      );
    } else {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF0F7FF),
        ],
      );
    }
  }

  static LinearGradient get royalGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1D4ED8), // royal blue
          Color(0xFF1E40AF), // sapphire
          Color(0xFF0C1445), // deep navy
        ],
      );

  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFCD34D), // lemon
          Color(0xFFF59E0B), // gold
          Color(0xFFD97706), // amber
        ],
      );

  // Legacy alias
  static LinearGradient get sapphireGradient => royalGradient;

  // Gold glow box shadow helper
  static List<BoxShadow> goldGlow({double intensity = 1.0}) => [
    BoxShadow(
      color: gold.withValues(alpha: 0.45 * intensity),
      blurRadius: 20,
      spreadRadius: 2,
    ),
  ];

  // Blue glow box shadow helper
  static List<BoxShadow> blueGlow({double intensity = 1.0}) => [
    BoxShadow(
      color: electricBlue.withValues(alpha: 0.4 * intensity),
      blurRadius: 20,
      spreadRadius: 1,
    ),
  ];
}

final class RodMaeTheme {
  RodMaeTheme._();

  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final inter = GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: RodMaeColors.background,
      colorScheme: const ColorScheme.dark(
        primary: RodMaeColors.electricBlue,
        secondary: RodMaeColors.gold,
        tertiary: RodMaeColors.lemon,
        surface: RodMaeColors.navy,
        onSurface: Colors.white,
      ),
      textTheme: inter.copyWith(
        headlineLarge: GoogleFonts.playfairDisplay(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: GoogleFonts.playfairDisplay(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: GoogleFonts.inter(
          color: RodMaeColors.textSoft,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RodMaeColors.navy2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.22),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.36),
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RodMaeColors.gold, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final inter = GoogleFonts.interTextTheme(base.textTheme);
    return base.copyWith(
      scaffoldBackgroundColor: RodMaeColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: RodMaeColors.royalBlue,
        secondary: RodMaeColors.gold,
        tertiary: RodMaeColors.amber,
        surface: RodMaeColors.lightCard,
        onSurface: RodMaeColors.lightText,
      ),
      textTheme: inter.copyWith(
        headlineLarge: GoogleFonts.playfairDisplay(
          color: RodMaeColors.lightText,
          fontSize: 30,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: GoogleFonts.playfairDisplay(
          color: RodMaeColors.lightText,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: GoogleFonts.inter(
          color: RodMaeColors.lightText,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: GoogleFonts.inter(
          color: RodMaeColors.lightText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: GoogleFonts.inter(
          color: RodMaeColors.lightTextSoft,
          fontSize: 13,
          height: 1.35,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: RodMaeColors.lightText),
        titleTextStyle: GoogleFonts.playfairDisplay(
          color: RodMaeColors.lightText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RodMaeColors.royalBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RodMaeColors.royalBlue.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: GoogleFonts.inter(
          color: RodMaeColors.lightText.withValues(alpha: 0.4),
          fontSize: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: RodMaeColors.royalBlue.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: RodMaeColors.royalBlue.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RodMaeColors.gold, width: 1.5),
        ),
      ),
    );
  }
}
