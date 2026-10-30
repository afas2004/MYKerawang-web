import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/access_strings.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/utils/event_live.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/widgets/universal_card.dart';

import 'helpers/feed_fixtures.dart';

void main() {
  String iso(Duration d) => DateTime.now().add(d).toIso8601String();
  const past = Duration(days: -3);
  const later = Duration(days: 3);

  group('rules', () {
    Map<String, dynamic> event({Duration? start, String? cancelled}) => {
          'start_datetime': iso(start ?? later),
          'end_datetime': iso((start ?? later) + const Duration(hours: 2)),
          'cancelled_at': cancelled,
        };

    test('cancelled wins over ended', () {
      final s = AppStrings.en;
      final e = event(start: past, cancelled: iso(past));
      expect(eventBadge(e, s), s.cancelled);
      expect(isEventClosed(e), isTrue);
    });

    test('ended and upcoming', () {
      final s = AppStrings.en;
      expect(eventBadge(event(start: past), s), s.ended);
      expect(eventBadge(event(), s), isNull);
    });

    test('browse order: upcoming soonest first, then closed newest first', () {
      final soon = event(start: const Duration(days: 1));
      final next = event(start: later);
      final ended = event(start: const Duration(days: -1));
      final cancelled = event(start: later, cancelled: iso(past));
      final old = event(start: past);
      final rows = [old, cancelled, next, ended, soon]..sort(compareForBrowse);
      expect(rows, [soon, next, cancelled, ended, old]);
    });
  });

  group('render', () {
    Widget strip(Map<String, dynamic> data) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              height: 196,
              child: UniversalCard(data: data, onTap: () {}),
            ),
          ),
        );

    for (final size in [kCompact, kExpanded]) {
      testWidgets('cancelled event in a strip at ${size.width}', (t) async {
        await pumpAt(t, size, strip(sampleEvent('a', cancelledAt: iso(past))));
        expect(find.text('Cancelled'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('plain event and listing carry no badge', (t) async {
      await pumpAt(t, kCompact, strip(sampleEvent('a')));
      expect(find.text('Cancelled'), findsNothing);
      expect(find.text('Ended'), findsNothing);
      await pumpAt(t, kCompact, strip(sampleListing('b')));
      expect(find.text('Reserved'), findsNothing);
    });

    testWidgets('an event with its door open says so', (t) async {
      final e = {
        ...sampleEvent('a'),
        'attendance_enabled': true,
        'start_datetime': iso(const Duration(minutes: -5)),
        'end_datetime': iso(const Duration(hours: 1)),
      };
      await pumpAt(t, kCompact, strip(e));
      expect(find.text(AppStrings.en.evCheckinOpen), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('reserved listing is marked', (t) async {
      await pumpAt(t, kCompact, strip(sampleListing('b', status: 'reserved')));
      expect(find.text('Reserved'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a shared cancelled event is marked in its post', (t) async {
      await pumpAt(
        t,
        kCompact,
        Scaffold(
          body: SingleChildScrollView(
            child: SharedItemHero(
              data: sampleEvent('a', cancelledAt: iso(past)),
              isEvent: true,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Cancelled'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
