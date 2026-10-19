import 'package:flutter/material.dart';

/// Window size classes — the single source of truth for layout.
///
/// | class    | width      | navigation                         |
/// |----------|------------|------------------------------------|
/// | compact  | < 600      | bottom bar (Home, Market, Create, Events, Profile); Search in the top bar |
/// | medium   | 600–899    | navigation rail + one column (max 680) |
/// | expanded | 900–1199   | sidebar 240 + feed 680             |
/// | large    | ≥ 1200     | sidebar + feed + right rail        |
enum WindowSize {
  compact,
  medium,
  expanded,
  large;

  bool get isCompact => this == compact;
  bool get isMedium => this == medium;

  /// Expanded or large: sidebar layout, dialogs instead of sheets, no FAB,
  /// two-column detail pages.
  bool get isExpanded => index >= expanded.index;
  bool get isLarge => this == large;

  /// At least [other] (e.g. `size >= WindowSize.medium`).
  bool operator >=(WindowSize other) => index >= other.index;
  bool operator <(WindowSize other) => index < other.index;
}

/// Responsive helpers for phone / tablet / desktop (web).
class Responsive {
  Responsive._();

  // --- Breakpoints: the only place layout widths are decided. ---

  static const double mediumBreakpoint = 600;

  /// At or above: sidebar layout, dialogs instead of sheets, no FAB,
  /// two-column detail pages.
  static const double desktopBreakpoint = 900;

  /// At or above: the right rail (events / market) appears next to the feed.
  static const double railBreakpoint = 1200;

  /// Phone layout clamp used by [ResponsiveShell] until the medium rail
  /// layout ships (see [ResponsiveShell.clampMidBand]).
  static const double clampedMobileWidth = 840;

  // --- Column widths ---

  /// Outer clamp for the whole app on very large screens.
  static const double maxContentWidth = 1320;

  /// Max width of the center feed / single content column.
  static const double feedMaxWidth = 680;

  /// Desktop sidebar and right rail.
  static const double sidebarWidth = 240;
  static const double rightRailWidth = 300;

  /// Two-column detail pages (media left, details right) at ≥900.
  static const double detailMaxWidth = 1200;

  static WindowSize sizeFor(double width) {
    if (width < mediumBreakpoint) return WindowSize.compact;
    if (width < desktopBreakpoint) return WindowSize.medium;
    if (width < railBreakpoint) return WindowSize.expanded;
    return WindowSize.large;
  }

  /// Size class of the whole window. Inside a constrained pane prefer
  /// `LayoutBuilder` + [sizeFor] on the pane's own width.
  static WindowSize sizeOf(BuildContext context) =>
      sizeFor(MediaQuery.sizeOf(context).width);

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => sizeOf(context).isCompact;
  static bool isMedium(BuildContext context) => sizeOf(context).isMedium;

  /// ≥900 (expanded or large).
  static bool isDesktop(BuildContext context) => sizeOf(context).isExpanded;
  static bool showRightRail(BuildContext context) => sizeOf(context).isLarge;

  /// Card-grid columns for the space a grid actually has:
  /// 2 (<600) · 3 (<900) · 4 (<1200) · 5.
  static int gridColumnsFor(double availableWidth) =>
      switch (sizeFor(availableWidth)) {
        WindowSize.compact => 2,
        WindowSize.medium => 3,
        WindowSize.expanded => 4,
        WindowSize.large => 5,
      };

  /// Tile-width based column count (kept for existing grids), 2–5.
  static int gridColumns(double availableWidth, {double minTileWidth = 200}) {
    final cols = (availableWidth / minTileWidth).floor();
    return cols.clamp(2, 5);
  }

  /// Page gutter for the current size: 16 on phones, 24 above.
  static double gutter(BuildContext context) =>
      isCompact(context) ? 16 : 24;
}

/// Centers a pushed page's content (detail screens, create forms) at a
/// comfortable reading width on desktop. No-op on phones.
class PageBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PageBody({super.key, required this.child, this.maxWidth = 680});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // Let users select and copy prices, phone numbers, descriptions —
        // a basic web expectation (UI_UX_AUDIT A5 / 0.16).
        child: SelectionArea(child: child),
      ),
    );
  }
}

/// Wraps the entire app (via `MaterialApp.builder`).
///
/// With [clampMidBand] (the default, legacy behaviour) widths between
/// [Responsive.clampedMobileWidth] and the desktop breakpoint get the phone
/// layout clamped and centred. Pass `clampMidBand: false` once MainScaffold
/// renders the medium (navigation rail) layout — then this is a no-op.
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  final bool clampMidBand;

  const ResponsiveShell({
    super.key,
    required this.child,
    this.clampMidBand = true,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;

    if (!clampMidBand ||
        width >= Responsive.desktopBreakpoint ||
        width <= Responsive.clampedMobileWidth) {
      return child;
    }

    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: Responsive.clampedMobileWidth),
          child: MediaQuery(
            data: media.copyWith(
                size: Size(Responsive.clampedMobileWidth, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
