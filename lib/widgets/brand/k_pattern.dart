import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The three repeating motifs, drawn in code so they take any colour and
/// stay crisp at every size:
///
/// - [star8]: bintang lapan, the 8-point star of Malay and Islamic geometry
/// - [pucuk]: pucuk rebung, the bamboo-shoot triangles of songket borders
/// - [tabur]: bunga tabur, small scattered diamonds
enum KPatternKind { star8, pucuk, tabur }

/// Fills its box with a faint repeating motif over an optional background.
/// The pattern is clipped to the box, so it never spills or overflows.
///
/// Patterns are for grounds that have nothing else to say (login, banners,
/// covers with no photo). Everyday screens stay plain.
///
///   KPattern(kind: KPatternKind.star8, color: plum.withValues(alpha: .16))
class KPattern extends StatelessWidget {
  final KPatternKind kind;

  /// Line / fill colour of the motif, alpha included.
  final Color color;

  /// Painted under the motif; transparent when null.
  final Color? background;

  /// Tile size in logical pixels.
  final double cell;

  /// Rotation of the whole pattern, in degrees.
  final double angle;

  final Widget? child;

  const KPattern({
    super.key,
    required this.kind,
    required this.color,
    this.background,
    this.cell = 36,
    this.angle = 0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: child == null,
      child: CustomPaint(
        painter: KPatternPainter(
          kind: kind,
          color: color,
          background: background,
          cell: cell,
          angle: angle,
        ),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

class KPatternPainter extends CustomPainter {
  final KPatternKind kind;
  final Color color;
  final Color? background;
  final double cell;
  final double angle;

  const KPatternPainter({
    required this.kind,
    required this.color,
    this.background,
    this.cell = 36,
    this.angle = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    if (background != null) canvas.drawRect(bounds, Paint()..color = background!);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, cell / 28)
      ..isAntiAlias = true;
    final fill = Paint()..color = color;

    // Rotate about the centre and cover the whole diagonal, so rotated
    // patterns still reach every corner.
    final c = size.center(Offset.zero);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle * math.pi / 180);
    final reach = size.longestSide;
    final n = (reach / cell).ceil() + 1;
    for (var i = -n; i <= n; i++) {
      for (var j = -n; j <= n; j++) {
        _tile(canvas, Offset(i * cell, j * cell), stroke, fill);
      }
    }
    canvas.restore();
  }

  void _tile(Canvas canvas, Offset o, Paint stroke, Paint fill) {
    final s = cell;
    switch (kind) {
      case KPatternKind.star8:
        final mid = o + Offset(s / 2, s / 2);
        final a = s * 0.18;
        final b = a * math.sqrt2;
        canvas.drawRect(Rect.fromCenter(center: mid, width: a * 2, height: a * 2), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(mid.dx, mid.dy - b)
            ..lineTo(mid.dx + b, mid.dy)
            ..lineTo(mid.dx, mid.dy + b)
            ..lineTo(mid.dx - b, mid.dy)
            ..close(),
          stroke,
        );
        canvas.drawCircle(o, s * 0.045, fill);
      case KPatternKind.pucuk:
        Path tri(double l, double r, double top) => Path()
          ..moveTo(o.dx + l * s, o.dy + s)
          ..lineTo(o.dx + s / 2, o.dy + top * s)
          ..lineTo(o.dx + r * s, o.dy + s)
          ..close();
        canvas.drawPath(tri(0, 1, 0.12), stroke);
        canvas.drawPath(tri(0.25, 0.75, 0.5), stroke);
        canvas.drawLine(o + Offset(s / 2, s * 0.12), o + Offset(s / 2, s * 0.5), stroke);
      case KPatternKind.tabur:
        void diamond(Offset p, double r) => canvas.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - r)
              ..lineTo(p.dx + r, p.dy)
              ..lineTo(p.dx, p.dy + r)
              ..lineTo(p.dx - r, p.dy)
              ..close(),
            fill);
        diamond(o + Offset(s / 2, s / 2), s * 0.12);
        diamond(o, s * 0.06);
    }
  }

  @override
  bool shouldRepaint(KPatternPainter old) =>
      old.kind != kind ||
      old.color != color ||
      old.background != background ||
      old.cell != cell ||
      old.angle != angle;
}
