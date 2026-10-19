import 'package:flutter/material.dart';
import '../theme/app_themes.dart';

/// "ENDED" / "SOLD" marker laid over a cover photo. One look everywhere:
/// the corner pill on cards and grid tiles, [StatusBadge.stamp] centred
/// over a detail-page hero.
///
/// Pass the sentence-case label (`s.ended`, `s.sold`); it's uppercased here.
class StatusBadge extends StatelessWidget {
  final String label;
  final bool _stamp;

  const StatusBadge(this.label, {super.key}) : _stamp = false;

  /// Large bordered variant for a full-bleed hero image.
  const StatusBadge.stamp(this.label, {super.key}) : _stamp = true;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: kOnPhoto,
            fontWeight: FontWeight.w700,
            letterSpacing: _stamp ? 3 : 1,
            fontSize: _stamp ? 20 : 11,
          ),
    );

    if (!_stamp) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: photoScrim(0.75),
          borderRadius: BorderRadius.circular(6),
        ),
        child: text,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: photoScrim(0.6),
        border: Border.all(color: kOnPhoto, width: 2),
      ),
      child: text,
    );
  }
}
