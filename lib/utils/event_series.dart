/// Rules for events with several dates (a *series*) and for where an event
/// happens, kept in one place so the Create event form (which writes the
/// rows) and every screen that reads them agree.
///
/// A series is not a special kind of event: each date is an ordinary
/// `events` row with its own check-in, joiners, cancel and registration
/// deadline, and `series_id` groups them (20261112003100_event_series.sql).
/// So "is this date cancelled / over / still open to join" is always the
/// same per-row rule from event_live.dart, never something worked out from
/// a repeat pattern.
library;

import 'event_live.dart';

/// Most dates one series may hold. The database enforces the same number
/// (EVENT:series_full).
const int kMaxSeriesDates = 26;

/// How far ahead a series may run from its first date.
const Duration kMaxSeriesSpan = Duration(days: 366);

// ---------------------------------------------------------------- timing

/// The three timing choices on the Create event form.
enum TimingMode { once, repeats, dates }

/// One date of a series as the form builds it.
class SessionSlot {
  final DateTime start;
  final DateTime end;

  /// Added by hand to a weekly pattern ("+ Add extra date").
  final bool extra;

  const SessionSlot(this.start, this.end, {this.extra = false});

  SessionSlot copyWith({DateTime? start, DateTime? end}) =>
      SessionSlot(start ?? this.start, end ?? this.end, extra: extra);

  bool get valid => end.isAfter(start);

  @override
  bool operator ==(Object other) =>
      other is SessionSlot && other.start == start && other.end == end && other.extra == extra;

  @override
  int get hashCode => Object.hash(start, end, extra);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

/// The days a weekly pattern lands on, from [first] to [until] (both
/// included), on [weekdays] (DateTime.monday … DateTime.sunday), every
/// [everyWeeks] weeks counted from the week [first] is in. Dates only;
/// [until] is clamped to [kMaxSeriesSpan] after [first].
List<DateTime> weeklyDates({
  required DateTime first,
  required DateTime until,
  required Set<int> weekdays,
  int everyWeeks = 1,
}) {
  if (weekdays.isEmpty || everyWeeks < 1) return const [];
  final start = dateOnly(first);
  var end = dateOnly(until);
  final cap = start.add(kMaxSeriesSpan);
  if (end.isAfter(cap)) end = cap;
  final weekZero = _mondayOf(start);
  final out = <DateTime>[];
  // Step by calendar day (not 24h) so a DST change never skips a date.
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    if (!weekdays.contains(d.weekday)) continue;
    final week = dateOnly(d).difference(weekZero).inDays ~/ 7;
    if (week % everyWeeks == 0) out.add(d);
  }
  return out;
}

