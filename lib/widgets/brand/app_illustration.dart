import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/tokens.dart';
import 'app_motif.dart';
import 'songket_hem.dart';

/// The app's spot illustrations: Open Peeps students (CC0) in a hand line,
/// with Malaysian stitch motifs (WP25, CC BY 4.0) and a few Fluent emoji
/// (MIT). Sources and licences: assets/illustrations/LICENSE.md.
enum AppIllo {
  emptyFeed,
  emptyMarket,
  noEvents,
  noNotifications,
  noResults,
  welcome,
  login,
  offline,

  /// 404: the kite's string snapped ("Wau terputus tali").
  notFound,

  /// Something failed to load: a songket hem with one loose thread.
  error,

  /// Guests reaching a signed-in feature: a student peeking in.
  guestGate,
}

/// A theme-tinted scene. The people's ink follows the theme text colour and
/// their fill the surface, so they hold up on Songket Noir; motifs take the
/// primary (plum) or the accent (marigold).
///
///   AppIllustration(AppIllo.emptyFeed, size: 200)
///
/// Every scene is drawn on one fixed 240 × 180 canvas and scaled as a whole
/// ([FittedBox]), so the parts keep their places and nothing clips or
/// overflows at any size. [size] is the width; height is ¾ of it.
///
/// Decorative by default (hidden from screen readers); pass
/// [semanticLabel] when the picture itself carries meaning.
class AppIllustration extends StatelessWidget {
  final AppIllo illo;
  final double size;
  final String? semanticLabel;

  const AppIllustration(this.illo, {super.key, this.size = 200, this.semanticLabel});

  static const double canvasWidth = 240;
  static const double canvasHeight = 180;

  /// Every asset a scene uses (for preloading and tests).
  static Set<String> assetsOf(AppIllo illo) => {
        for (final l in _scenes[illo]!)
          if (l.asset != null) l.asset!,
      };

  static final Map<String, Future<String>> _cache = {};

  static Future<String> _load(String asset) =>
      _cache.putIfAbsent(asset, () => rootBundle.loadString(asset));

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Rewrites the people art for the current theme: black ink becomes the
  /// text colour, white fill the surface, the doodle pink the accent.
  static String recolor(String svg, ColorScheme scheme, {Color? accent}) {
    final dark = scheme.brightness == Brightness.dark;
    final map = <String, String>{
      '#000000': _hex(scheme.onSurface),
      '#ffffff': _hex(dark ? scheme.surfaceContainerHigh : Colors.white),
      '#ff5678': _hex(accent ?? scheme.tertiary),
      '#4f66af': _hex(scheme.primary),
    };
    return svg.replaceAllMapped(
      RegExp(r'#[0-9a-fA-F]{6}\b', caseSensitive: false),
      (m) => map[m.group(0)!.toLowerCase()] ?? m.group(0)!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layers = _scenes[illo]!;
    final picture = SizedBox(
      width: size,
      height: size * canvasHeight / canvasWidth,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [for (final l in layers) l.build(context)],
          ),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: picture);
    return Semantics(label: semanticLabel, image: true, child: picture);
  }
}

// ---------------------------------------------------------------------------
// Scenes. Coordinates are on the 240 × 180 canvas; people stand on the
// bottom edge.
// ---------------------------------------------------------------------------

const _people = 'assets/illustrations/people';
const _emoji = 'assets/illustrations/emoji';

