import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'luxe_tokens.dart';

abstract final class LuxeTheme {
  static ThemeData dark() => _build(LuxeTokens.obsidian, Brightness.dark);
  static ThemeData light() => _build(LuxeTokens.ivory, Brightness.light);

  static ThemeData _build(LuxeTokens tokens, Brightness brightness) {
    final textTheme = TextTheme(
      displayLarge: GoogleFonts.sora(
        color: tokens.textPrimary,
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: GoogleFonts.sora(
        color: tokens.textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displaySmall: GoogleFonts.sora(
        color: tokens.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: GoogleFonts.sora(
        color: tokens.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.sora(
        color: tokens.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        color: tokens.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: GoogleFonts.inter(
        color: tokens.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: GoogleFonts.jetBrainsMono(
        color: tokens.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        color: tokens.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: tokens.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: tokens.emerald,
        onPrimary: tokens.isDark ? const Color(0xFF041F15) : Colors.white,
        secondary: tokens.gold,
        onSecondary: const Color(0xFF1F1600),
        error: tokens.crimson,
        onError: Colors.white,
        surface: tokens.surfaceSolid,
        onSurface: tokens.textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: tokens.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: IconThemeData(color: tokens.textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.bgElevated,
        hintStyle: TextStyle(color: tokens.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.emerald, width: 1.5),
        ),
      ),
      extensions: [tokens],
    );
  }
}
