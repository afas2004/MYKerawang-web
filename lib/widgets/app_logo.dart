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
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        // The artwork has generous margins; zoom so the K fills the tile.
        scale: 1.75,
        child: Image.asset(
          'assets/logo_mark.jpg',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
