import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'official_frame.dart';

/// The standard card: surface fill, 12-radius outline, and consistent
/// hover / keyboard-focus / pressed feedback when tappable.
///
/// - hover: outline darkens and the card lifts slightly
/// - focus: a 2 px focus ring drawn outside the layout (no jump)
/// - pressed: themed ink ripple
///
/// [official] switches to the kerawang cut and wraps it in [OfficialFrame]
/// (gold hairline + corner lattice) — for official / pinned content only.
///
///   KCard(onTap: () => context.goEvent(e), child: ...)
///   KCard(official: true, semanticLabel: s.pinned, child: ...)
class KCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Official / pinned styling (kerawang cut + gold frame).
  final bool official;

  /// Overrides the radius (defaults: [KRadius.card], or [KRadius.cut] when
  /// [official]).
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
    final radius = widget.borderRadius ??
        (widget.official ? KRadius.cut : KRadius.card);
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final lifted = interactive && _hovered;

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
        border: Border.all(
          color: widget.official
              ? k.gold
              : (lifted ? k.cardBorderHover : k.cardBorder),
        ),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: k.elevationRaised * 3,
                  offset: Offset(0, k.elevationRaised / 2),
                ),
              ]
            : null,
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
      card = OfficialFrame(borderRadius: radius, child: card);
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