final Map<AppIllo, List<_Layer>> _scenes = {
  AppIllo.notFound: [
    const _Motif(AppMotif.wauBulan, left: 146, top: 2, size: 86),
    const _Line([Offset(156, 74), Offset(138, 88), Offset(120, 100)], dashed: true),
    const _Line([Offset(102, 110), Offset(94, 118), Offset(86, 128)], dashed: true),
    const _Person('peep-standing-5', left: 22, height: 176, aspect: 680 / 304),
  ],
  AppIllo.emptyFeed: [
    const _Person('peep-sitting-2', left: 22, height: 150, aspect: 521 / 346),
    const _Person('peep-72', left: 140, height: 112, aspect: 324 / 240),
  ],
  AppIllo.emptyMarket: [
    const _Person('peep-standing-20', left: 46, height: 176, aspect: 706 / 213),
    const _Motif(AppMotif.nasiLemak, left: 124, top: 80, size: 94, accent: true),
  ],
  AppIllo.noEvents: [
    const _Motif(AppMotif.wauKucing, left: 140, top: 0, size: 92),
    const _Person('peep-sitting-14', left: 10, height: 150, aspect: 603 / 462),
  ],
  AppIllo.offline: [
    const _Line([Offset(8, 172), Offset(80, 166), Offset(160, 172), Offset(232, 168)]),
    const _Motif(AppMotif.wauJalaBudi, left: 24, top: 96, size: 74, angle: -1.2),
    const _Person('peep-standing-26', left: 156, height: 168, aspect: 677 / 246),
  ],
  AppIllo.noNotifications: [
    const _Person('doodle-meditating', left: 12, height: 162, aspect: 768 / 1024),
  ],
  AppIllo.noResults: [
    const _Person('peep-standing-22', left: 46, height: 176, aspect: 691 / 321),
    const _Emoji('magnifier', left: 150, top: 46, size: 40),
  ],
  AppIllo.welcome: [
    const _Person('peep-standing-12', left: 12, height: 164, aspect: 710 / 255),
    const _Person('peep-standing-5', left: 62, height: 172, aspect: 680 / 304),
    const _Person('peep-standing-16', left: 122, height: 164, aspect: 652 / 309),
    const _Person('peep-standing-20', left: 184, height: 172, aspect: 706 / 213),
  ],
  AppIllo.login: [
    const _Motif(AppMotif.wauBulan, left: 148, top: 6, size: 76),
    const _Line([Offset(160, 66), Offset(130, 96), Offset(98, 112)], dashed: true),
    const _Person('peep-standing-5', left: 34, height: 176, aspect: 680 / 304),
  ],
  AppIllo.error: [
    const _Hem(left: 0, top: 0, width: 150, height: 8),
    const _Line([Offset(148, 6), Offset(160, 34), Offset(142, 62), Offset(156, 92), Offset(146, 118)]),
    const _Person('peep-standing-22', left: 40, height: 168, aspect: 691 / 321),
  ],
  AppIllo.guestGate: [
    const _Card(left: 104, top: 28, width: 120, height: 104),
    const _Emoji('locked', left: 146, top: 62, size: 36),
    const _Person('peep-63', left: 4, height: 124, aspect: 324 / 240),
  ],
};

abstract class _Layer {
  const _Layer();
  String? get asset => null;
  Widget build(BuildContext context);
}

class _Person extends _Layer {
  final String file;
  final double left;
  final double height;

  /// Height / width of the art.
  final double aspect;

  const _Person(this.file, {required this.left, required this.height, required this.aspect});

  @override
  String get asset => '$_people/$file.svg';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = KTokens.of(context).accent;
    final width = height / aspect;
    return Positioned(
      left: left,
      bottom: 0,
      width: width,
      height: height,
      child: FutureBuilder<String>(
        future: AppIllustration._load(asset),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return SvgPicture.string(
            AppIllustration.recolor(snap.data!, scheme, accent: accent),
            width: width,
            height: height,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            excludeFromSemantics: true,
          );
        },
      ),
    );
  }
}

class _Motif extends _Layer {
  final AppMotif motif;
  final double left, top, size;

  /// Radians.
  final double angle;
  final bool accent;

  const _Motif(this.motif,
      {required this.left, required this.top, required this.size, this.angle = 0, this.accent = false});

  @override
  String get asset => motif.asset;

  @override
  Widget build(BuildContext context) {
    final color = accent ? KTokens.of(context).accent : Theme.of(context).colorScheme.primary;
    Widget art = MotifArt(motif, size: size, color: color);
    if (angle != 0) art = Transform.rotate(angle: angle, child: art);
    return Positioned(left: left, top: top, width: size, height: size, child: art);
  }
}

class _Emoji extends _Layer {
  final String file;
  final double left, top, size;
  const _Emoji(this.file, {required this.left, required this.top, required this.size});

  @override
  String get asset => '$_emoji/$file.svg';

  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        top: top,
        width: size,
        height: size,
        child: SvgPicture.asset(asset, width: size, height: size, excludeFromSemantics: true),
      );
}

/// A kite string or a loose thread, in the primary colour.
class _Line extends _Layer {
  final List<Offset> points;
  final bool dashed;
  const _Line(this.points, {this.dashed = false});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: CustomPaint(
          painter: _LinePainter(points, Theme.of(context).colorScheme.primary, dashed),
        ),
      );
}

class _LinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final bool dashed;
  const _LinePainter(this.points, this.color, this.dashed);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // A smooth curve through the points (midpoint quadratic segments).
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.points != points || old.dashed != dashed;
}

class _Hem extends _Layer {
  final double left, top, width, height;
  const _Hem({required this.left, required this.top, required this.width, required this.height});

  @override
  String get asset => SongketHem.asset;

  @override
  Widget build(BuildContext context) => Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: SongketHem(height: height),
      );
}

/// A plain surface card (the locked page in the guest scene).
class _Card extends _Layer {
  final double left, top, width, height;
  const _Card({required this.left, required this.top, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: KRadius.input,
          border: Border.all(color: KTokens.of(context).cardBorder, width: 1.5),
        ),
      ),
    );
  }
}
