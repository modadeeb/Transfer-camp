import 'package:flutter/material.dart';

/// Palette shared with the web app (apps/web/src/style.css).
@immutable
class CampColors extends ThemeExtension<CampColors> {
  const CampColors({
    required this.bg,
    required this.sunken,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.forest,
    required this.sage,
    required this.sageSoft,
    required this.brass,
    required this.brassSoft,
    required this.danger,
    required this.dangerSoft,
    required this.primary,
    required this.onPrimary,
  });

  final Color bg;
  final Color sunken;
  final Color card;
  final Color ink;
  final Color muted;
  final Color line;
  final Color forest;
  final Color sage;
  final Color sageSoft;
  final Color brass;
  final Color brassSoft;
  final Color danger;
  final Color dangerSoft;
  final Color primary;
  final Color onPrimary;

  static const light = CampColors(
    bg: Color(0xFFF7F6F1),
    sunken: Color(0xFFEFEEE7),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF252A27),
    muted: Color(0xFF777E78),
    line: Color(0xFFE7E9E3),
    forest: Color(0xFF243F35),
    sage: Color(0xFF56856A),
    sageSoft: Color(0xFFE7EFE9),
    brass: Color(0xFFB68A47),
    brassSoft: Color(0xFFF5EDE0),
    danger: Color(0xFFA9483A),
    dangerSoft: Color(0xFFF7E8E4),
    primary: Color(0xFF243F35),
    onPrimary: Color(0xFFF7F6F1),
  );

  static const dark = CampColors(
    bg: Color(0xFF121715),
    sunken: Color(0xFF0D110F),
    card: Color(0xFF1A211E),
    ink: Color(0xFFE8EBE7),
    muted: Color(0xFF9AA49D),
    line: Color(0xFF2A332F),
    forest: Color(0xFF9CC5B0),
    sage: Color(0xFF7FB096),
    sageSoft: Color(0xFF1F2D26),
    brass: Color(0xFFD3A865),
    brassSoft: Color(0xFF2E271B),
    danger: Color(0xFFE08A7B),
    dangerSoft: Color(0xFF34201C),
    primary: Color(0xFF3D7560),
    onPrimary: Color(0xFFFFFFFF),
  );

  @override
  CampColors copyWith() => this;

  @override
  CampColors lerp(ThemeExtension<CampColors>? other, double t) => t < 0.5 ? this : (other as CampColors? ?? this);
}

extension CampTheme on BuildContext {
  CampColors get c => Theme.of(this).extension<CampColors>()!;
}

const _fallback = ['PlexLatin'];

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? CampColors.dark : CampColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.primary,
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.brass,
    error: c.danger,
    surface: c.card,
    onSurface: c.ink,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'PlexArabic',
    fontFamilyFallback: _fallback,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: 'PlexArabic', fontFamilyFallback: _fallback),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'PlexArabic', fontFamilyFallback: _fallback, fontSize: 19, fontWeight: FontWeight.w700, color: c.ink),
    ),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: c.brass, width: 2)),
      errorBorder: border.copyWith(borderSide: BorderSide(color: c.danger)),
      labelStyle: TextStyle(color: c.muted),
      hintStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'PlexArabic', fontFamilyFallback: _fallback, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 46),
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'PlexArabic', fontFamilyFallback: _fallback, fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.forest)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.card,
      indicatorColor: c.sageSoft,
      height: 66,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontFamily: 'PlexArabic', fontFamilyFallback: _fallback, fontSize: 12, color: c.ink)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.forest,
      contentTextStyle: TextStyle(fontFamily: 'PlexArabic', fontFamilyFallback: _fallback, color: brightness == Brightness.dark ? c.bg : c.onPrimary),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, showDragHandle: true),
    dialogTheme: DialogThemeData(backgroundColor: c.card),
  );
}
