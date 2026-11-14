import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Malaysian stitch drawings from the Wikimedia Malaysia "WP25" set, by
/// Geleparaplu, CC BY 4.0 (credited in the app's licences page; see
/// assets/brand/LICENSE.md). Single colour, so each takes any tint.
enum AppMotif {
  wauBulan('wau_bulan'),
  wauKucing('wau_kucing'),
  wauJalaBudi('wau_jala_budi'),
  nasiLemak('nasi_lemak'),
  sape('sape');

  final String file;
  const AppMotif(this.file);

  String get asset => 'assets/brand/motifs/$file.svg';
}

/// One stitch motif, square, in a single colour (the theme primary by
/// default). Decorative: hidden from screen readers.
///
///   MotifArt(AppMotif.wauBulan, size: 96)
///
/// Each drawing is 170–600 stitched paths. Drawn as vectors, every card
/// without a photo replayed all of them on every scroll frame, which made
/// lists stutter on phones. So each motif is drawn ONCE per size bucket into
/// a bitmap (white on transparent) and shared; the colour is applied when
/// the bitmap is painted, which is cheap. Until a bucket's bitmap is ready
/// (one frame or so, the first time only) the vector version shows, so
/// nothing pops in.
class MotifArt extends StatefulWidget {
  final AppMotif motif;
  final double size;
  final Color? color;

  const MotifArt(this.motif, {super.key, this.size = 96, this.color});

  /// Bitmap side in device pixels for [logical] at [dpr]: rounded up to a
  /// multiple of 64 so nearby sizes share one bitmap, capped at 512.
  @visibleForTesting
  static int bucket(double logical, double dpr) {
    final px = (logical * dpr).ceil().clamp(1, 512);
    return ((px + 63) ~/ 64 * 64).clamp(64, 512);
  }

  /// Shared bitmaps, newest last. Small: a few motifs × a few sizes.
  static final _cache = <String, ui.Image>{};
  static final _pending = <String, Future<ui.Image?>>{};
  static const _maxCached = 24;

  static Future<ui.Image?> _render(AppMotif motif, int px) {
    final key = '${motif.file}|$px';
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _pending.putIfAbsent(key, () async {
      try {
        final info = await vg.loadPicture(SvgAssetLoader(motif.asset), null);
        final side = info.size.longestSide;
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        // Same placement as BoxFit.contain: scale to fit, centred.
        final s = px / side;
        canvas
          ..translate((px - info.size.width * s) / 2, (px - info.size.height * s) / 2)
          ..scale(s)
          ..drawPicture(info.picture);
        info.picture.dispose();
        final image = await rec.endRecording().toImage(px, px);
        _cache[key] = image;
        if (_cache.length > _maxCached) {
          // Widgets showing it hold their own clone, so this is safe.
          _cache.remove(_cache.keys.first)?.dispose();
        }
        return image;
      } catch (_) {
        return null; // keep showing the vector version
      } finally {
        _pending.remove(key);
      }
    });
  }

  @override
  State<MotifArt> createState() => _MotifArtState();
}

class _MotifArtState extends State<MotifArt> {
  ui.Image? _image; // our own clone; disposed with the widget
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensure();
  }

  @override
  void didUpdateWidget(MotifArt old) {
    super.didUpdateWidget(old);
    _ensure();
  }

  void _ensure() {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final px = MotifArt.bucket(widget.size, dpr);
    final key = '${widget.motif.file}|$px';
    if (key == _key) return;
    _key = key;
    final hit = MotifArt._cache[key];
    if (hit != null) {
      _swap(hit.clone()); // called just before build: no setState needed
      return;
    }
    MotifArt._render(widget.motif, px).then((_) {
      // Re-read the cache: the bitmap may already have been evicted.
      final ready = MotifArt._cache[key];
      if (!mounted || key != _key || ready == null) return;
      setState(() => _swap(ready.clone()));
    });
  }

  void _swap(ui.Image? next) {
    _image?.dispose();
    _image = next;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final image = _image;
    if (image == null) {
      return SvgPicture.asset(
        widget.motif.asset,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return ExcludeSemantics(
      child: RawImage(
        image: image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        color: color,
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}
