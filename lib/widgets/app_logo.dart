import 'package:flutter/material.dart';

/// The MYKerawang mark. `logo_mark.jpg` is a small square centre crop of
/// the landscape source art (`assets/MyKerawang.png`, 1 MB — not bundled),
/// shown in a rounded tile like the app icon.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // A rounded tile, like the app icon, rather than a circle.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        // The artwork's own white tile spans ~53 % of the crop; zoom past its
        // soft edge so only the inside shows and our tile is the only tile.
        scale: 1.95,
        child: Image.asset(
          'assets/logo_mark.jpg',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
