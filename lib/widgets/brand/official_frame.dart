import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'kerawang_lattice.dart';

/// Marks official / pinned / verified content: a gold hairline in the
/// kerawang cut plus a small lattice ornament in one corner.
///
/// Gold means "special" (rule 3), so use this only for content that is
/// genuinely official or pinned. Keep the ornament's corner free of text —
/// give the child at least [cornerExtent] of padding on that corner, or put
/// it where an image or whitespace sits.
///
///   OfficialFrame(child: PostCard(...))
///   OfficialFrame(enabled: post['is_pinned'] == true, child: ...)
class OfficialFrame extends StatelessWidget {
  final Widget child;

  /// When false the child is returned untouched (saves call-site ternaries).
  final bool enabled;

  final BorderRadius borderRadius;
  final Alignment corner;
  final double cornerExtent;

  /// Read by screen readers, e.g. "Pinned" or "Official".
  final String? semanticLabel;

  const OfficialFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = KRadius.cut,
    this.corner = Alignment.topRight,
    this.cornerExtent = 36,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final k = KTokens.of(context);

    final framed = Stack(
      children: [
        ClipRRect(borderRadius: borderRadius, child: child),
        Positioned(
          top: corner.y < 0 ? 0 : null,
          bottom: corner.y > 0 ? 0 : null,
          left: corner.x < 0 ? 0 : null,
          right: corner.x > 0 ? 0 : null,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: KerawangLattice.corner(
              corner: corner,
              extent: cornerExtent,
              tileSize: cornerExtent / 4,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: k.gold, width: 1),
              ),
            ),
          ),
        ),
      ],
    );

    if (semanticLabel == null) return framed;
    return Semantics(label: semanticLabel, container: true, child: framed);
  }
}
