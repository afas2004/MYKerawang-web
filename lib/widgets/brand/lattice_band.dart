import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'kerawang_lattice.dart';

/// The thin lattice strip that tops headers, app bars and the sidebar,
/// with an optional gold hairline underneath. Purely decorative.
///
///   Column(children: [const LatticeBand(), AppBar(...)])
///   AppBar(bottom: LatticeBand.preferred())
class LatticeBand extends StatelessWidget {
  /// Tile height of the lattice row.
  final double height;

  /// Draw a gold hairline under the lattice.
  final bool hairline;

  /// Defaults to [KTokens.motif].
  final Color? color;

  const LatticeBand({
    super.key,
    this.height = 8,
    this.hairline = true,
    this.color,
  });

  /// For `AppBar.bottom` and other PreferredSizeWidget slots.
  static PreferredSizeWidget preferred({
    double height = 8,
    bool hairline = true,
    Color? color,
  }) =>
      PreferredSize(
        preferredSize: Size.fromHeight(height + (hairline ? 1 : 0)),
        child: LatticeBand(height: height, hairline: hairline, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final k = KTokens.of(context);
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KerawangLattice.band(tileSize: height, color: color),
          if (hairline)
            Container(
              height: 1,
              color: (color ?? k.gold).withValues(alpha: k.motifBandOpacity * 0.6),
            ),
        ],
      ),
    );
  }
}
