import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The three named MYKerawang themes (DESIGN_SPEC.md §2).
/// Shared identity (kerawang cut, motif, Fraunces, spacing, gold rules)
/// never changes — only the palette and button mood swap.
enum AppTheme { kampus, istana, noir }

/// Signature asymmetric corner — the "kerawang cut".
/// Use on hero cards, embed cards, primary buttons (istana/noir), images.
const BorderRadius kerawangCut = BorderRadius.only(
  topLeft: Radius.circular(2),
  topRight: Radius.circular(14),
  bottomRight: Radius.circular(2),
  bottomLeft: Radius.circular(14),
);

class AppThemeSpec {
  final String displayName;
  final String tagline;
  final Brightness brightness;
  final Color background;
  final Color surface; // cards
  final Color primary;
  final Color gold;
  final Color text;
  final Color border;
  final bool pillButtons; // kampus = pills; others = kerawang cut

  const AppThemeSpec({
    required this.displayName,
    required this.tagline,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.primary,
    required this.gold,
    required this.text,
    required this.border,
    required this.pillButtons,
  });
}

const Map<AppTheme, AppThemeSpec> kThemeSpecs = {
  AppTheme.kampus: AppThemeSpec(
    displayName: "Kampus Bold",
    tagline: "Loud & young",
    brightness: Brightness.light,
    background: Color(0xFFFAF7FF),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF5B3E96),
    gold: Color(0xFFF0A81C),
    text: Color(0xFF241640),
    border: Color(0xFFE4DCF2),
    pillButtons: true,
  ),
  AppTheme.istana: AppThemeSpec(
    displayName: "Istana Modern",
    tagline: "Crafted & warm",
    brightness: Brightness.light,
    background: Color(0xFFF6F0E4),
    surface: Color(0xFFFFFDF7),
    primary: Color(0xFF3D2B56),
    gold: Color(0xFFBA7517),
    text: Color(0xFF2C2050),
    border: Color(0xFFE3D5B8),
    pillButtons: false,
  ),
  AppTheme.noir: AppThemeSpec(
    displayName: "Songket Noir",
    tagline: "Premium & dark",
    brightness: Brightness.dark,
    background: Color(0xFF171122),
    surface: Color(0xFF231A35),
    primary: Color(0xFF7E5FC7),
    gold: Color(0xFFE8C766),
    text: Color(0xFFEDE6FA),
    border: Color(0xFF3D2E5C),
    pillButtons: false,
  ),
};

ThemeData buildAppTheme(AppTheme theme) {
  final spec = kThemeSpecs[theme]!;
  final isDark = spec.brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: spec.primary,
    brightness: spec.brightness,
  ).copyWith(
    primary: spec.primary,
    surface: spec.background,
    onSurface: spec.text,
    tertiary: spec.gold,
    outlineVariant: spec.border,
    surfaceContainerLowest: spec.surface,
    surfaceContainerLow: spec.surface,
    surfaceContainer: isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.04), spec.surface)
        : Color.alphaBlend(spec.primary.withValues(alpha: 0.04), spec.surface),
    surfaceContainerHighest: isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), spec.surface)
        : Color.alphaBlend(spec.primary.withValues(alpha: 0.08), spec.surface),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  TextStyle? serif(TextStyle? s) =>
      s == null ? null : GoogleFonts.fraunces(textStyle: s);

  final buttonShape = spec.pillButtons
      ? const StadiumBorder()
      : const RoundedRectangleBorder(borderRadius: kerawangCut);

  final buttonPadding =
      const EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  return base.copyWith(
    scaffoldBackgroundColor: spec.background,
    cardColor: spec.surface,
    dividerColor: spec.border,
    textTheme: base.textTheme.copyWith(
      displayLarge: serif(base.textTheme.displayLarge),
      displayMedium: serif(base.textTheme.displayMedium),
      displaySmall: serif(base.textTheme.displaySmall),
      headlineLarge: serif(base.textTheme.headlineLarge),
      headlineMedium: serif(base.textTheme.headlineMedium),
      headlineSmall: serif(base.textTheme.headlineSmall),
      titleLarge: serif(base.textTheme.titleLarge),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.background,
      titleTextStyle: GoogleFonts.fraunces(
        textStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: spec.text,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: TextStyle(
          fontWeight: theme == AppTheme.kampus ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        side: BorderSide(color: isDark ? spec.gold : spec.border),
        foregroundColor: isDark ? spec.gold : spec.primary,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: spec.pillButtons
          ? const StadiumBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: spec.border),
    ),
  );
}
