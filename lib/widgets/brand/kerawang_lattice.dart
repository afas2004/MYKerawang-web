import 'package:flutter/material.dart';

/// Where a lattice was used. Kept for API compatibility only.
enum LatticeVariant { band, corner, field }

/// **Deprecated — renders nothing.** The kerawang lattice motif was
/// retired in the modern redesign (the user found it decorative noise).
/// The class and its constructors remain so existing call sites compile;
/// remove usages when you next touch a screen.
class KerawangLattice extends StatelessWidget {
  final LatticeVariant variant;
  final double tileSize;
  final Color? color;
  final double? opacity;
  final Alignment corner;
  final double extent;
  final double strokeWidth;

  const KerawangLattice({
    super.key,
    this.tileSize = 18,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  })  : variant = LatticeVariant.field,
        corner = Alignment.topLeft,
        extent = 0;

  const KerawangLattice.band({
    super.key,
    this.tileSize = 10,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  })  : variant = LatticeVariant.band,
        corner = Alignment.topLeft,
        extent = 0;

  const KerawangLattice.corner({
    super.key,
    this.corner = Alignment.topRight,
    this.extent = 40,
    this.tileSize = 10,
    this.color,
    this.opacity,
    this.strokeWidth = 1,
  }) : variant = LatticeVariant.corner;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
