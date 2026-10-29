import 'package:flutter/material.dart';

import 'brand_cover.dart' show KPalette;

/// The "kepala kain" header: on the main tabs the app bar is a solid plum
/// band with softly rounded lower corners — no strip, no pattern, no sharp
/// edges; the app's one ground (KGround) already carries the drawings. One
/// tone on every main tab so the frame reads as one piece.
///
///   appBar: KBand.appBar(context, tone: KBand.home, title: ..., actions: ...)
///
/// The tones are brand palette colours, all ≥ 4.5:1 under white text; on dark
/// themes they're deepened so the band doesn't glare.
abstract final class KBand {
  static const home = KPalette.plum;
  static const news = KPalette.plum;
  static const market = KPalette.plum;
  static const events = KPalette.plum;

  /// Text and icons on the band.
  static const Color onBand = Colors.white;

  /// Radius of the band's rounded lower corners.
  static const double footRadius = 22;

  static const ShapeBorder _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(footRadius)),
  );

  static Color colorOf(BuildContext context, Color tone) =>
      Theme.of(context).brightness == Brightness.dark
          ? Color.lerp(tone, Colors.black, 0.35)!
          : tone;

  /// 20 px (not the usual 22) so "Pengumuman" / "Announcements" fit beside
  /// five actions on a 360 px phone.
  static TextStyle? _title(BuildContext context) => Theme.of(context)
      .appBarTheme
      .titleTextStyle
      ?.copyWith(color: onBand, fontSize: 20, letterSpacing: -0.3);

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
      shape: _shape,
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
      shape: _shape,
    );
  }
}
