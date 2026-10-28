import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';
import 'transitions.dart';

export 'app_icons.dart';
export 'tokens.dart';

/// The three named MYKerawang themes. They share one system — Fraunces for
/// headlines, Plus Jakarta Sans for everything else, 16-radius cards,
/// stadium buttons, 1px borders, the logo's plum with one marigold accent
/// used sparingly — and differ only in palette:
/// Kampus Bold (clean light), Istana Modern (warm light), Songket Noir (dark).
enum AppTheme { kampus, istana, noir }

/// Deprecated: the asymmetric "kerawang cut" was retired; this is now the
/// standard card radius. Kept so existing call sites compile.
const BorderRadius kerawangCut = KRadius.card;

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

  /// Page background (tier 0).
  final Color background;

  /// Cards (tier 1).
  final Color surface;

  /// Sheets, dialogs, menus, pressed fills (tier 2).
  final Color elevated;

  /// Brand plum (from the logo).
  final Color primary;

  /// The single accent (the logo's marigold): prices, verified, pinned, and
  /// the one accent button per screen. Used sparingly.
  final Color gold;

  /// The third analysis colour: programme feedback in the KI form editor and
  /// answer page, beside [primary] (KI before) and [gold] (KI after).
  final Color feedback;

  final Color text;

  /// Secondary text (captions, metadata).
  final Color textMuted;

  /// The 1px hairline used on cards, inputs and dividers.
  final Color border;

  const AppThemeSpec({
    required this.displayName,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.primary,
    required this.gold,
    required this.feedback,
    required this.text,
    required this.textMuted,
    required this.border,
  });
}

const Map<AppTheme, AppThemeSpec> kThemeSpecs = {
  // Cool near-white; the logo's plum and marigold.
  AppTheme.kampus: AppThemeSpec(
    displayName: "Kampus Bold",
    brightness: Brightness.light,
    background: Color(0xFFF6F5F8),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFFFFFFF),
    primary: Color(0xFF5E1A4F),
    gold: Color(0xFFE07128),
    feedback: Color(0xFF16786B),
    text: Color(0xFF22101E),
    textMuted: Color(0xFF625660),
    border: Color(0xFFE7E1E6),
  ),
  // Warm paper tones, a deeper plum.
  AppTheme.istana: AppThemeSpec(
    displayName: "Istana Modern",
    brightness: Brightness.light,
    background: Color(0xFFF7F3EE),
    surface: Color(0xFFFFFDF9),
    elevated: Color(0xFFFFFFFF),
    primary: Color(0xFF55163F),
    gold: Color(0xFFD0661F),
    feedback: Color(0xFF146C60),
    text: Color(0xFF22140F),
    textMuted: Color(0xFF645549),
    border: Color(0xFFEAE1D6),
  ),
  // Plum-tinted near-black, lifted plum for contrast.
  AppTheme.noir: AppThemeSpec(
    displayName: "Songket Noir",
    brightness: Brightness.dark,
    background: Color(0xFF130C11),
    surface: Color(0xFF1D141A),
    elevated: Color(0xFF271C24),
    primary: Color(0xFFD9A0C8),
    gold: Color(0xFFF29550),
    feedback: Color(0xFF6FD3C4),
    text: Color(0xFFF3EAF0),
    textMuted: Color(0xFFB7A6B1),
    border: Color(0xFF33252E),
  ),
};

/// Tests can't download fonts; set this to use the platform font instead of
/// Plus Jakarta Sans (layout is otherwise identical).
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

/// Passes [min] against both surfaces text can sit on.
Color _ensureOnBoth(Color fg, Color a, Color b, double min) =>
    _ensureContrast(_ensureContrast(fg, a, min), b, min);

/// White or near-black, whichever reads better on [bg].
Color _onColor(Color bg) =>
    contrastRatio(Colors.white, bg) >= contrastRatio(const Color(0xFF14121A), bg)
        ? Colors.white
        : const Color(0xFF14121A);

