import 'package:flutter/material.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../theme/app_themes.dart';
import '../utils/event_live.dart';
import '../utils/listing_status.dart';

/// Badge text for an event or listing row; null while it is live.
String? statusLabelFor(Map<String, dynamic> data, AppStrings s,
        {required bool isEvent}) =>
    isEvent ? eventBadge(data, s) : ListingStatus.of(data).badge(s);

/// [statusLabelFor], plus "Check-in open" while an event's door is open: what
/// the feed's cards show on their photo.
String? cardLabelFor(Map<String, dynamic> data, AppStrings s,
        {required bool isEvent}) =>
    statusLabelFor(data, s, isEvent: isEvent) ??
    (isEvent && checkinOpen(data) ? s.evCheckinOpen : null);

/// [photo] with [label] in its top corner; [photo] itself when there is no
/// label. The parent must give the photo a fixed size.
Widget photoWithStatus(Widget photo, String? label) => label == null
    ? photo
    : Stack(
        fit: StackFit.expand,
        children: [
          photo,
          Positioned(
              top: KSpace.s, left: KSpace.s, child: StatusBadge(label)),
        ],
      );

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
