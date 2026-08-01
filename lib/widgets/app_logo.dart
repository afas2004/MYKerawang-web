import 'package:flutter/material.dart';

/// The MYKerawang mark. The source artwork is landscape with the "K"
/// centred, so a centre-cropped circle yields the icon cleanly without
/// needing a separate export.
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
          'assets/MyKerawang.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
