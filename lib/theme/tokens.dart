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

/// Corner radii. [cut] is the signature asymmetric "kerawang cut".
abstract final class KRadius {
  /// Hero media, primary buttons (Istana/Noir), pinned/official cards.
  static const BorderRadius cut = BorderRadius.only(
    topLeft: Radius.circular(2),
    topRight: Radius.circular(14),
    bottomRight: Radius.circular(2),
    bottomLeft: Radius.circular(14),
  );

  /// Regular cards, inputs, sheets.
  static const BorderRadius card = BorderRadius.all(Radius.circular(12));

  /// Chips, badges, small tiles.
  static const BorderRadius small = BorderRadius.all(Radius.circular(8));

  static const double cardValue = 12;
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
  /// Decorative gold: motif strokes, hairlines, verified/official marks,
  /// the ◆ glyph. Not guaranteed to pass AA as small text on light themes —
  /// for gold *text* use `colorScheme.tertiary` (text-safe).
  final Color gold;

  /// Lattice/motif colour (usually gold or a muted primary).
  final Color motif;

  /// Motif opacity per placement: band (headers), corner (official cards),
  /// field (empty states, splash — the faintest).
  final double motifBandOpacity;
  final double motifCornerOpacity;
  final double motifFieldOpacity;

  /// Keyboard focus ring colour (≥3:1 against surfaces).
  final Color focusRing;

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
    this.elevationRest = 0,
    this.elevationRaised = 3,
  });

  /// Tokens for the current theme. Falls back to a neutral set so widgets
  /// still render under a bare `ThemeData()` (tests, dialogs in isolation).
  static KTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<KTokens>() ?? KTokens.fallback(theme.colorScheme);
  }

  factory KTokens.fallback(ColorScheme scheme) => KTokens(
        gold: scheme.tertiary,
        motif: scheme.tertiary,
        motifBandOpacity: 0.5,
        motifCornerOpacity: 0.6,
        motifFieldOpacity: 0.08,
        focusRing: scheme.primary,
        cardBorder: scheme.outlineVariant,
        cardBorderHover: scheme.outline,
        skeletonBase: scheme.surfaceContainerHighest,
        skeletonHighlight: scheme.surfaceContainer,
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
