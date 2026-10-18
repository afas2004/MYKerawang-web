import 'package:flutter/material.dart';

/// Tappable surface for cards, grid tiles and media tiles.
///
/// Use instead of `GestureDetector(onTap:)`: InkWell gives a pointer cursor,
/// hover/focus highlight and keyboard activation on web (UI_UX_AUDIT G6),
/// and the Material clips the ripple to [borderRadius].
class TapCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Card fill. Null = transparent (the child paints its own background).
  final Color? color;

  /// Optional outline, drawn by the Material so it follows [borderRadius].
  final BorderSide? border;

  const TapCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}
