import 'dart:math' as math;
import 'dart:ui' as ui;

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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return ExcludeSemantics(
      excluding: child == null,
      // Its own layer, so nearby repaints don't re-record it. On the web that
      // is not enough: every frame is rasterised again, so the motif itself
      // is one cached tile image filled as a shader (see [KPatternPainter]).
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          painter: KPatternPainter(
            kind: kind,
            color: color,
            background: background,
            cell: cell,
            angle: angle,
            tile: KPatternPainter.tileImage(kind, color, cell, dpr),
            dpr: dpr,
          ),
          child: child ?? const SizedBox.expand(),
        ),
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

  /// One tile of the motif at device resolution. When given, the box is
  /// filled with it as a repeating shader: one draw per frame instead of
  /// three anti-aliased paths per tile (about 130 for the Home pin bar,
  /// replayed on every scroll frame because the web keeps no raster cache).
  final ui.Image? tile;
  final double dpr;

  const KPatternPainter({
    required this.kind,
    required this.color,
    this.background,
    this.cell = 36,
    this.angle = 0,
    this.tile,
    this.dpr = 1,
  });

  /// Rendered tiles, shared by every pattern with the same look. A handful
  /// at most (the pin bar's star, brand covers).
  static final _tiles = <String, ui.Image>{};

  /// The tile for this look, drawn once. The 3×3 neighbourhood is painted
  /// and clipped to one cell, so motifs that cross a cell edge (the star's
  /// corner dots, the pucuk's base line) wrap seamlessly when repeated.
  /// Null if this renderer can't snapshot a picture.
  static ui.Image? tileImage(KPatternKind kind, Color color, double cell, double dpr) {
    final px = (cell * dpr).round();
    if (px <= 0 || px > 1024) return null;
    final key = '${kind.name}|${color.toARGB32()}|$cell|$px';
    final hit = _tiles[key];
    if (hit != null) return hit;
    try {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec)..scale(px / cell);
      canvas.clipRect(Rect.fromLTWH(0, 0, cell, cell));
      final drawer = KPatternPainter(kind: kind, color: color, cell: cell);
      final stroke = drawer._stroke(), fill = Paint()..color = color;
      for (var i = -1; i <= 1; i++) {
        for (var j = -1; j <= 1; j++) {
          drawer._tile(canvas, Offset(i * cell, j * cell), stroke, fill);
        }
      }
      final picture = rec.endRecording();
      final image = picture.toImageSync(px, px);
      picture.dispose();
      return _tiles[key] = image;
    } catch (_) {
      return null;
    }
  }

  Paint _stroke() => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, cell / 28)
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    if (background != null) {
      canvas.drawRect(bounds, Paint()..color = background!);
    }

    final stroke = _stroke();
    final fill = Paint()..color = color;

    // Tiles sit on a grid centred on the box. Unrotated, only the tiles that
    // touch the box are drawn; rotated, the box's corners can reach as far as
    // half its diagonal from the centre, so that circle is covered. (This used
    // to cover twice the longest side both ways: about 2,000 draw calls for a
    // 360 px strip, repeated every frame it was repainted.)
    final c = size.center(Offset.zero);
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle * math.pi / 180);
    final rotated = angle % 360 != 0;
    final reachX = rotated
        ? size.bottomRight(Offset.zero).distance / 2
        : size.width / 2;
    final reachY = rotated ? reachX : size.height / 2;
    final image = tile;
    if (image != null) {
      // Tile (0,0) sits at the centre, as in the loop below.
      // Scale by cell/width, not 1/dpr: the tile's pixel size was rounded,
      // and the repeat must stay exactly one cell.
      final k = cell / image.width;
      final m = Matrix4.diagonal3Values(k, k, 1).storage;
      canvas.drawRect(
        Rect.fromLTRB(-reachX - cell, -reachY - cell, reachX + cell, reachY + cell),
        Paint()
          ..shader = ImageShader(image, TileMode.repeated, TileMode.repeated, m)
          ..filterQuality = FilterQuality.low,
      );
      canvas.restore();
      return;
    }
    for (var i = (-reachX / cell).floor() - 1; i * cell <= reachX; i++) {
      for (var j = (-reachY / cell).floor() - 1; j * cell <= reachY; j++) {
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
        canvas.drawRect(
          Rect.fromCenter(center: mid, width: a * 2, height: a * 2),
          stroke,
        );
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
        canvas.drawLine(
          o + Offset(s / 2, s * 0.12),
          o + Offset(s / 2, s * 0.5),
          stroke,
        );
      case KPatternKind.tabur:
        void diamond(Offset p, double r) => canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - r)
            ..lineTo(p.dx + r, p.dy)
            ..lineTo(p.dx, p.dy + r)
            ..lineTo(p.dx - r, p.dy)
            ..close(),
          fill,
        );
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
      old.angle != angle ||
      old.tile != tile ||
      old.dpr != dpr;
}
