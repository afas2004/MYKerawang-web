import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Where the lattice is used; picks the default opacity from [KTokens].
enum LatticeVariant {
  /// One row of tiles: the thin strip at the top of headers / the sidebar.
  band,

  /// A triangle of tiles fading out from one corner: official / pinned
  /// cards, login, empty-state medallions.
  corner,

  /// An even field of tiles: splash, empty states. The faintest variant;
  /// never put it behind body text.
  field,
}

/// The kerawang motif: a procedural openwork lattice like the carved
/// panels of a rumah Melayu. Each tile is a diamond with an inner diamond
/// and four spokes; adjacent tiles meet at their tips, and the gaps
/// between them get a small solid "pierced" diamond.
///
/// Decorative only: excluded from semantics and hit-testing, wrapped in a
/// RepaintBoundary, and painted as one path per opacity level, so it's
/// cheap even as a full field.
///
///   const KerawangLattice.band()                       // header strip
///   const KerawangLattice.corner(corner: Alignment.topRight, extent: 40)
///   const SizedBox(height: 120, child: KerawangLattice())  // field
class KerawangLattice extends StatelessWidget {
  final LatticeVariant variant;

  /// Edge length of one tile in logical pixels.
  final double tileSize;

  /// Defaults to [KTokens.motif].
  final Color? color;

  /// Defaults to the token opacity for [variant].
  final double? opacity;

  /// [LatticeVariant.corner] only: which corner the ornament grows from.
  final Alignment corner;

  /// [LatticeVariant.corner] only: width and height of the ornament.
  final double extent;

  final double strokeWidth;

  /// A field lattice filling its parent (give it bounded constraints).
  const KerawangLattice({
    super.key,
    this.tileSize = 18,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  })  : variant = LatticeVariant.field,
        corner = Alignment.topLeft,
        extent = 0;

  /// A single row, [tileSize] tall, as wide as its parent allows.
  const KerawangLattice.band({
    super.key,
    this.tileSize = 10,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  })  : variant = LatticeVariant.band,
        corner = Alignment.topLeft,
        extent = 0;

  /// A corner ornament [extent]×[extent], fading toward the inside.
  const KerawangLattice.corner({
    super.key,
    this.corner = Alignment.topRight,
    this.extent = 40,
    this.tileSize = 10,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  }) : variant = LatticeVariant.corner;

  @override
  Widget build(BuildContext context) {
    final k = KTokens.of(context);
    final alpha = opacity ??
        switch (variant) {
          LatticeVariant.band => k.motifBandOpacity,
          LatticeVariant.corner => k.motifCornerOpacity,
          LatticeVariant.field => k.motifFieldOpacity,
        };
    final painter = _LatticePainter(
      variant: variant,
      tile: tileSize,
      color: color ?? k.motif,
      opacity: alpha,
      corner: corner,
      strokeWidth: strokeWidth,
    );

    Widget paint = CustomPaint(painter: painter);
    paint = switch (variant) {
      LatticeVariant.band =>
        SizedBox(height: tileSize, width: double.infinity, child: paint),
      LatticeVariant.corner =>
        SizedBox(width: extent, height: extent, child: paint),
      LatticeVariant.field => SizedBox.expand(child: paint),
    };

    return ExcludeSemantics(
      child: IgnorePointer(child: RepaintBoundary(child: paint)),
    );
  }
}

class _LatticePainter extends CustomPainter {
  final LatticeVariant variant;
  final double tile;
  final Color color;
  final double opacity;
  final Alignment corner;
  final double strokeWidth;

  _LatticePainter({
    required this.variant,
    required this.tile,
    required this.color,
    required this.opacity,
    required this.corner,
    required this.strokeWidth,
  });

  /// One tile's strokes, origin at its top-left.
  static Path _tileStrokes(double t) {
    final c = t / 2;
    final r = t * 0.21; // inner diamond half-diagonal
    return Path()
      // outer diamond (tips touch the neighbouring tiles)
      ..moveTo(c, 0)
      ..lineTo(t, c)
      ..lineTo(c, t)
      ..lineTo(0, c)
      ..close()
      // inner diamond
      ..moveTo(c, c - r)
      ..lineTo(c + r, c)
      ..lineTo(c, c + r)
      ..lineTo(c - r, c)
      ..close()
      // spokes: inner tips to outer tips
      ..moveTo(c, 0)
      ..lineTo(c, c - r)
      ..moveTo(t, c)
      ..lineTo(c + r, c)
      ..moveTo(c, t)
      ..lineTo(c, c + r)
      ..moveTo(0, c)
      ..lineTo(c - r, c);
  }

  /// The small solid diamond in the gap where four tiles meet.
  static Path _pierce(double t, Offset at) {
    final r = t * 0.11;
    return Path()
      ..moveTo(at.dx, at.dy - r)
      ..lineTo(at.dx + r, at.dy)
      ..lineTo(at.dx, at.dy + r)
      ..lineTo(at.dx - r, at.dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || tile <= 0 || opacity <= 0) return;
    final tilePath = _tileStrokes(tile);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    final fill = Paint()..style = PaintingStyle.fill;

    void draw(Path strokes, Path dots, double a) {
      final c = color.withValues(alpha: (color.a * a).clamp(0.0, 1.0));
      canvas.drawPath(strokes, stroke..color = c);
      canvas.drawPath(dots, fill..color = c);
    }

    switch (variant) {
      case LatticeVariant.band:
        // Centre the row so the pattern is symmetric in any width.
        final count = (size.width / tile).ceil() + 1;
        final start = (size.width - count * tile) / 2;
        final top = (size.height - tile) / 2;
        final strokes = Path();
        final dots = Path();
        for (var i = 0; i < count; i++) {
          final o = Offset(start + i * tile, top);
          strokes.addPath(tilePath, o);
          dots.addPath(_pierce(tile, o + Offset(0, tile / 2)), Offset.zero);
        }
        draw(strokes, dots, opacity);

      case LatticeVariant.field:
        final cols = (size.width / tile).ceil() + 1;
        final rows = (size.height / tile).ceil() + 1;
        final ox = (size.width - cols * tile) / 2;
        final oy = (size.height - rows * tile) / 2;
        final strokes = Path();
        final dots = Path();
        for (var y = 0; y < rows; y++) {
          for (var x = 0; x < cols; x++) {
            final o = Offset(ox + x * tile, oy + y * tile);
            strokes.addPath(tilePath, o);
            dots.addPath(_pierce(tile, o), Offset.zero);
          }
        }
        draw(strokes, dots, opacity);

      case LatticeVariant.corner:
        canvas.save();
        // Paint as if anchored top-left, then mirror into place.
        if (corner.x > 0) {
          canvas.translate(size.width, 0);
          canvas.scale(-1, 1);
        }
        if (corner.y > 0) {
          canvas.translate(0, size.height);
          canvas.scale(1, -1);
        }
        final n = math.max(1, (math.min(size.width, size.height) / tile).floor());
        // One path per diagonal so each ring fades a step further.
        for (var d = 0; d < n; d++) {
          final strokes = Path();
          final dots = Path();
          for (var x = 0; x <= d; x++) {
            final o = Offset(x * tile, (d - x) * tile);
            strokes.addPath(tilePath, o);
            dots.addPath(_pierce(tile, o), Offset.zero);
          }
          draw(strokes, dots, opacity * (1 - d / n));
        }
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LatticePainter old) =>
      old.variant != variant ||
      old.tile != tile ||
      old.color != color ||
      old.opacity != opacity ||
      old.corner != corner ||
      old.strokeWidth != strokeWidth;
}
