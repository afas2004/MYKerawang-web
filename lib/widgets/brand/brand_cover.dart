import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'app_motif.dart';
import 'k_pattern.dart';

/// The six colours a club (and later a profile) can wear. All are dark
/// enough for white text and marks on top (≥ 4.5:1), in every theme.
abstract final class KPalette {
  static const plum = Color(0xFF5E1A4F); // Ungu manggis
  static const jingga = Color(0xFFB4501A); // Jingga
  static const hijauPucuk = Color(0xFF1F6E5A); // Hijau pucuk
  static const biruLaut = Color(0xFF1E4E8C); // Biru laut
  static const merahSaga = Color(0xFFA3262E); // Merah saga
  static const kelabuArang = Color(0xFF3B3540); // Kelabu arang

  static const all = [plum, jingga, hijauPucuk, biruLaut, merahSaga, kelabuArang];

  /// A stable colour for [key] (a handle, an id), the same on every device.
  static Color forKey(String key) => all[stableHash(key) % all.length];

  /// [c] as a line or edge on the current theme: lifted on dark themes so a
  /// thin stroke of it still reads against near-black.
  static Color onTheme(Color c, Brightness b) =>
      b == Brightness.dark ? Color.lerp(c, Colors.white, 0.45)! : c;
}

/// FNV-1a: a small, stable string hash (Dart's `hashCode` differs per run).
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// A cover for clubs and profile banners without a photo: a solid colour
/// with a faint pattern generated from [seed] — motif, scale and angle all
/// follow from the seed, so no two clubs share one but each always looks the
/// same — plus an optional stitch [motif].
///
///   BrandCover(seed: club.handle, color: clubColor(club), motif: AppMotif.sape)
///
/// Fills its parent; everything is laid out inside the box (the motif is
/// sized from the box, never bigger), so nothing clips at any size.
class BrandCover extends StatelessWidget {
  final String seed;

  /// Defaults to [KPalette.forKey] of [seed].
  final Color? color;
  final AppMotif? motif;

  /// Optional content on top (e.g. a category icon).
  final Widget? child;

  const BrandCover({
    super.key,
    required this.seed,
    this.color,
    this.motif,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? KPalette.forKey(seed);
    final h = stableHash(seed);
    const angles = [0.0, 0.0, 45.0, 90.0];
    final mark = Colors.white.withValues(alpha: 0.86);
    return ExcludeSemantics(
      excluding: child == null,
      child: ClipRect(
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth.isFinite ? box.maxWidth : 320.0;
          final ht = box.maxHeight.isFinite ? box.maxHeight : 160.0;
          final motifSize = math.min(ht * 0.82, w * 0.42);
          return Stack(
            fit: StackFit.expand,
            children: [
              KPattern(
                kind: KPatternKind.values[h % KPatternKind.values.length],
                color: Colors.white.withValues(alpha: 0.14 + ((h >> 4) % 8) / 100),
                background: bg,
                cell: 26 + ((h >> 8) % 20).toDouble(),
                angle: angles[(h >> 12) % angles.length],
              ),
              if (motif != null && motifSize >= 24)
                Positioned(
                  right: math.min(KSpace.l, w * 0.05),
                  top: (ht - motifSize) / 2,
                  width: motifSize,
                  height: motifSize,
                  child: MotifArt(motif!, size: motifSize, color: mark),
                ),
              if (child != null) child!,
            ],
          );
        }),
      ),
    );
  }
}
