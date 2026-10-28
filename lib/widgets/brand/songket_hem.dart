import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A strip of Malay songket (the CC0 "Perseri" pattern), tiled
/// horizontally like the hem of a kain.
///
/// Songket lives on the **edges** of a screen or a container — the top or
/// bottom of a cover, the top of an official card, under an app bar — never
/// across the middle of content and never as a background texture.
///
///   const SongketHem(height: 8)
///   SongketHem(height: 10, color: Colors.white.withValues(alpha: 0.85))
///
/// Always fills the width it is given and clips the last tile, so it can't
/// overflow at any screen size. Decorative: hidden from screen readers.
class SongketHem extends StatelessWidget {
  final double height;

  /// Defaults to the theme's primary (plum).
  final Color? color;

  const SongketHem({super.key, this.height = 8, this.color});

  static const asset = 'assets/brand/songket_perseri.svg';

  /// The pattern's own width / height (viewBox 92 × 50).
  static const double _aspect = 92 / 50;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final tileWidth = height * _aspect;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth.isFinite ? box.maxWidth : tileWidth * 6;
          final count = (width / tileWidth).ceil();
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < count; i++)
                    SvgPicture.asset(
                      asset,
                      width: tileWidth,
                      height: height,
                      fit: BoxFit.fill,
                      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
