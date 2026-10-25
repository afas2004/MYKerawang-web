import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/event_live.dart';

/// The check-in window and the "live" chip.
void main() {
  final start = DateTime(2026, 10, 25, 9);
  final end = DateTime(2026, 10, 25, 12);

  Map<String, dynamic> event({
    bool attendance = true,
    DateTime? startsAt,
    DateTime? endsAt,
    String? cancelledAt,
  }) =>
      {
        'attendance_enabled': attendance,
        'start_datetime': (startsAt ?? start).toIso8601String(),
        'end_datetime': (endsAt ?? end).toIso8601String(),
        'cancelled_at': cancelledAt,
      };

  group('check-in window', () {
    test('opens fifteen minutes before the start', () {
      expect(checkinOpen(event(), now: start.subtract(const Duration(minutes: 16))),
          isFalse);
      expect(checkinOpen(event(), now: start.subtract(const Duration(minutes: 10))),
          isTrue);
    });

    test('stays open through the event and closes at the end', () {
      expect(checkinOpen(event(), now: start.add(const Duration(hours: 1))), isTrue);
      expect(checkinOpen(event(), now: end), isFalse);
      expect(checkinOpen(event(), now: end.add(const Duration(minutes: 1))), isFalse);
    });

    test('attendance off, cancelled, or undated → never open', () {
      expect(checkinOpen(event(attendance: false), now: start), isFalse);
      expect(checkinOpen(event(cancelledAt: '2026-10-20'), now: start), isFalse);
      expect(checkinOpen({'attendance_enabled': true}, now: start), isFalse);
    });

    test('an event without an end still gets a window', () {
      final e = event()..remove('end_datetime');
      expect(checkinOpen(e, now: start.add(const Duration(hours: 2))), isTrue);
      expect(checkinOpen(e, now: start.add(const Duration(hours: 4))), isFalse);
    });
  });

  group('live chip', () {
    test('live only between start and end', () {
      expect(eventIsLive(event(), now: start.subtract(const Duration(minutes: 5))),
          isFalse);
      expect(eventIsLive(event(), now: start), isTrue);
      expect(eventIsLive(event(), now: end.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(eventIsLive(event(), now: end), isFalse);
    });

    test('a cancelled event is not live', () {
      expect(eventIsLive(event(cancelledAt: '2026-10-20'), now: start), isFalse);
    });
  });
}
