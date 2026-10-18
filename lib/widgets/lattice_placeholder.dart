import 'package:flutter/material.dart';

/// Stand-in for the foundation branch's KerawangLattice: a faint grid of
/// diamonds in [color]. Decorative only (excluded from semantics) and
/// never placed behind body text. Replace usages when foundation lands.
class LatticePlaceholder extends StatelessWidget {
  final Color color;
  final double cell;
  final double opacity;
  final Widget? child;

  const LatticePlaceholder({
    super.key,
    required this.color,
    this.cell = 24,
    this.opacity = 0.35,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LatticePainter(color.withValues(alpha: opacity), cell),
      child: child,
    );
  }
}

class _LatticePainter extends CustomPainter {
  final Color color;
  final double cell;
  _LatticePainter(this.color, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double y = 0; y < size.height + cell; y += cell) {
      for (double x = 0; x < size.width + cell; x += cell) {
        final path = Path()
          ..moveTo(x, y - cell / 2)
          ..lineTo(x + cell / 2, y)
          ..lineTo(x, y + cell / 2)
          ..lineTo(x - cell / 2, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LatticePainter old) =>
      old.color != color || old.cell != cell;
}
