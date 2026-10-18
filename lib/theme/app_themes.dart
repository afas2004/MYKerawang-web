import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';
import 'transitions.dart';

export 'tokens.dart';

/// The three named MYKerawang themes (DESIGN_SPEC.md §2).
/// Shared identity (kerawang cut, motif, Fraunces, spacing, gold rules)
/// never changes — only the palette and button mood swap.
enum AppTheme { kampus, istana, noir }

/// Signature asymmetric corner — the "kerawang cut".
/// Use on hero cards, embed cards, primary buttons (istana/noir), images.
/// Same value as [KRadius.cut]; kept for existing call sites.
const BorderRadius kerawangCut = KRadius.cut;

/// Chrome that sits directly on photos — status badges, carousel counters,
/// the fullscreen viewer. Theme-independent on purpose (a photo looks the
/// same in every theme). Everything else takes colours from ColorScheme.
const Color kOnPhoto = Colors.white;

/// Dark wash behind [kOnPhoto] content on top of an image.
Color photoScrim([double opacity = 0.55]) =>
    Colors.black.withValues(alpha: opacity);

class AppThemeSpec {
  final String displayName; // proper name, not translated (tagline: AppStrings)
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


/// Tests can't download fonts; set this to use the platform font instead of
/// Fraunces (layout is otherwise identical).
@visibleForTesting
bool debugUseSystemFonts = false;

/// Nudges [fg]'s lightness away from [bg] until the pair reaches [min]
/// contrast (WCAG). Keeps hue, so brand colours stay recognisable.
Color _ensureContrast(Color fg, Color bg, double min) {
  if (contrastRatio(fg, bg) >= min) return fg;
  final darken = bg.computeLuminance() > 0.5;
  var hsl = HSLColor.fromColor(fg);
  for (var i = 0; i < 40 && contrastRatio(hsl.toColor(), bg) < min; i++) {
    final l = (hsl.lightness + (darken ? -0.02 : 0.02)).clamp(0.0, 1.0);
    hsl = hsl.withLightness(l);
  }
  return hsl.toColor();
}

/// White or near-black, whichever reads better on [bg].
Color _onColor(Color bg) =>
    contrastRatio(Colors.white, bg) >= contrastRatio(const Color(0xFF1A1225), bg)
        ? Colors.white
        : const Color(0xFF1A1225);

ThemeData buildAppTheme(AppTheme theme) {
  final spec = kThemeSpecs[theme]!;
  final isDark = spec.brightness == Brightness.dark;

  final containerHighest = isDark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), spec.surface)
      : Color.alphaBlend(spec.primary.withValues(alpha: 0.08), spec.surface);

  final seeded = ColorScheme.fromSeed(
    seedColor: spec.primary,
    brightness: spec.brightness,
  );

  // AA (4.5:1) for anything that renders as text, checked against the
  // surface it can sit on. Verified in test/theme_contrast_test.dart for
  // all three themes.
  // Text sits on both the page background and cards, so check both.
  final primary = _ensureContrast(
      _ensureContrast(spec.primary, spec.background, 4.5), spec.surface, 4.5);
  final textGold = _ensureContrast(
      _ensureContrast(spec.gold, spec.surface, 4.5), spec.background, 4.5);
  final onSurfaceVariant =
      _ensureContrast(seeded.onSurfaceVariant, containerHighest, 4.5);
  // Non-text UI (borders that convey state, focus rings): 3:1.
  final outline = _ensureContrast(seeded.outline, spec.background, 3);

  final scheme = seeded.copyWith(
    primary: primary,
    onPrimary: _onColor(primary),
    surface: spec.background,
    onSurface: spec.text,
    onSurfaceVariant: onSurfaceVariant,
    tertiary: textGold,
    onTertiary: _onColor(textGold),
    outline: outline,
    outlineVariant: spec.border,
    surfaceContainerLowest: spec.surface,
    surfaceContainerLow: spec.surface,
    surfaceContainer: isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.04), spec.surface)
        : Color.alphaBlend(spec.primary.withValues(alpha: 0.04), spec.surface),
    surfaceContainerHighest: containerHighest,
  );

  final tokens = KTokens(
    gold: spec.gold,
    motif: spec.gold,
    // Light backgrounds need more ink for the same presence.
    motifBandOpacity: isDark ? 0.45 : 0.6,
    motifCornerOpacity: isDark ? 0.55 : 0.7,
    motifFieldOpacity: isDark ? 0.07 : 0.09,
    focusRing: _ensureContrast(primary, spec.surface, 3),
    cardBorder: spec.border,
    cardBorderHover: Color.lerp(spec.border, primary, 0.45)!,
    skeletonBase: containerHighest,
    skeletonHighlight: spec.surface,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  TextStyle? serif(TextStyle? s) {
    if (s == null) return null;
    return debugUseSystemFonts ? s : GoogleFonts.fraunces(textStyle: s);
  }

  // Type scale: Fraunces for display/headline/titleLarge (and the wordmark),
  // the platform sans for everything people read in volume.
  final t = base.textTheme;
  final textTheme = t
      .copyWith(
        displayLarge: serif(t.displayLarge?.copyWith(fontWeight: FontWeight.w600)),
        displayMedium: serif(t.displayMedium?.copyWith(fontWeight: FontWeight.w600)),
        displaySmall: serif(t.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        headlineLarge: serif(t.headlineLarge?.copyWith(fontWeight: FontWeight.w600)),
        headlineMedium: serif(t.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        headlineSmall: serif(t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        titleLarge: serif(t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: t.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
        bodySmall: t.bodySmall?.copyWith(height: 1.4),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 0.8),
      )
      .apply(bodyColor: spec.text, displayColor: spec.text);

  final buttonShape = spec.pillButtons
      ? const StadiumBorder()
      : const RoundedRectangleBorder(borderRadius: kerawangCut);

  const buttonPadding =
      EdgeInsets.symmetric(horizontal: KSpace.xl - 4, vertical: KSpace.m + 2);
  // Touch-target floor: 48 px tall for every button (usability rule 7).
  const buttonMinSize = Size(64, 48);

  // Themed interaction overlays (hover / focus / pressed) so every
  // clickable surface reacts the same way.
  final hover = scheme.primary.withValues(alpha: 0.08);
  final focus = scheme.primary.withValues(alpha: 0.14);
  final pressed = scheme.primary.withValues(alpha: 0.16);
  WidgetStateProperty<Color?> overlay(Color tint) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return tint.withValues(alpha: 0.16);
        if (states.contains(WidgetState.focused)) return tint.withValues(alpha: 0.14);
        if (states.contains(WidgetState.hovered)) return tint.withValues(alpha: 0.08);
        return null;
      });
  // Visible keyboard focus ring on text buttons (web).
  final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) =>
      states.contains(WidgetState.focused)
          ? BorderSide(color: tokens.focusRing, width: 2)
          : null);
  final outlinedColor = isDark ? spec.gold : primary;

  return base.copyWith(
    extensions: [tokens],
    textTheme: textTheme,
    scaffoldBackgroundColor: spec.background,
    cardColor: spec.surface,
    dividerColor: spec.border,
    hoverColor: hover,
    focusColor: focus,
    highlightColor: pressed,
    splashColor: pressed,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: spec.text,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: spec.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.card,
        side: BorderSide(color: spec.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.secondaryContainer,
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle:
          textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48))
          .copyWith(overlayColor: overlay(scheme.onSurface)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        textStyle: textTheme.labelLarge?.copyWith(
          fontWeight: theme == AppTheme.kampus ? FontWeight.w700 : FontWeight.w600,
        ),
      ).copyWith(overlayColor: overlay(scheme.onPrimary)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        elevation: 0,
      ).copyWith(overlayColor: overlay(scheme.primary)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        foregroundColor: outlinedColor,
      ).copyWith(
        overlayColor: overlay(outlinedColor),
        side: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.focused)
                ? BorderSide(color: tokens.focusRing, width: 2)
                : BorderSide(color: isDark ? spec.gold : spec.border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: buttonMinSize)
          .copyWith(overlayColor: overlay(primary), side: focusSide),
    ),
    // Floating, width-limited toasts instead of a full-bleed bar glued to
    // the bottom of a wide window (UI_UX_AUDIT G4).
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 420,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    // Every form field in the app inherits this — no per-screen borders.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      hoverColor: hover,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: KSpace.l, vertical: KSpace.m + 2),
      border: OutlineInputBorder(
        borderRadius: KRadius.card,
        borderSide: BorderSide(color: spec.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: KRadius.card,
        borderSide: BorderSide(color: spec.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: KRadius.card,
        borderSide: BorderSide(color: primary, width: 2),
      ),
      hintStyle: textTheme.bodyLarge?.copyWith(color: onSurfaceVariant),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: spec.pillButtons
          ? const StadiumBorder()
          : const RoundedRectangleBorder(borderRadius: KRadius.small),
      side: BorderSide(color: spec.border),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}
