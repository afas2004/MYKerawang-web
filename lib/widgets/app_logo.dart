import 'package:flutter/material.dart';

/// The MYKerawang mark. `logo_mark.jpg` is a small square centre crop of
/// the landscape source art (`assets/MyKerawang.png`, 1 MB — not bundled),
/// so a centre-cropped circle yields the icon cleanly.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Transform.scale(
        // The artwork has generous margins; zoom so the mark fills the circle.
        scale: 1.9,
        child: Image.asset(
          'assets/logo_mark.jpg',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
