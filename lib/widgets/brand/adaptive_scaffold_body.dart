import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../utils/responsive.dart';

/// List/detail or media/details layout that splits into two columns when
/// it has room, and stacks otherwise.
///
/// Decides on its **own** width (LayoutBuilder), not the window's, so it
/// stays single-column inside a narrow parent. Detail pages that want the
/// split on desktop must give it the space — e.g.
/// `DesktopChrome(maxWidth: Responsive.detailMaxWidth, ...)`.
///
/// Each pane scrolls itself in the split layout; when stacked, [compact]
/// is used if given, else both panes go in one scroll view.
///
///   AdaptiveScaffoldBody(
///     primary: EventGallery(...),        // media left
///     secondary: EventDetails(...),      // details right
///   )
class AdaptiveScaffoldBody extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;

  /// Width at which the panes split. Defaults to the desktop breakpoint.
  final double breakpoint;

  final int primaryFlex;
  final int secondaryFlex;

  /// Max width of the split layout (centred beyond that).
  final double maxWidth;

  /// Gap between the panes.
  final double gap;

  /// Layout to use when not split (e.g. a CustomScrollView with the media
  /// as a SliverAppBar). Defaults to primary-then-secondary in one scroll.
  final Widget? compact;

  const AdaptiveScaffoldBody({
    super.key,
    required this.primary,
    this.secondary,
    this.breakpoint = Responsive.desktopBreakpoint,
    this.primaryFlex = 5,
    this.secondaryFlex = 4,
    this.maxWidth = Responsive.detailMaxWidth,
    this.gap = KSpace.xl,
    this.compact,
  });

  /// True when a pane of [width] would be split.
  bool splitsAt(double width) => secondary != null && width >= breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (!splitsAt(constraints.maxWidth)) {
        if (compact != null) return compact!;
        if (secondary == null) return primary;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, secondary!],
          ),
        );
      }
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: primaryFlex, child: primary),
                SizedBox(width: gap),
                Expanded(flex: secondaryFlex, child: secondary!),
              ],
            ),
          ),
        ),
      );
    });
  }
}
