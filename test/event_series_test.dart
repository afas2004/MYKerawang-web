import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/event_series.dart';

Map<String, dynamic> ev(String id, DateTime start,
        {String? series, bool cancelled = false, DateTime? deadline, Duration length = const Duration(hours: 2)}) =>
    {
      'id': id,
      'series_id': series,
      'start_datetime': start.toUtc().toIso8601String(),
      'end_datetime': start.add(length).toUtc().toIso8601String(),
      if (cancelled) 'cancelled_at': '2026-11-01T00:00:00Z',
      if (deadline != null) 'join_deadline': deadline.toUtc().toIso8601String(),
    };

void main() {
  group('weeklyDates', () {
    // Thu 19 Nov 2026.
    final first = DateTime(2026, 11, 19);

    test('every Thursday until the end date, both ends included', () {
      final d = weeklyDates(first: first, until: DateTime(2026, 12, 17), weekdays: {DateTime.thursday});
      expect(d, [
        DateTime(2026, 11, 19),
        DateTime(2026, 11, 26),
        DateTime(2026, 12, 3),
        DateTime(2026, 12, 10),
        DateTime(2026, 12, 17),
      ]);
    });

    test('several weekdays, starting mid-week skips days before the first date', () {
      final d = weeklyDates(
          first: first, until: DateTime(2026, 11, 30), weekdays: {DateTime.monday, DateTime.thursday});
      expect(d, [DateTime(2026, 11, 19), DateTime(2026, 11, 23), DateTime(2026, 11, 26), DateTime(2026, 11, 30)]);
    });

    test('every 2 weeks counts from the first date\'s week', () {
      final d = weeklyDates(
          first: first, until: DateTime(2026, 12, 31), weekdays: {DateTime.thursday}, everyWeeks: 2);
      expect(d, [DateTime(2026, 11, 19), DateTime(2026, 12, 3), DateTime(2026, 12, 17), DateTime(2026, 12, 31)]);
    });

    test('no weekdays or an end before the start gives nothing', () {
      expect(weeklyDates(first: first, until: DateTime(2027), weekdays: {}), isEmpty);
      expect(weeklyDates(first: first, until: DateTime(2026, 11, 1), weekdays: {4}), isEmpty);
    });

    test('a far end date is clamped to a year', () {
      final d = weeklyDates(first: first, until: DateTime(2030), weekdays: {DateTime.thursday});
      expect(d.last.isAfter(first.add(kMaxSeriesSpan)), isFalse);
    });
  });

  group('weeklySessions', () {
    final days = [DateTime(2026, 11, 19), DateTime(2026, 11, 26), DateTime(2026, 12, 3)];

    test('applies the times, drops skipped days and sorts extras in', () {
      final extra = SessionSlot(DateTime(2026, 11, 28, 9), DateTime(2026, 11, 28, 12), extra: true);
      final s = weeklySessions(
        days: days,
        fromHour: 20,
        fromMinute: 30,
        toHour: 22,
        toMinute: 0,
        skipped: {DateTime(2026, 11, 26)},
        extras: [extra],
      );
      expect(s.map((x) => x.start), [
        DateTime(2026, 11, 19, 20, 30),
        DateTime(2026, 11, 28, 9),
        DateTime(2026, 12, 3, 20, 30),
      ]);
      expect(s[1].extra, isTrue);
      expect(s.first.end, DateTime(2026, 11, 19, 22));
    });
  });

  group('checkSessions', () {
    SessionSlot at(int day, [int hours = 2]) =>
        SessionSlot(DateTime(2026, 12, day, 20), DateTime(2026, 12, day, 20).add(Duration(hours: hours)));

    test('flags each problem', () {
      expect(checkSessions([]), SessionsIssue.empty);
      expect(checkSessions([at(1, -1)]), SessionsIssue.endBeforeStart);
      expect(checkSessions([at(1), at(1)]), SessionsIssue.duplicate);
      expect(checkSessions([for (var i = 1; i <= kMaxSeriesDates + 1; i++) at(1).copyWith(start: DateTime(2026, 1, i, 20), end: DateTime(2026, 1, i, 22))]),
          SessionsIssue.tooMany);
      expect(checkSessions([at(1), at(8)]), SessionsIssue.none);
    });
  });

  group('registration deadline', () {
    final start = DateTime(2026, 12, 3, 20, 30);

    test('the form choice becomes a deadline', () {
      expect(deadlineFor(CloseRule.never, start), isNull);
      expect(deadlineFor(CloseRule.atStart, start), start);
      final set = DateTime(2026, 12, 2, 23, 59);
      expect(deadlineFor(CloseRule.setTime, start, setTime: set), set);
      expect(deadlineFor(CloseRule.setTime, start, before: const Duration(days: 1)),
          DateTime(2026, 12, 2, 20, 30));
    });

    test('reading a row back gives the same choice (creator and viewer agree)', () {
      for (final rule in CloseRule.values) {
        final d = deadlineFor(rule, start, before: const Duration(hours: 3));
        final row = ev('a', start, deadline: d);
        expect(closeRuleOf(row), rule, reason: '$rule');
      }
    });

    test('"this and later dates" keeps each date\'s deadline relative to its own start', () {
      final other = DateTime(2026, 12, 10, 20, 30);
      expect(shiftedDeadline(editedStart: start, editedDeadline: start, otherStart: other), other);
      expect(shiftedDeadline(editedStart: start, editedDeadline: null, otherStart: other), isNull);
      expect(
          shiftedDeadline(
              editedStart: start, editedDeadline: start.subtract(const Duration(days: 1)), otherStart: other),
          other.subtract(const Duration(days: 1)));
    });

    test('joinClosed: cancelled, over, or past its own deadline', () {
      final now = DateTime(2026, 12, 3, 12);
      expect(joinClosed(ev('a', start), now: now), isFalse);
      expect(joinClosed(ev('a', start, cancelled: true), now: now), isTrue);
      expect(joinClosed(ev('a', DateTime(2026, 12, 1)), now: now), isTrue);
      expect(joinClosed(ev('a', start, deadline: DateTime(2026, 12, 3, 9)), now: now), isTrue);
      expect(joinClosed(ev('a', start, deadline: DateTime(2026, 12, 3, 13)), now: now), isFalse);
    });
  });

  group('series in lists', () {
    final now = DateTime(2026, 12, 1, 12);

    test('one card per series: the next date still on, counting only dates still to come', () {
      final events = [
        ev('solo', DateTime(2026, 12, 2)),
        ev('w1', DateTime(2026, 11, 26), series: 's'), // over
        ev('w2', DateTime(2026, 12, 3), series: 's', cancelled: true),
        ev('w3', DateTime(2026, 12, 10), series: 's'),
        ev('w4', DateTime(2026, 12, 17), series: 's'),
        ev('w5', DateTime(2026, 12, 24), series: 's'),
      ];
      final out = collapseSeries(events, now: now);
      expect(out.map((e) => e['id']), ['solo', 'w3']);
      expect(out[1][kSeriesMoreKey], 2);
      expect(out.first.containsKey(kSeriesMoreKey), isFalse);
    });

    test('a series with every date over or cancelled shows its latest date', () {
      final out = collapseSeries([
        ev('a', DateTime(2026, 11, 1), series: 's'),
        ev('b', DateTime(2026, 11, 8), series: 's', cancelled: true),
      ], now: now);
      expect(out.single['id'], 'b');
      expect(out.single[kSeriesMoreKey], 0);
    });

    test('no series: the list is returned as is', () {
      final list = [ev('a', now), ev('b', now)];
      expect(identical(collapseSeries(list, now: now), list), isTrue);
    });

    test('session states and next session agree with the cards', () {
      final s = [
        ev('a', DateTime(2026, 11, 1), series: 's'),
        ev('b', DateTime(2026, 12, 8), series: 's', cancelled: true),
        ev('c', DateTime(2026, 12, 15), series: 's'),
      ];
      expect(s.map((e) => sessionStateOf(e, now: now)),
          [SessionState.ended, SessionState.cancelled, SessionState.upcoming]);
      expect(nextSession(s, now: now)?['id'], 'c');
    });
  });

  group('where', () {
    test('modes map to the database and back', () {
      for (final m in LocationMode.values) {
        expect(LocationMode.of(m.db), m);
      }
      expect(LocationMode.of(null), LocationMode.inPerson);
      expect(LocationMode.online.hasPlace, isFalse);
      expect(LocationMode.hybrid.hasPlace && LocationMode.hybrid.hasLink, isTrue);
    });

    test('the meeting link shows only while the date is still on', () {
      final now = DateTime(2026, 12, 1, 12);
      Map<String, dynamic> online(DateTime start, {bool cancelled = false, String mode = 'online'}) => {
            ...ev('x', start, cancelled: cancelled),
            'location_mode': mode,
            'online_url': 'https://meet.google.com/abc',
          };
      expect(onlineLinkFor(online(DateTime(2026, 12, 2)), now: now), 'https://meet.google.com/abc');
      expect(onlineLinkFor(online(DateTime(2026, 12, 2), cancelled: true), now: now), isNull);
      expect(onlineLinkFor(online(DateTime(2026, 11, 2)), now: now), isNull);
      expect(onlineLinkFor(online(DateTime(2026, 12, 2), mode: 'in_person'), now: now), isNull);
    });
  });

  test('repeat rule matches the database\'s accepted shape', () {
    expect(repeatRule(TimingMode.repeats, weekdays: {4, 1}, everyWeeks: 2),
        {'kind': 'weekly', 'every': 2, 'weekdays': [1, 4]});
    expect(repeatRule(TimingMode.dates), {'kind': 'dates'});
  });
}
