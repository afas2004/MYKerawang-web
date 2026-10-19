import 'package:flutter/material.dart';

/// Tappable surface for cards, grid tiles and media tiles.
///
/// Use instead of `GestureDetector(onTap:)`: InkWell gives a pointer cursor,
/// hover/focus highlight and keyboard activation on web (UI_UX_AUDIT G6),
/// and the Material clips the ripple to [borderRadius].
///
/// [hoverLift] raises the card slightly on mouse hover and keyboard focus
/// (browse grids). It's skipped when the platform asks for reduced motion.
class TapCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Card fill. Null = transparent (the child paints its own background).
  final Color? color;

  /// Optional outline, drawn by the Material so it follows [borderRadius].
  final BorderSide? border;

  final bool hoverLift;

  /// Screen-reader label for the whole card.
  final String? semanticLabel;

  const TapCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color,
    this.border,
    this.hoverLift = false,
    this.semanticLabel,
  });

  @override
  State<TapCard> createState() => _TapCardState();
}

class _TapCardState extends State<TapCard> {
  bool _raised = false;

  void _setRaised(bool v) {
    if (widget.hoverLift && v != _raised) setState(() => _raised = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final lifted = _raised && !reduceMotion;

    Widget card = Material(
      color: widget.color ?? Colors.transparent,
      elevation: lifted ? 4 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: widget.borderRadius,
        side: widget.border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHover: widget.hoverLift ? _setRaised : null,
        onFocusChange: widget.hoverLift ? _setRaised : null,
        child: widget.child,
      ),
    );

    if (widget.hoverLift) {
      card = AnimatedSlide(
        offset: lifted ? const Offset(0, -0.01) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: card,
      );
    }

    if (widget.semanticLabel != null) {
      card = Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        child: card,
      );
    }
    return card;
  }
}
