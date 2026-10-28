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
class MotifArt extends StatelessWidget {
  final AppMotif motif;
  final double size;
  final Color? color;

  const MotifArt(this.motif, {super.key, this.size = 96, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      motif.asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      colorFilter: ColorFilter.mode(
          color ?? Theme.of(context).colorScheme.primary, BlendMode.srcIn),
    );
  }
}
