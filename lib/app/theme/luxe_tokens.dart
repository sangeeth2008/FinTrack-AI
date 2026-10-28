import 'dart:ui';
import 'package:flutter/material.dart';

@immutable
class LuxeTokens extends ThemeExtension<LuxeTokens> {
  final bool isDark;
  final Color bg;
  final Color bgElevated;
  final Color surfaceGlass;
  final Color surfaceSolid;
  final Color borderSubtle;
  final Color borderHighlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color emerald;
  final Color gold;
  final Color crimson;
  final Color cyan;
  final LinearGradient primaryGradient;
  final LinearGradient creditGradient;
  final LinearGradient debitGradient;
  final LinearGradient copilotGradient;
  final double glassBlur;

  const LuxeTokens({
    required this.isDark,
    required this.bg,
    required this.bgElevated,
    required this.surfaceGlass,
    required this.surfaceSolid,
    required this.borderSubtle,
    required this.borderHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.emerald,
    required this.gold,
    required this.crimson,
    required this.cyan,
    required this.primaryGradient,
    required this.creditGradient,
    required this.debitGradient,
    required this.copilotGradient,
    required this.glassBlur,
  });

  static const obsidian = LuxeTokens(
    isDark: true,
    bg: Color(0xFF07080C),
    bgElevated: Color(0xFF0E1118),
    surfaceGlass: Color(0x99151A24),
    surfaceSolid: Color(0xFF141923),
    borderSubtle: Color(0x1FFFFFFF),
    borderHighlight: Color(0x4510E5A0),
    textPrimary: Color(0xFFF3F5F8),
    textSecondary: Color(0xFF9AA3B2),
    textMuted: Color(0xFF5D6676),
    emerald: Color(0xFF10E5A0),
    gold: Color(0xFFE8C468),
    crimson: Color(0xFFFF5C7A),
    cyan: Color(0xFF00F2FF),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF10E5A0), Color(0xFFE8C468)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    creditGradient: LinearGradient(
      colors: [Color(0xFF10E5A0), Color(0xFF059669)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    debitGradient: LinearGradient(
      colors: [Color(0xFFFF5C7A), Color(0xFFF59E0B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    copilotGradient: LinearGradient(
      colors: [Color(0xFF00F2FF), Color(0xFF10E5A0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glassBlur: 22.0,
  );

  static const ivory = LuxeTokens(
    isDark: false,
    bg: Color(0xFFF6F5F0),
    bgElevated: Color(0xFFEDEBE4),
    surfaceGlass: Color(0xCCFFFFFF),
    surfaceSolid: Color(0xFFFFFFFF),
    borderSubtle: Color(0x1814161A),
    borderHighlight: Color(0x45099968),
    textPrimary: Color(0xFF11141C),
    textSecondary: Color(0xFF525B6C),
    textMuted: Color(0xFF8B93A2),
    emerald: Color(0xFF089969),
    gold: Color(0xFFC59B27),
    crimson: Color(0xFFE02D50),
    cyan: Color(0xFF008899),
    primaryGradient: LinearGradient(
      colors: [Color(0xFF089969), Color(0xFFC59B27)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    creditGradient: LinearGradient(
      colors: [Color(0xFF089969), Color(0xFF057A55)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    debitGradient: LinearGradient(
      colors: [Color(0xFFE02D50), Color(0xFFD97706)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    copilotGradient: LinearGradient(
      colors: [Color(0xFF008899), Color(0xFF089969)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glassBlur: 18.0,
  );

  @override
  LuxeTokens copyWith({
    bool? isDark,
    Color? bg,
    Color? bgElevated,
    Color? surfaceGlass,
    Color? surfaceSolid,
    Color? borderSubtle,
    Color? borderHighlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? emerald,
    Color? gold,
    Color? crimson,
    Color? cyan,
    LinearGradient? primaryGradient,
    LinearGradient? creditGradient,
    LinearGradient? debitGradient,
    LinearGradient? copilotGradient,
    double? glassBlur,
  }) {
    return LuxeTokens(
      isDark: isDark ?? this.isDark,
      bg: bg ?? this.bg,
      bgElevated: bgElevated ?? this.bgElevated,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceSolid: surfaceSolid ?? this.surfaceSolid,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderHighlight: borderHighlight ?? this.borderHighlight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      emerald: emerald ?? this.emerald,
      gold: gold ?? this.gold,
      crimson: crimson ?? this.crimson,
      cyan: cyan ?? this.cyan,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      creditGradient: creditGradient ?? this.creditGradient,
      debitGradient: debitGradient ?? this.debitGradient,
      copilotGradient: copilotGradient ?? this.copilotGradient,
      glassBlur: glassBlur ?? this.glassBlur,
    );
  }

  @override
  LuxeTokens lerp(ThemeExtension<LuxeTokens>? other, double t) {
    if (other is! LuxeTokens) return this;
    return LuxeTokens(
      isDark: t < 0.5 ? isDark : other.isDark,
      bg: Color.lerp(bg, other.bg, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      surfaceSolid: Color.lerp(surfaceSolid, other.surfaceSolid, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderHighlight: Color.lerp(borderHighlight, other.borderHighlight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      emerald: Color.lerp(emerald, other.emerald, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      crimson: Color.lerp(crimson, other.crimson, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      primaryGradient: LinearGradient.lerp(primaryGradient, other.primaryGradient, t)!,
      creditGradient: LinearGradient.lerp(creditGradient, other.creditGradient, t)!,
      debitGradient: LinearGradient.lerp(debitGradient, other.debitGradient, t)!,
      copilotGradient: LinearGradient.lerp(copilotGradient, other.copilotGradient, t)!,
      glassBlur: lerpDouble(glassBlur, other.glassBlur, t)!,
    );
  }
}

extension LuxeContext on BuildContext {
  LuxeTokens get luxe => Theme.of(this).extension<LuxeTokens>() ?? LuxeTokens.obsidian;
}

