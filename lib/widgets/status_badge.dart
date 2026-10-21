import 'package:flutter/material.dart';
import '../theme/app_themes.dart';

/// "Ended" / "Sold" / "Reserved" / "Cancelled" marker laid over a photo:
/// a dark pill, so it reads on any image. [StatusBadge.stamp] is the
/// larger version centred over a detail-page hero.
///
/// Pass the sentence-case label (`s.ended`, `s.sold`).
class StatusBadge extends StatelessWidget {
  final String label;
  final bool _stamp;

  const StatusBadge(this.label, {super.key}) : _stamp = false;

  /// Larger pill for a full-bleed hero image.
  const StatusBadge.stamp(this.label, {super.key}) : _stamp = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: _stamp
          ? const EdgeInsets.symmetric(horizontal: KSpace.l, vertical: KSpace.s)
          : const EdgeInsets.symmetric(horizontal: KSpace.s + 2, vertical: KSpace.xs),
      decoration: BoxDecoration(
        color: photoScrim(_stamp ? 0.65 : 0.7),
        borderRadius: KRadius.pill,
      ),
      child: Text(
        label,
        style: (_stamp ? theme.textTheme.titleSmall : theme.textTheme.labelSmall)
            ?.copyWith(color: kOnPhoto, fontWeight: FontWeight.w600),
      ),
    );
  }
}
