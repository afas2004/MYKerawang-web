import 'package:flutter/material.dart';

/// Responsive helpers for phone / tablet / desktop (web).
class Responsive {
  Responsive._();

  /// Outer clamp for the whole app on very large screens.
  /// Wide enough for the desktop 3-column layout (sidebar + feed + rail).
  static const double maxContentWidth = 1320;

  /// Max width of the center feed column on desktop.
  static const double feedMaxWidth = 680;

  // --- Breakpoints: the only place layout widths are decided. ---

  /// At or above: sidebar + feed layout, dialogs instead of sheets, no FAB.
  static const double desktopBreakpoint = 900;

  /// At or above: the right rail (events / market) appears next to the feed.
  static const double railBreakpoint = 1150;

  /// Between this and [desktopBreakpoint] the phone layout is clamped to
  /// this width so it doesn't stretch.
  static const double clampedMobileWidth = 840;

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isDesktop(BuildContext context) =>
      screenWidth(context) >= desktopBreakpoint;

  /// Column count for card grids based on the available width.
  /// e.g. 2 columns on phones, 3-4 on wider screens.
  static int gridColumns(double availableWidth, {double minTileWidth = 200}) {
    final cols = (availableWidth / minTileWidth).floor();
    return cols.clamp(2, 4);
  }
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

/// Wraps the entire app (via `MaterialApp.builder`) so that on wide
/// screens the content is centered at [Responsive.maxContentWidth]
/// instead of stretching edge-to-edge. On phones it is a no-op.
class ResponsiveShell extends StatelessWidget {
  final Widget child;
  const ResponsiveShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;

    // Desktop: MainScaffold lays out sidebar/feed/rail itself and
    // should span edge-to-edge like a real web app. Phones: no-op.
    if (width >= Responsive.desktopBreakpoint ||
        width <= Responsive.clampedMobileWidth) {
      return child;
    }

    // Awkward mid-band: clamp the mobile layout so it doesn't stretch,
    // since the desktop layout hasn't kicked in yet.
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
