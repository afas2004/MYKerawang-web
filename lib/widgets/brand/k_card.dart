import 'package:flutter/material.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import 'official_frame.dart';

/// The standard card: surface fill, 16-radius 1px outline, and consistent
/// hover / keyboard-focus / pressed feedback when tappable.
///
/// - hover: outline darkens (no shadow — the system uses borders, not
///   elevation)
/// - focus: a 2 px focus ring drawn outside the layout (no jump)
/// - pressed: themed ink ripple
///
/// [official] gives the card an accent outline; with [officialLabel] it also
/// shows a small accent label row at the top ("Pinned", "Official").
///
///   KCard(onTap: () => context.goEvent(e), child: ...)
///   KCard(official: true, officialLabel: s.pinned, child: ...)
class KCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Official / pinned styling (accent outline).
  final bool official;

  /// Label row text for [official] cards; no row when null.
  final String? officialLabel;

  /// Icon for the label row (defaults to [AppIcons.pin]).
  final IconData officialIcon;

  /// Overrides the radius (default [KRadius.card]).
  final BorderRadius? borderRadius;

  /// Fill; defaults to `theme.cardColor`.
  final Color? color;

  /// Read by screen readers instead of the merged child text.
  final String? semanticLabel;

  const KCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(KSpace.l),
    this.official = false,
    this.officialLabel,
    this.officialIcon = AppIcons.pin,
    this.borderRadius,
    this.color,
    this.semanticLabel,
  });

  @override
  State<KCard> createState() => _KCardState();
}

class _KCardState extends State<KCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final k = KTokens.of(context);
    final motion = KMotion.of(context);
    final outerRadius = widget.borderRadius ?? KRadius.card;
    // Inside an official frame the frame owns the shape (and clips to it),
    // so the card itself stays square-cornered — no nested-card look.
    final radius = widget.official ? BorderRadius.zero : outerRadius;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final hovered = interactive && _hovered;

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (interactive) {
      content = InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHover: (v) => setState(() => _hovered = v),
        onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: radius,
        child: content,
      );
    }

    Widget card = AnimatedContainer(
      duration: motion.fast,
      curve: KMotion.curve,
      decoration: BoxDecoration(
        color: widget.color ?? theme.cardColor,
        borderRadius: radius,
        // Official cards take their outline from the frame around them.
        border: widget.official
            ? null
            : Border.all(color: hovered ? k.cardBorderHover : k.cardBorder),
      ),
      // Focus ring painted on top so it never shifts the layout.
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: k.focusRing, width: 2),
            )
          : null,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );

    if (widget.official) {
      card = OfficialFrame(
        borderRadius: outerRadius,
        label: widget.officialLabel,
        icon: widget.officialIcon,
        child: card,
      );
    }
    if (widget.semanticLabel != null) {
      card = Semantics(
        label: widget.semanticLabel,
        button: interactive,
        container: true,
        child: card,
      );
    }
    return card;
  }
}
