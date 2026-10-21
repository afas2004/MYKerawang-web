import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/screens/events_screen.dart';
import 'package:mykerawang/utils/ics.dart';

void main() {
  group('buildEventIcs', () {
    final event = {
      'id': 'abc-123',
      'title': 'Campus Run, 5km; open to all',
      'location': 'Dataran, UiTM',
      'description': 'Line one\nLine two',
      // 8pm Malaysia time (UTC+8) is 12:00 UTC
      'start_datetime': '2026-10-20T20:00:00+08:00',
      'end_datetime': '2026-10-20T12:00:00Z',
    };

    final ics = buildEventIcs(event,
        url: 'https://mykerawang-app.web.app/event/abc-123',
        now: DateTime.utc(2026, 10, 19, 1, 2, 3));

    test('encodes times as UTC', () {
      expect(ics, contains('DTSTART:20261020T120000Z\r\n'));
      expect(ics, contains('DTEND:20261020T120000Z\r\n'));
      expect(ics, contains('DTSTAMP:20261019T010203Z\r\n'));
    });

    test('escapes text and uses CRLF', () {
      expect(ics, contains(r'SUMMARY:Campus Run\, 5km\; open to all'));
      expect(ics, contains(r'LOCATION:Dataran\, UiTM'));
      expect(ics.startsWith('BEGIN:VCALENDAR\r\n'), isTrue);
      expect(ics.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(ics.replaceAll('\r\n', '').contains('\n'), isFalse);
    });

    test('folds long lines at 75 octets', () {
      for (final line in ics.split('\r\n')) {
        expect(line.length, lessThanOrEqualTo(75));
      }
    });

    test('defaults end to start + 2h and marks cancellation', () {
      final out = buildEventIcs({
        'id': 'x',
        'title': 'T',
        'start_datetime': '2026-10-20T01:00:00Z',
        'cancelled_at': '2026-10-19T00:00:00Z',
      });
      expect(out, contains('DTEND:20261020T030000Z'));
      expect(out, contains('STATUS:CANCELLED'));
    });
  });

  test('icsFileName slugs the title', () {
    expect(icsFileName('Campus Run 2026!'), 'campus-run-2026.ics');
    expect(icsFileName(null), 'event.ics');
  });

  group('eventCountdown', () {
    const s = AppStrings.en;
    // Relative to the real clock: isEventEnded (inside eventCountdown)
    // compares against DateTime.now(), so the events must be in the future.
    final day = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    final now = day.add(const Duration(hours: 9));
    String? at(DateTime start) =>
        eventCountdown(s, {'start_datetime': start.toUtc().toIso8601String()}, now: now);

    test('today / tomorrow / in N days / none', () {
      expect(at(day.add(const Duration(hours: 23))), 'Today');
      expect(at(day.add(const Duration(days: 1, hours: 1))), 'Tomorrow');
      expect(at(day.add(const Duration(days: 3, hours: 9))), 'In 3 days');
      expect(at(day.add(const Duration(days: 7, hours: 9))), isNull);
    });

    test('cancelled events get no countdown', () {
      expect(
          eventCountdown(s, {
            'start_datetime': day.add(const Duration(days: 1)).toUtc().toIso8601String(),
            'cancelled_at': '2026-10-19T00:00:00Z',
          }, now: now),
          isNull);
    });
  });
}
