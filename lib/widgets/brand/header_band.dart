import 'package:flutter/material.dart';

import 'brand_cover.dart' show KPalette;
import 'k_pattern.dart';
import 'songket_hem.dart';

/// The "kepala kain" header: on the main tabs the app bar becomes a band of
/// colour with a faint star pattern and a songket hem along its lower edge,
/// like the head panel of a kain. Each tab has its own [tone]; everything
/// under the band stays plain.
///
///   appBar: KBand.appBar(context, tone: KBand.home, title: ..., actions: ...)
///
/// The tones are brand palette colours, all ≥ 4.5:1 under white text; on dark
/// themes they're deepened so the band doesn't glare.
abstract final class KBand {
  static const home = KPalette.plum;
  static const news = KPalette.biruLaut;
  static const market = KPalette.jingga;
  static const events = KPalette.hijauPucuk;

  /// Text and icons on the band.
  static const Color onBand = Colors.white;

  static const double hemHeight = 9;

  static Color colorOf(BuildContext context, Color tone) =>
      Theme.of(context).brightness == Brightness.dark
          ? Color.lerp(tone, Colors.black, 0.35)!
          : tone;

  static Widget _pattern() => KPattern(
        kind: KPatternKind.star8,
        color: onBand.withValues(alpha: 0.09),
        cell: 34,
      );

  static PreferredSizeWidget _hem() => PreferredSize(
        preferredSize: const Size.fromHeight(hemHeight),
        child: SongketHem(height: hemHeight, color: onBand.withValues(alpha: 0.7)),
      );

  static TextStyle? _title(BuildContext context) =>
      Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: onBand);

  static AppBar appBar(
    BuildContext context, {
    required Color tone,
    Widget? title,
    List<Widget>? actions,
  }) {
    return AppBar(
      title: title,
      actions: actions,
      backgroundColor: colorOf(context, tone),
      foregroundColor: onBand,
      iconTheme: const IconThemeData(color: onBand),
      actionsIconTheme: const IconThemeData(color: onBand),
      titleTextStyle: _title(context),
      flexibleSpace: _pattern(),
      bottom: _hem(),
    );
  }

  /// The same band for a [CustomScrollView] (Home's floating app bar).
  static SliverAppBar sliverAppBar(
    BuildContext context, {
    required Color tone,
    Widget? title,
    List<Widget>? actions,
    bool floating = true,
    bool snap = true,
  }) {
    return SliverAppBar(
      floating: floating,
      snap: snap,
      title: title,
      actions: actions,
      centerTitle: false,
      backgroundColor: colorOf(context, tone),
      foregroundColor: onBand,
      iconTheme: const IconThemeData(color: onBand),
      actionsIconTheme: const IconThemeData(color: onBand),
      titleTextStyle: _title(context),
      flexibleSpace: _pattern(),
      bottom: _hem(),
    );
  }
}