ThemeData buildAppTheme(AppTheme theme) {
  final spec = kThemeSpecs[theme]!;
  final isDark = spec.brightness == Brightness.dark;

  final seeded = ColorScheme.fromSeed(
    seedColor: spec.primary,
    brightness: spec.brightness,
  );

  // Surface tiers: background → card → elevated, plus two neutral fills
  // for inputs/chips and hovered/pressed rows.
  final fillLow = isDark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.04), spec.surface)
      : Color.alphaBlend(spec.text.withValues(alpha: 0.035), spec.surface);
  final fillHigh = isDark
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), spec.surface)
      : Color.alphaBlend(spec.text.withValues(alpha: 0.07), spec.surface);

  // AA (4.5:1) for anything rendered as text, against every tier it can
  // sit on. Guarded by test/theme_contrast_test.dart.
  final primary = _ensureOnBoth(spec.primary, spec.background, spec.surface, 4.5);
  final accentText = _ensureOnBoth(spec.gold, spec.background, spec.surface, 4.5);
  final muted = _ensureOnBoth(spec.textMuted, spec.background, fillHigh, 4.5);
  // Non-text UI (state borders, focus rings): 3:1.
  final outline = _ensureContrast(seeded.outline, spec.background, 3);

  // A soft brand tint for selected nav items / tonal buttons.
  final primaryContainer = isDark
      ? Color.alphaBlend(primary.withValues(alpha: 0.20), spec.surface)
      : Color.alphaBlend(primary.withValues(alpha: 0.10), spec.surface);
  final onPrimaryContainer =
      _ensureContrast(isDark ? spec.text : primary, primaryContainer, 4.5);

  final scheme = seeded.copyWith(
    primary: primary,
    onPrimary: _onColor(primary),
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondaryContainer: primaryContainer,
    onSecondaryContainer: onPrimaryContainer,
    tertiary: accentText,
    onTertiary: _onColor(accentText),
    surface: spec.background,
    onSurface: spec.text,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: spec.border,
    surfaceContainerLowest: spec.surface,
    surfaceContainerLow: spec.surface,
    surfaceContainer: fillLow,
    surfaceContainerHigh: spec.elevated,
    surfaceContainerHighest: fillHigh,
    surfaceTint: Colors.transparent,
  );

  final tokens = KTokens(
    gold: spec.gold,
    motif: spec.gold,
    motifBandOpacity: 0,
    motifCornerOpacity: 0,
    motifFieldOpacity: 0,
    focusRing: _ensureOnBoth(primary, spec.surface, spec.background, 3),
    cardBorder: spec.border,
    cardBorderHover: Color.lerp(spec.border, spec.textMuted, 0.35)!,
    skeletonBase: fillHigh,
    // The shimmer sweep carries a little plum instead of plain white/grey.
    skeletonHighlight: Color.alphaBlend(
        primary.withValues(alpha: isDark ? 0.14 : 0.08), spec.surface),
    feedback: _ensureOnBoth(spec.feedback, spec.background, spec.surface, 4.5),
    onAccent: _onColor(spec.gold),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  // Two families: Fraunces (a soft serif) for display, headline and the
  // large title — page names, empty-state titles, the wordmark — and
  // Plus Jakarta Sans for everything people read or tap.
  final t = debugUseSystemFonts
      ? base.textTheme
      : GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
  TextStyle? display(TextStyle? s) =>
      debugUseSystemFonts || s == null ? s : GoogleFonts.fraunces(textStyle: s);
  final textTheme = t
      .copyWith(
        displayLarge: display(t.displayLarge?.copyWith(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.1)),
        displayMedium: display(t.displayMedium?.copyWith(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.12)),
        displaySmall: display(t.displaySmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.15)),
        headlineLarge: display(t.headlineLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2)),
        headlineMedium: display(t.headlineMedium?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2)),
        headlineSmall: display(t.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2)),
        titleLarge: display(t.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.1, height: 1.25)),
        titleMedium: t.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: t.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
        bodySmall: t.bodySmall?.copyWith(fontSize: 12, height: 1.4, color: muted),
        labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: t.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: t.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      )
      .apply(bodyColor: spec.text, displayColor: spec.text);
  // apply() overwrote bodySmall's muted colour; restore it.
  final finalText =
      textTheme.copyWith(bodySmall: textTheme.bodySmall?.copyWith(color: muted));

  const pill = StadiumBorder();
  const buttonPadding =
      EdgeInsets.symmetric(horizontal: KSpace.xl - 4, vertical: KSpace.m);
  // Touch-target floor: 48 px tall for every button.
  const buttonMinSize = Size(64, 48);

  // Themed interaction overlays (hover / focus / pressed).
  final hover = spec.text.withValues(alpha: 0.05);
  final focus = primary.withValues(alpha: 0.12);
  final pressed = spec.text.withValues(alpha: 0.10);
  WidgetStateProperty<Color?> overlay(Color tint) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return tint.withValues(alpha: 0.14);
        if (states.contains(WidgetState.focused)) return tint.withValues(alpha: 0.12);
        if (states.contains(WidgetState.hovered)) return tint.withValues(alpha: 0.08);
        return null;
      });
  // Visible keyboard focus ring (web).
  BorderSide? focusSide(Set<WidgetState> s) => s.contains(WidgetState.focused)
      ? BorderSide(color: tokens.focusRing, width: 2)
      : null;

  return base.copyWith(
    extensions: [tokens],
    textTheme: finalText,
    scaffoldBackgroundColor: spec.background,
    canvasColor: spec.background,
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
    iconTheme: IconThemeData(color: spec.text, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: spec.background,
      foregroundColor: spec.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: finalText.titleLarge,
      iconTheme: IconThemeData(color: spec.text, size: 22),
      shape: Border(bottom: BorderSide(color: Colors.transparent)),
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
    dividerTheme: DividerThemeData(color: spec.border, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      shape: const RoundedRectangleBorder(borderRadius: KRadius.input),
      subtitleTextStyle: finalText.bodySmall,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: spec.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((s) =>
          finalText.labelMedium?.copyWith(
              color: s.contains(WidgetState.selected) ? spec.text : muted)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? onPrimaryContainer : muted)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: spec.surface,
      indicatorColor: primaryContainer,
      indicatorShape: const StadiumBorder(),
      selectedIconTheme: IconThemeData(color: onPrimaryContainer, size: 22),
      unselectedIconTheme: IconThemeData(color: muted, size: 22),
      selectedLabelTextStyle: finalText.labelMedium?.copyWith(color: spec.text),
      unselectedLabelTextStyle: finalText.labelMedium?.copyWith(color: muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: spec.elevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: KRadius.sheet),
      showDragHandle: true,
      dragHandleColor: spec.border,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: spec.elevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: KRadius.dialog),
      titleTextStyle: finalText.titleLarge,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: spec.elevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.input,
        side: BorderSide(color: spec.border),
      ),
      textStyle: finalText.bodyMedium,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48))
          .copyWith(overlayColor: overlay(spec.text)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: _onColor(primary),
      elevation: 2,
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        textStyle: finalText.labelLarge,
      ).copyWith(
          overlayColor: overlay(_onColor(primary)),
          side: WidgetStateProperty.resolveWith(focusSide)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pill,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        elevation: 0,
        textStyle: finalText.labelLarge,
      ).copyWith(
          overlayColor: overlay(primary),
          side: WidgetStateProperty.resolveWith(focusSide)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        padding: buttonPadding,
        minimumSize: buttonMinSize,
        foregroundColor: spec.text,
        textStyle: finalText.labelLarge,
      ).copyWith(
        overlayColor: overlay(spec.text),
        side: WidgetStateProperty.resolveWith((s) =>
            focusSide(s) ?? BorderSide(color: spec.border)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        minimumSize: buttonMinSize,
        foregroundColor: primary,
        textStyle: finalText.labelLarge,
      ).copyWith(
          overlayColor: overlay(primary),
          side: WidgetStateProperty.resolveWith(focusSide)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: primaryContainer,
        selectedForegroundColor: onPrimaryContainer,
        side: BorderSide(color: spec.border),
        shape: pill,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: BorderSide(color: spec.border)),
      side: BorderSide(color: spec.border),
      backgroundColor: spec.surface,
      selectedColor: primaryContainer,
      labelStyle: finalText.labelLarge?.copyWith(color: spec.text),
      secondaryLabelStyle: finalText.labelLarge?.copyWith(color: onPrimaryContainer),
      checkmarkColor: onPrimaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: KSpace.xs),
    ),
    // Floating, width-limited toasts.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 420,
      shape: const RoundedRectangleBorder(borderRadius: KRadius.input),
      contentTextStyle: finalText.bodyMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    // Every form field in the app inherits this — no per-screen borders.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fillLow,
      hoverColor: hover,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: KSpace.l, vertical: KSpace.m + 2),
      border: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: spec.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: spec.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: primary, width: 2),
      ),
      hintStyle: finalText.bodyLarge?.copyWith(color: muted),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: spec.text,
      unselectedLabelColor: muted,
      indicatorColor: primary,
      // A rounded 3 px bar that slides between tabs.
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: primary, width: 3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
      dividerColor: spec.border,
      labelStyle: finalText.titleSmall,
      unselectedLabelStyle: finalText.titleSmall,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: finalText.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}
