/// When an event's door is open, as a pure rule so the event page, the list and
/// the tests agree on it.
///
/// "Open" is deliberately generous: from 15 minutes before the start until the
/// end. Students queue and scan early, and a code that is refused at 8:55 for a
/// 9:00 event is a queue, not a security feature. The rotating token is what
/// makes the code short-lived; this only decides whether the UI offers it.
library;

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
