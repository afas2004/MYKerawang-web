/// When an event's door is open, as a pure rule so the event page, the list and
/// the tests agree on it.
///
/// "Open" is deliberately generous: from 15 minutes before the start until the
/// end. Students queue and scan early, and a code that is refused at 8:55 for a
/// 9:00 event is a queue, not a security feature. The rotating token is what
/// makes the code short-lived; this only decides whether the UI offers it.
library;

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';

/// The check-in window: 15 minutes before the start until the end.
const Duration kCheckinOpensBefore = Duration(minutes: 15);

/// True when [event] has attendance on and its window contains [now].
///
/// Undated, cancelled or attendance-less events are never open.
bool checkinOpen(Map<String, dynamic> event, {DateTime? now}) {
  if (event['attendance_enabled'] != true) return false;
  if (event['cancelled_at'] != null) return false;

  final start = DateTime.tryParse('${event['start_datetime'] ?? ''}');
  if (start == null) return false;
  final end = DateTime.tryParse('${event['end_datetime'] ?? ''}') ??
      start.add(const Duration(hours: 3));

  final at = now ?? DateTime.now();
  return at.isAfter(start.subtract(kCheckinOpensBefore)) && at.isBefore(end);
}

/// Has this event finished? Ended events stay visible (greyed out) —
/// history is content (DESIGN_SPEC §6).
bool isEventEnded(Map<String, dynamic> event) {
  final raw = event['end_datetime'] ?? event['start_datetime'];
  final end = DateTime.tryParse(raw ?? '');
  if (end == null) return false;
  return end.toUtc().isBefore(DateTime.now().toUtc());
}

/// Cancelled by the organiser (events.cancelled_at, see
/// 20261019002200_event_soft_cancel.sql).
bool isEventCancelled(Map<String, dynamic> event) => event['cancelled_at'] != null;

/// Ended or cancelled: either way it's history, greyed and sorted last.
bool isEventClosed(Map<String, dynamic> event) =>
    isEventEnded(event) || isEventCancelled(event);

/// Badge text for a closed event; none while it is still on. Cancelled wins
/// over ended: a cancelled event whose date has passed never happened.
String? eventBadge(Map<String, dynamic> event, AppStrings s) {
  if (isEventCancelled(event)) return s.cancelled;
  return isEventEnded(event) ? s.ended : null;
}

/// Browse order: upcoming (soonest first), then ended or cancelled (most
/// recent first).
int compareForBrowse(Map<String, dynamic> a, Map<String, dynamic> b) {
  DateTime start(Map<String, dynamic> e) =>
      DateTime.tryParse(e['start_datetime'] ?? '') ?? DateTime(1970);
  final aClosed = isEventClosed(a);
  final bClosed = isEventClosed(b);
  if (aClosed != bClosed) return aClosed ? 1 : -1;
  return aClosed ? start(b).compareTo(start(a)) : start(a).compareTo(start(b));
}

/// True when [event] is happening right now (start <= now < end). Used for the
/// "live" chip, which is about the event, not the door.
bool eventIsLive(Map<String, dynamic> event, {DateTime? now}) {
  if (event['cancelled_at'] != null) return false;
  final start = DateTime.tryParse('${event['start_datetime'] ?? ''}');
  if (start == null) return false;
  final end = DateTime.tryParse('${event['end_datetime'] ?? ''}') ??
      start.add(const Duration(hours: 3));
  final at = now ?? DateTime.now();
  return !at.isBefore(start) && at.isBefore(end);
}
