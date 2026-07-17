import 'package:flutter/material.dart';

/// Kerawang-inspired diamond ornament — the app's signature motif.
///
/// Use as a divider or decorative accent (login header, sidebar footer,
/// empty states, section breaks). Kept deliberately subtle: identity
/// comes from repetition, not size.
class KerawangDivider extends StatelessWidget {
  final double size;
  final Color? color;

  const KerawangDivider({super.key, this.size = 8, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.tertiary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _diamond(c.withValues(alpha: 0.45), size * 0.6),
        SizedBox(width: size),
        _diamond(c, size),
        SizedBox(width: size),
        _diamond(c.withValues(alpha: 0.45), size * 0.6),
      ],
    );
  }

  Widget _diamond(Color c, double s) => Transform.rotate(
        angle: 0.785398, // 45°
        child: Container(width: s, height: s, color: c),
      );
}
