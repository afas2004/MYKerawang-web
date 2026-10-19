import 'package:flutter/material.dart';

/// **Deprecated look.** The lattice strip was retired in the modern
/// redesign. [LatticeBand] now renders nothing; [LatticeBand.preferred]
/// (used as `AppBar.bottom`) renders a plain 1px divider so app bars keep a
/// clean separation from scrolling content. Parameters are kept for API
/// compatibility and ignored.
class LatticeBand extends StatelessWidget {
  final double height;
  final bool hairline;
  final Color? color;

  const LatticeBand({
    super.key,
    this.height = 8,
    this.hairline = true,
    this.color,
  });

  /// For `AppBar.bottom`: a 1px divider in the theme's border colour.
  static PreferredSizeWidget preferred({
    double height = 8,
    bool hairline = true,
    Color? color,
  }) =>
      const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1),
      );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
