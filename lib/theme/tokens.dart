import 'package:flutter/material.dart';

/// Design tokens: the only place spacing, radii, motion and the brand's
/// special colours are decided. Screens read these instead of hand-setting
/// numbers (DESIGN_SPEC §2; shared UI direction).
///
///   padding: const EdgeInsets.all(KSpace.l)
///   borderRadius: KRadius.card
///   duration: KMotion.of(context).medium
///   color: KTokens.of(context).gold

/// Spacing scale 4 / 8 / 12 / 16 / 24 / 32. Nothing in between.
abstract final class KSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter on phones; cards sit this far from the edge.
  static const double gutter = l;
}

/// Corner radii — uniform and the same in every theme. Buttons and chips
/// are fully rounded (stadium) via the theme.
abstract final class KRadius {
  static const double cardValue = 16;

  /// Cards, media, embeds.
  static const BorderRadius card = BorderRadius.all(Radius.circular(cardValue));

  /// Text fields, search bars, filled list tiles.
  static const BorderRadius input = BorderRadius.all(Radius.circular(12));

  /// Badges, small thumbnails.
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));

  /// Bottom sheets (top corners only).
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(24));

  /// Dialogs.
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(20));

  /// Pills: buttons, chips, tags.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));

  /// Deprecated: the asymmetric "kerawang cut" was retired in the modern
  /// redesign. Kept so existing call sites compile; equals [card].
  static const BorderRadius cut = card;
}

/// Motion: 150–250 ms, standard easing. Use [KMotion.of] so durations
/// collapse to zero when the platform asks for reduced motion.
class KMotion {
  final Duration fast;
  final Duration medium;
  final Duration slow;

  const KMotion._(this.fast, this.medium, this.slow);

  static const standard = KMotion._(
    Duration(milliseconds: 150),
    Duration(milliseconds: 200),
    Duration(milliseconds: 250),
  );
  static const none = KMotion._(Duration.zero, Duration.zero, Duration.zero);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  /// True when the OS/browser asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static KMotion of(BuildContext context) =>
      reduced(context) ? none : standard;
}

/// Theme-dependent brand roles, attached to ThemeData as an extension.
@immutable
class KTokens extends ThemeExtension<KTokens> {
  /// The one accent (the logo's marigold), used sparingly: prices,
  /// verified, pinned/official markers, the one accent button per screen —
  /// as icon or fill. For accent *text* use `colorScheme.tertiary` (AA-safe
  /// on every surface). The name predates the marigold.
  final Color gold;

  /// Text / icons on a [gold] fill (white or near-black, whichever passes).
  final Color onAccent;

  /// Deprecated with the lattice motif (which now renders nothing).
  /// Kept for API compatibility; equals [gold].
  final Color motif;

  /// Deprecated with the lattice motif; 0 in every theme.
  final double motifBandOpacity;
  final double motifCornerOpacity;
  final double motifFieldOpacity;

  /// Keyboard focus ring colour (≥3:1 against surfaces).
  final Color focusRing;

  /// The third analysis colour, beside primary (purple) and gold: programme
  /// feedback in the form editor and answer page. Contrast-checked against the
  /// surfaces it is used on, like [gold].
  final Color feedback;

  /// Card outline at rest and on hover.
  final Color cardBorder;
  final Color cardBorderHover;

  /// Shimmer base/highlight for skeletons.
  final Color skeletonBase;
  final Color skeletonHighlight;

  /// Elevations: cards rest flat; raised = hover / dialogs on desktop.
  final double elevationRest;
  final double elevationRaised;

  const KTokens({
    required this.gold,
    required this.motif,
    required this.motifBandOpacity,
    required this.motifCornerOpacity,
    required this.motifFieldOpacity,
    required this.focusRing,
    required this.cardBorder,
    required this.cardBorderHover,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.feedback,
    required this.onAccent,
    this.elevationRest = 0,
    this.elevationRaised = 3,
  });

  /// Alias for [gold]: the one accent colour.
  Color get accent => gold;

  /// Tokens for the current theme. Falls back to a neutral set so widgets
  /// still render under a bare `ThemeData()` (tests, dialogs in isolation).
  static KTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<KTokens>() ?? KTokens.fallback(theme.colorScheme);
  }

  factory KTokens.fallback(ColorScheme scheme) => KTokens(
        gold: scheme.tertiary,
        motif: scheme.tertiary,
        motifBandOpacity: 0,
        motifCornerOpacity: 0,
        motifFieldOpacity: 0,
        focusRing: scheme.primary,
        cardBorder: scheme.outlineVariant,
        cardBorderHover: scheme.outline,
        skeletonBase: scheme.surfaceContainerHighest,
        skeletonHighlight: scheme.surfaceContainer,
        feedback: scheme.secondary,
        onAccent: scheme.onTertiary,
      );

  @override
  KTokens copyWith({
    Color? gold,
    Color? motif,
    double? motifBandOpacity,
    double? motifCornerOpacity,
    double? motifFieldOpacity,
    Color? focusRing,
    Color? cardBorder,
    Color? cardBorderHover,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? feedback,
    Color? onAccent,
    double? elevationRest,
    double? elevationRaised,
  }) =>
      KTokens(
        gold: gold ?? this.gold,
        motif: motif ?? this.motif,
        motifBandOpacity: motifBandOpacity ?? this.motifBandOpacity,
        motifCornerOpacity: motifCornerOpacity ?? this.motifCornerOpacity,
        motifFieldOpacity: motifFieldOpacity ?? this.motifFieldOpacity,
        focusRing: focusRing ?? this.focusRing,
        cardBorder: cardBorder ?? this.cardBorder,
        cardBorderHover: cardBorderHover ?? this.cardBorderHover,
        skeletonBase: skeletonBase ?? this.skeletonBase,
        skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
        feedback: feedback ?? this.feedback,
        onAccent: onAccent ?? this.onAccent,
        elevationRest: elevationRest ?? this.elevationRest,
        elevationRaised: elevationRaised ?? this.elevationRaised,
      );

  @override
  KTokens lerp(KTokens? other, double t) {
    if (other == null) return this;
    double d(double a, double b) => a + (b - a) * t;
    return KTokens(
      gold: Color.lerp(gold, other.gold, t)!,
      motif: Color.lerp(motif, other.motif, t)!,
      motifBandOpacity: d(motifBandOpacity, other.motifBandOpacity),
      motifCornerOpacity: d(motifCornerOpacity, other.motifCornerOpacity),
      motifFieldOpacity: d(motifFieldOpacity, other.motifFieldOpacity),
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardBorderHover: Color.lerp(cardBorderHover, other.cardBorderHover, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      feedback: Color.lerp(feedback, other.feedback, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      elevationRest: d(elevationRest, other.elevationRest),
      elevationRaised: d(elevationRaised, other.elevationRaised),
    );
  }
}

/// WCAG relative-contrast ratio between two opaque colours (1–21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
