import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_motif.dart';
import 'brand_cover.dart' show stableHash;

/// The app's one ground: "Corak kampus", small line drawings of Malay and
/// campus life scattered at low strength behind everything — the way
/// Telegram and WhatsApp put a quiet doodle wallpaper behind chats.
///
/// It is the only pattern most screens have. Cards and bars sit on top as
/// plain surfaces, so the drawings only show in the gaps.
///
/// Placed once, behind the router (`MaterialApp.builder`); the theme's
/// scaffold background is transparent so it shows through. Drawn from one
/// 240 px tile rendered to an image and repeated, so it costs one shader
/// fill per frame and never clips or misaligns at any size.
class KGround extends StatefulWidget {
  final Widget child;

  /// Opacity of the drawings (0–1). 0.06 is the shipped default.
  final double strength;

  const KGround({super.key, required this.child, this.strength = 0.06});

  /// The drawings, 24 × 24, single stroke.
  static const glyphs = <String, String>{
    'wau': '<path d="M12 2C9 5 5 6.5 2 7.5c3.5 2 7 3 10 3.5 3-.5 6.5-1.5 10-3.5C19 6.5 15 5 12 2Z"/><path d="M12 11v6"/><path d="M8.5 17.5c1.5 1.8 5.5 1.8 7 0-1.5-1.2-5.5-1.2-7 0Z"/><path d="M12 19.5v3"/>',
    'ketupat': '<path d="M12 3l8 8-8 8-8-8z"/><path d="M8 7l8 8M16 7l-8 8"/><path d="M12 19v3"/>',
    'bungaraya': '<circle cx="12" cy="6.5" r="3"/><circle cx="17.2" cy="10.3" r="3"/><circle cx="15.2" cy="16.5" r="3"/><circle cx="8.8" cy="16.5" r="3"/><circle cx="6.8" cy="10.3" r="3"/><path d="M12 12l5-6"/>',
    'star': '<rect x="6.5" y="6.5" width="11" height="11"/><path d="M12 4.2l7.8 7.8-7.8 7.8L4.2 12z"/>',
    'songket': '<path d="M12 3l4 4-4 4-4-4z"/><path d="M12 13l4 4-4 4-4-4z"/><path d="M3 12h4M17 12h4"/>',
    'book': '<path d="M3 5h6a3 3 0 0 1 3 3v12a2 2 0 0 0-2-2H3z"/><path d="M21 5h-6a3 3 0 0 0-3 3v12a2 2 0 0 1 2-2h7z"/>',
    'cap': '<path d="M2 9l10-5 10 5-10 5z"/><path d="M6 11v5c3 2 9 2 12 0v-5"/><path d="M22 9v6"/>',
    'tea': '<path d="M5 9h11v5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z"/><path d="M16 11h2a2 2 0 0 1 0 4h-2"/><path d="M8 3c-1 1 1 2 0 3M12 3c-1 1 1 2 0 3"/>',
    'note': '<path d="M9 18V6l10-2v12"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="16" r="2"/>',
    'pencil': '<path d="M4 20l1-5L16 4l4 4L9 19z"/><path d="M14 6l4 4"/>',
    'ball': '<circle cx="12" cy="12" r="9"/><path d="M12 8l3 2-1 3.5h-4L9 10z"/><path d="M12 8V3.5M15 10l4-1.5M14 13.5l2.5 3.5M10 13.5L7.5 17M9 10L5 8.5"/>',
    'bike': '<circle cx="6" cy="16" r="3.5"/><circle cx="18" cy="16" r="3.5"/><path d="M6 16l4-7h5l3 7M10 9l3 7M14 6h2"/>',
  };

  /// Where each drawing sits in the 240 px tile, and its turn (degrees).
  /// Spaced so no two touch, including across the tile seams.
  static const _spots = <(String, double, double, double)>[
    ('wau', 18, 14, -12), ('book', 96, 8, 8), ('star', 170, 22, 0),
    ('tea', 52, 70, -6), ('ketupat', 132, 74, 14), ('cap', 200, 92, -10),
    ('note', 10, 128, 10), ('bungaraya', 80, 132, 0), ('pencil', 150, 140, -20),
    ('ball', 206, 176, 0), ('songket', 40, 190, 0), ('bike', 112, 196, -4),
  ];