/// [day] at [hour]:[minute].
DateTime atTime(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// The dates a weekly pattern publishes: the pattern's days at the chosen
/// times, minus [skipped] days, plus [extras], soonest first.
List<SessionSlot> weeklySessions({
  required List<DateTime> days,
  required int fromHour,
  required int fromMinute,
  required int toHour,
  required int toMinute,
  Set<DateTime> skipped = const {},
  List<SessionSlot> extras = const [],
}) {
  final out = <SessionSlot>[
    for (final d in days)
      if (!skipped.contains(dateOnly(d)))
        SessionSlot(atTime(d, fromHour, fromMinute), atTime(d, toHour, toMinute)),
    ...extras,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// What is wrong with a list of dates about to be published, if anything.
enum SessionsIssue { none, empty, tooMany, endBeforeStart, duplicate }

SessionsIssue checkSessions(List<SessionSlot> slots) {
  if (slots.isEmpty) return SessionsIssue.empty;
  if (slots.length > kMaxSeriesDates) return SessionsIssue.tooMany;
  if (slots.any((s) => !s.valid)) return SessionsIssue.endBeforeStart;
  final starts = slots.map((s) => s.start).toSet();
  if (starts.length != slots.length) return SessionsIssue.duplicate;
  return SessionsIssue.none;
}

/// Stored on `event_series.repeat_rule`, read back for the summary line.
Map<String, dynamic> repeatRule(TimingMode mode, {Set<int> weekdays = const {}, int everyWeeks = 1}) =>
    mode == TimingMode.repeats
        ? {'kind': 'weekly', 'every': everyWeeks, 'weekdays': (weekdays.toList()..sort())}
        : {'kind': 'dates'};

// -------------------------------------------------- registration deadline

/// When registration closes, as the form offers it.
enum CloseRule { atStart, setTime, never }

/// The `join_deadline` for one date starting at [start].
///
/// [setTime] is the exact moment for a one-off event; a series uses
/// [before] instead ("1 day before"), counted back from each date, so every
/// date closes the same way relative to its own start.
DateTime? deadlineFor(CloseRule rule, DateTime start, {DateTime? setTime, Duration? before}) {
  switch (rule) {
    case CloseRule.never:
      return null;
    case CloseRule.atStart:
      return start;
    case CloseRule.setTime:
      if (before != null) return start.subtract(before);
      return setTime ?? start;
  }
}

/// Reads a row's deadline back into the form's choice.
CloseRule closeRuleOf(Map<String, dynamic> event) {
  final deadline = DateTime.tryParse('${event['join_deadline'] ?? ''}');
  if (deadline == null) return CloseRule.never;
  final start = DateTime.tryParse('${event['start_datetime'] ?? ''}');
  if (start != null && deadline.isAtSameMomentAs(start)) return CloseRule.atStart;
  return CloseRule.setTime;
}

/// The deadline for another date of the same series when an edit is applied
/// to "this and later dates": the edited date's rule, moved to [otherStart].
/// Closing at the start stays at the start; "never" stays never; a set time
/// keeps the same gap before the start.
DateTime? shiftedDeadline({
  required DateTime editedStart,
  required DateTime? editedDeadline,
  required DateTime otherStart,
}) {
  if (editedDeadline == null) return null;
  return otherStart.subtract(editedStart.difference(editedDeadline));
}

/// The gaps the form offers for "closes … before each date".
const List<Duration> kCloseBeforeChoices = [
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(days: 1),
  Duration(days: 2),
  Duration(days: 7),
];

/// Has registration closed for this date? The single rule both the event
/// page's Join button and the form's preview use: cancelled, over, or past
/// its own deadline.
bool joinClosed(Map<String, dynamic> event, {DateTime? now}) {
  if (isEventCancelled(event)) return true;
  final at = (now ?? DateTime.now()).toUtc();
  final end = DateTime.tryParse('${event['end_datetime'] ?? event['start_datetime'] ?? ''}');
  if (end != null && end.toUtc().isBefore(at)) return true;
  final deadline = DateTime.tryParse('${event['join_deadline'] ?? ''}');
  return deadline != null && at.isAfter(deadline.toUtc());
}

// ------------------------------------------------------- reading a series

/// Where one date of a series stands, for the dates list on the event page.
enum SessionState { upcoming, ended, cancelled }

SessionState sessionStateOf(Map<String, dynamic> event, {DateTime? now}) {
  // Cancelled wins over ended: a cancelled date that has passed never happened.
  if (isEventCancelled(event)) return SessionState.cancelled;
  final at = (now ?? DateTime.now()).toUtc();
  final end = DateTime.tryParse('${event['end_datetime'] ?? event['start_datetime'] ?? ''}');
  if (end != null && end.toUtc().isBefore(at)) return SessionState.ended;
  return SessionState.upcoming;
}

DateTime _startOf(Map<String, dynamic> e) =>
    DateTime.tryParse('${e['start_datetime'] ?? ''}') ?? DateTime(1970);

/// The next date that will still happen (not cancelled, not over), or null.
Map<String, dynamic>? nextSession(Iterable<Map<String, dynamic>> sessions, {DateTime? now}) {
  final open = sessions.where((e) => sessionStateOf(e, now: now) == SessionState.upcoming).toList()
    ..sort((a, b) => _startOf(a).compareTo(_startOf(b)));
  return open.isEmpty ? null : open.first;
}

/// Key added by [collapseSeries]: how many other dates of the same series
/// are still to come.
const String kSeriesMoreKey = 'series_more';

/// Lists show one card per series, not one per date: the next date that
/// will still happen, or, when every date is over or cancelled, the latest
/// one. That card gets [kSeriesMoreKey] = the number of *other* dates still
/// to come, so "+3 more dates" never counts a cancelled or finished date.
/// Events without a series pass through untouched. The kept card sits where
/// the first date of its series was.
List<Map<String, dynamic>> collapseSeries(List<Map<String, dynamic>> events, {DateTime? now}) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final e in events) {
    final sid = e['series_id'];
    if (sid is String && sid.isNotEmpty) (groups[sid] ??= []).add(e);
  }
  if (groups.isEmpty) return events;

  final keep = <String, Map<String, dynamic>>{};
  groups.forEach((sid, group) {
    final next = nextSession(group, now: now);
    final pick = next ??
        (group.toList()..sort((a, b) => _startOf(b).compareTo(_startOf(a)))).first;
    final more = group
        .where((e) => !identical(e, pick) && sessionStateOf(e, now: now) == SessionState.upcoming)
        .length;
    keep[sid] = {...pick, kSeriesMoreKey: more};
  });

  final out = <Map<String, dynamic>>[];
  final placed = <String>{};
  for (final e in events) {
    final sid = e['series_id'];
    if (sid is String && sid.isNotEmpty) {
      if (placed.add(sid)) out.add(keep[sid]!);
    } else {
      out.add(e);
    }
  }
  return out;
}

// ---------------------------------------------------------------- where

/// In person, online or both. Stored as `events.location_mode`.
enum LocationMode {
  inPerson('in_person'),
  online('online'),
  hybrid('hybrid');

  final String db;
  const LocationMode(this.db);

  static LocationMode of(Object? value) =>
      values.firstWhere((m) => m.db == value, orElse: () => LocationMode.inPerson);

  /// Needs a venue (the location field).
  bool get hasPlace => this != LocationMode.online;

  /// Needs a meeting link.
  bool get hasLink => this != LocationMode.inPerson;
}

/// The meeting link a viewer may open: only for online / hybrid events
/// that are still on. A cancelled or finished date shows no link.
String? onlineLinkFor(Map<String, dynamic> event, {DateTime? now}) {
  if (!LocationMode.of(event['location_mode']).hasLink) return null;
  final url = '${event['online_url'] ?? ''}'.trim();
  if (url.isEmpty) return null;
  if (sessionStateOf(event, now: now) != SessionState.upcoming) return null;
  return url;
}
