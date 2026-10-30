import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../utils/responsive.dart';
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
///
/// Desktop (≥ 900) has no band: the sidebar already frames the page and holds
/// notifications and the profile, so a tab opens with a quiet page header
/// instead — the title large in the display face, on the page's own ground.
/// Only [desktopActions] (page-specific, e.g. "New announcement") show there.
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

  /// Page header height on desktop.
  static const double desktopHeight = 88;

  /// Height of the bar this context gets: the band, or the desktop header.
  static double heightOf(BuildContext context) =>
      Responsive.isDesktop(context) ? desktopHeight : kToolbarHeight;

  static TextStyle? _desktopTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.headlineMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    );
  }

  static List<Widget>? _withEdge(List<Widget>? actions) =>
      actions == null || actions.isEmpty
          ? null
          : [...actions, const SizedBox(width: KSpace.s)];

  static AppBar appBar(
    BuildContext context, {
    required Color tone,
    Widget? title,
    List<Widget>? actions,
    List<Widget>? desktopActions,
  }) {
    if (Responsive.isDesktop(context)) {
      return AppBar(
        title: title,
        actions: _withEdge(desktopActions),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        toolbarHeight: desktopHeight,
        titleSpacing: KSpace.l,
        titleTextStyle: _desktopTitle(context),
      );
    }
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
    List<Widget>? desktopActions,
    bool floating = true,
    bool snap = true,
    bool pinned = false,
    bool rounded = true,
  }) {
    if (Responsive.isDesktop(context)) {
      return SliverAppBar(
        title: title,
        actions: _withEdge(desktopActions),
        automaticallyImplyLeading: false,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        toolbarHeight: desktopHeight,
        titleSpacing: KSpace.l,
        titleTextStyle: _desktopTitle(context),
      );
    }
    return SliverAppBar(
      floating: floating,
      snap: snap,
      pinned: pinned,
      title: title,
      actions: actions,
      centerTitle: false,
      backgroundColor: colorOf(context, tone),
      foregroundColor: onBand,
      iconTheme: const IconThemeData(color: onBand),
      actionsIconTheme: const IconThemeData(color: onBand),
      titleTextStyle: _title(context),
      shape: rounded ? _shape : null,
    );
  }
}