  static const double tile = 240;

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// One tile as SVG: every drawing in [ink] at [opacity].
  static String tileSvg(Color ink, double opacity) {
    const size = 26.0;
    final body = StringBuffer();
    for (final (name, x, y, turn) in _spots) {
      body.write('<g transform="translate($x $y) rotate($turn ${size / 2} ${size / 2}) '
          'scale(${size / 24})">${glyphs[name]}</g>');
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="$tile" height="$tile" '
        'viewBox="0 0 $tile $tile"><g fill="none" stroke="${_hex(ink)}" '
        'stroke-opacity="$opacity" stroke-width="1.5" stroke-linecap="round" '
        'stroke-linejoin="round">$body</g></svg>';
  }

  @override
  State<KGround> createState() => _KGroundState();
}

class _KGroundState extends State<KGround> {
  /// Rendered tiles by theme/strength/dpr. Shared, so a page that carries
  /// its own ground while it slides (see transitions.dart) paints the
  /// drawings on its first frame instead of popping them in.
  static final _cache = <String, ui.Image>{};

  ui.Image? _tile;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureTile();
  }

  @override
  void didUpdateWidget(KGround old) {
    super.didUpdateWidget(old);
    _ensureTile();
  }

  Future<void> _ensureTile() async {
    final theme = Theme.of(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final key = '${theme.colorScheme.primary.toARGB32()}|${widget.strength}|$dpr';
    if (key == _key) return;
    _key = key;
    if (widget.strength <= 0) {
      setState(() => _tile = null);
      return;
    }
    final cached = _cache[key];
    if (cached != null) {
      // Called just before a build, so no setState is needed.
      _tile = cached;
      return;
    }
    try {
      final svg = KGround.tileSvg(theme.colorScheme.primary, widget.strength);
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      // Re-render at device resolution so the strokes stay crisp.
      final px = (KGround.tile * dpr).round();
      final rec = ui.PictureRecorder();
      ui.Canvas(rec)
        ..scale(px / info.size.width)
        ..drawPicture(info.picture);
      info.picture.dispose();
      final image = await rec.endRecording().toImage(px, px);
      _cache[key] = image;
      if (!mounted || key != _key) return;
      setState(() => _tile = image);
    } catch (_) {
      // No drawings is a fine fallback: the plain ground still shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surface;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _GroundPainter(bg, _tile, dpr)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _GroundPainter extends CustomPainter {
  final Color background;
  final ui.Image? tile;
  final double dpr;
  const _GroundPainter(this.background, this.tile, this.dpr);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    if (tile == null) return;
    final m = Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1).storage;
    canvas.drawRect(
      rect,
      Paint()..shader = ImageShader(tile!, TileMode.repeated, TileMode.repeated, m),
    );
  }

  @override
  bool shouldRepaint(_GroundPainter old) =>
      old.background != background || old.tile != tile || old.dpr != dpr;
}

/// A cover for an item with no photo: a soft wash of its colour with one
/// Malaysian stitch drawing (wau, nasi lemak, sape — the WP25 set) in that
/// colour. Calm on purpose — the ground already carries the pattern, so
/// covers don't add another.
class KTintCover extends StatelessWidget {
  final String seed;
  final Color color;

  /// Which drawings this kind of item may get (see [eventMotifs]).
  final List<AppMotif> motifs;

  static const eventMotifs = [AppMotif.wauBulan, AppMotif.wauKucing, AppMotif.wauJalaBudi, AppMotif.sape];
  static const listingMotifs = [AppMotif.nasiLemak, AppMotif.sape, AppMotif.wauKucing];

  /// On top (a date stub, a price tag).
  final Widget? child;

  const KTintCover({super.key, required this.seed, required this.color, this.motifs = eventMotifs, this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? Color.lerp(color, Colors.white, 0.45)! : color;
    final wash = Color.alphaBlend(color.withValues(alpha: dark ? 0.32 : 0.14), theme.cardColor);
    return ColoredBox(
      color: wash,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: LayoutBuilder(builder: (context, box) {
              final size = (box.maxHeight.isFinite ? box.maxHeight * 0.7 : 56.0).clamp(24.0, 110.0).toDouble();
              return MotifArt(motifs[stableHash(seed) % motifs.length], size: size, color: ink);
            }),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}
