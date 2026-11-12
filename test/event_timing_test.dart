import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/event_timing_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/events_screen.dart' show EventCard;
import 'package:mykerawang/utils/event_series.dart';
import 'package:mykerawang/widgets/event_timing_editor.dart';

import 'helpers/feed_fixtures.dart' show kCompact, kExpanded, pumpAt;

/// A Thursday evening, far enough ahead that nothing has ended.
final _start = DateTime(2027, 3, 4, 20, 30);
final _end = DateTime(2027, 3, 4, 22);

Future<void> _pump(WidgetTester t, Widget child, {Size size = kCompact}) =>
    pumpAt(t, size, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)));

String _text(WidgetTester t, String key) => (t.widget(find.byKey(ValueKey(key))) as Text).data!;

void main() {
  const s = AppStrings.en;

  group('timing editor', () {
    testWidgets('starts as Once with the given start and end', (t) async {
      final c = EventTimingController(start: _start, end: _end);
      await _pump(t, EventTimingEditor(controller: c));
      expect(find.byKey(const ValueKey('once-start')), findsOneWidget);
      expect(c.sessions, [SessionSlot(_start, _end)]);
      expect(c.isSeries, isFalse);
    });

    testWidgets('Repeats: weekly Thursdays for 8 weeks, then skip one and undo', (t) async {
      final c = EventTimingController(start: _start, end: _end);
      await _pump(t, EventTimingEditor(controller: c));
      await t.tap(find.text(s.tmRepeats));
      await t.pumpAndSettle();

      // First date + 8 weeks, both ends included: 9 Thursdays.
      expect(c.mode, TimingMode.repeats);
      expect(c.sessions.length, 9);
      expect(_text(t, 'repeat-count'), s.tmSessions(9));
      expect(c.sessions.every((x) => x.start.weekday == DateTime.thursday), isTrue);
      expect(c.sessions.first.start, _start);

      // Add Monday.
      await t.tap(find.byKey(const ValueKey('weekday-${DateTime.monday}')));
      await t.pumpAndSettle();
      expect(c.sessions.length, 17);

      // Skip the second date; it stays listed so it can come back.
      final second = c.sessions[1].start;
      final row = find.byKey(ValueKey('repeat-row-${dateOnly(second).toIso8601String()}'));
      await t.ensureVisible(row);
      await t.tap(find.descendant(of: row, matching: find.byTooltip(s.tmSkip)));
      await t.pumpAndSettle();
      expect(c.sessions.length, 16);
      expect(c.sessions.any((x) => x.start == second), isFalse);
      expect(find.descendant(of: row, matching: find.text(s.tmUndoSkip)), findsOneWidget);

      await t.tap(find.descendant(of: row, matching: find.text(s.tmUndoSkip)));
      await t.pumpAndSettle();
      expect(c.sessions.length, 17);
    });

    testWidgets('Repeats: every 2 weeks halves the dates', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.repeats;
      await _pump(t, EventTimingEditor(controller: c));
      await t.tap(find.byTooltip(s.tmMoreWeeks));
      await t.pumpAndSettle();
      expect(_text(t, 'repeat-every'), s.tmWeeks(2));
      expect(c.sessions.length, 5);
    });

    testWidgets('Repeats with no weekday shows the problem once publishing was tried', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.repeats;
      await _pump(t, EventTimingEditor(controller: c, showErrors: true));
      await t.tap(find.byKey(const ValueKey('weekday-${DateTime.thursday}')));
      await t.pumpAndSettle();
      expect(c.issue, SessionsIssue.empty);
      expect(find.text(s.tmNeedWeekday), findsOneWidget);
      expect(find.byKey(const ValueKey('timing-error')), findsOneWidget);
    });

    testWidgets('Pick dates: uneven dates each keep their own time', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.dates;
      c.addPicked(SessionSlot(DateTime(2027, 3, 13, 9), DateTime(2027, 3, 13, 12)));
      c.addPicked(SessionSlot(DateTime(2027, 3, 8, 21), DateTime(2027, 3, 8, 22, 30)));
      await _pump(t, EventTimingEditor(controller: c));

      expect(_text(t, 'picked-count'), s.tmDatesOf(3, kMaxSeriesDates));
      expect(find.byKey(const ValueKey('picked-add')), findsOneWidget);
      // Sorted soonest first, times untouched.
      expect(c.sessions.map((x) => x.start),
          [_start, DateTime(2027, 3, 8, 21), DateTime(2027, 3, 13, 9)]);
      expect(c.sessions[2].end, DateTime(2027, 3, 13, 12));
      expect(c.issue, SessionsIssue.none);

      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('picked-row-1')), matching: find.byTooltip(s.tmRemoveDate)));
      await t.pumpAndSettle();
      expect(c.sessions.length, 2);
    });

    testWidgets('the last date cannot be removed', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.dates;
      await _pump(t, EventTimingEditor(controller: c));
      final remove = t.widget<IconButton>(find.descendant(
          of: find.byKey(const ValueKey('picked-row-0')), matching: find.byType(IconButton)));
      expect(remove.onPressed, isNull);
    });

    testWidgets('a date of a published series can only change its own time', (t) async {
      final c = EventTimingController(start: _start, end: _end, locked: true);
      await _pump(t, EventTimingEditor(controller: c));
      expect(find.byKey(const ValueKey('timing-mode')), findsNothing);
      c.mode = TimingMode.repeats;
      expect(c.mode, TimingMode.once);
    });

    testWidgets('no overflow on a phone or desktop in any mode', (t) async {
      for (final size in [kCompact, kExpanded]) {
        for (final mode in TimingMode.values) {
          final c = EventTimingController(start: _start, end: _end)..mode = mode;
          await _pump(t, Column(children: [
            EventTimingEditor(controller: c, showErrors: true),
            RegistrationCloseField(controller: c),
          ]), size: size);
          expect(t.takeException(), isNull, reason: '$mode at $size');
        }
      }
    });
  });

  group('registration closes', () {
    testWidgets('one event: a set time after the start is flagged', (t) async {
      final c = EventTimingController(start: _start, end: _end);
      await _pump(t, RegistrationCloseField(controller: c));
      await t.tap(find.text(s.rcSetTime));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-at')), findsOneWidget);
      expect(c.deadlineAt(_start), _start.subtract(const Duration(hours: 1)));

      c.setCloseAt(_start.add(const Duration(hours: 1)));
      await t.pumpAndSettle();
      expect(c.closeAfterStart, isTrue);
      expect(find.text(s.rcAfterStart), findsOneWidget);
    });

    testWidgets('a series: the set time is a gap before each date', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.repeats;
      await _pump(t, RegistrationCloseField(controller: c));
      await t.tap(find.text(s.rcSetTime));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-before')), findsOneWidget);
      expect(find.text(s.rcHintSeriesSet), findsOneWidget);

      // Every date closes one day before its own start, and reading any
      // published row back gives the same choice the viewer's page uses.
      for (final slot in c.sessions) {
        final d = c.deadlineAt(slot.start)!;
        expect(slot.start.difference(d), const Duration(days: 1));
        final row = {
          'start_datetime': slot.start.toUtc().toIso8601String(),
          'join_deadline': d.toUtc().toIso8601String(),
        };
        expect(closeRuleOf(row), CloseRule.setTime);
      }
    });

    testWidgets('when it starts / never become the row\'s deadline', (t) async {
      final c = EventTimingController(start: _start, end: _end)..mode = TimingMode.repeats;
      await _pump(t, RegistrationCloseField(controller: c));
      for (final slot in c.sessions) {
        expect(c.deadlineAt(slot.start), slot.start);
      }
      await t.tap(find.text(s.rcNever));
      await t.pumpAndSettle();
      expect(c.deadlineAt(_start), isNull);
      expect(find.text(s.rcHintNever), findsOneWidget);
    });
  });

  group('viewer side', () {
    test('place line for each location mode', () {
      expect(s.placeOf({'location': 'Dewan Kerawang'}), 'Dewan Kerawang');
      expect(s.placeOf({'location': ''}), s.locationTba);
      expect(s.placeOf({'location': '', 'location_mode': 'online'}), s.onlineEvent);
      expect(s.placeOf({'location': 'Dewan', 'location_mode': 'hybrid'}), 'Dewan · ${s.lmOnline}');
    });

    test('series summary in three languages', () {
      final rule = {'kind': 'weekly', 'every': 1, 'weekdays': [1, 4]};
      expect(AppStrings.en.seriesSummary(rule), 'Every Mon, Thu');
      expect(AppStrings.ms.seriesSummary(rule), 'Setiap Isn, Kha');
      expect(AppStrings.ja.seriesSummary(rule), '毎週月, 木');
      expect(AppStrings.en.seriesSummary({'kind': 'weekly', 'every': 2, 'weekdays': [5]}),
          'Every 2 weeks on Fri');
      expect(AppStrings.en.seriesSummary({'kind': 'dates'}), s.seriesSelected);
      expect(AppStrings.en.seriesSummary(null), s.seriesSelected);
    });

    for (final size in [kCompact, kExpanded]) {
      testWidgets('event card shows "+N more dates" and Online at ${size.width}', (t) async {
        final card = collapseSeries([
          for (var i = 0; i < 4; i++)
            {
              'id': 'w$i',
              'series_id': 's',
              'title': 'Kelas Quran mingguan',
              'location': '',
              'location_mode': 'online',
              'start_datetime': _start.add(Duration(days: 7 * i)).toUtc().toIso8601String(),
              'end_datetime': _end.add(Duration(days: 7 * i)).toUtc().toIso8601String(),
              if (i == 2) 'cancelled_at': '2027-01-01T00:00:00Z',
            },
        ]).single;
        await pumpAt(
          t,
          size,
          BlocProvider(
            create: (_) => LanguageCubit(),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 360,
                  height: EventCard.heightFor(TextScaler.noScaling),
                  child: EventCard(event: card, goingCount: 12),
                ),
              ),
            ),
          ),
        );
        // w0 is next; w1 and w3 still to come; w2 is cancelled, not counted.
        expect(card['id'], 'w0');
        expect(find.text(s.seriesMore(2)), findsOneWidget);
        expect(find.text(s.onlineEvent), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
