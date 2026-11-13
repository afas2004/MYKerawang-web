import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/router.dart' show isGuestPath;
import 'package:mykerawang/screens/events/attendance_live_screen.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The form's own QR at the door: the organiser switches it on, it sits beside
/// (wide) or below (phone) the check-in code with the form's title beneath,
/// and it points at a link guests can open.

const eventForm = FormDoc(
    id: 'ev-form', title: 'Maklum balas program', status: 'open', eventId: 'ev1',
    isPublic: true);
const privateForm = FormDoc(
    id: 'priv', title: 'Members only', status: 'open', standalone: true);
const slugForm = FormDoc(
    id: 'abc', title: 'Survey', status: 'open', standalone: true,
    isPublic: true, slug: 'sus-survey');

Widget _app(Widget child) => BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      ),
    );

Future<void> _size(WidgetTester t, double w, {double h = 1400}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('where the form QR points', () {
    test('an event form uses /f/<id>, which guests may open', () {
      expect(doorFormPath(eventForm), '/f/ev-form');
      expect(isGuestPath(doorFormPath(eventForm)), isTrue);
      // The event's own answer page is behind sign-in.
      expect(isGuestPath(eventForm.answerPath), isFalse);
    });

    test('a short name is used when there is one', () {
      expect(doorFormPath(slugForm), '/f/sus-survey');
    });
  });

  group('the door codes', () {
    testWidgets('without the form QR: just the check-in code, no labels',
        (t) async {
      await _size(t, 375);
      await t.pumpWidget(_app(const DoorCodes(checkinUrl: 'https://x/c?t=1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('qr-checkin')), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-form')), findsNothing);
      expect(find.byKey(const ValueKey('qr-checkin-label')), findsNothing);
    });

    testWidgets('phone: the form QR sits below, its title beneath it',
        (t) async {
      await _size(t, 375);
      await t.pumpWidget(_app(
          const DoorCodes(checkinUrl: 'https://x/c?t=1', form: eventForm)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      final checkin = t.getRect(find.byKey(const ValueKey('qr-checkin')));
      final form = t.getRect(find.byKey(const ValueKey('qr-form')));
      final title = t.getRect(find.byKey(const ValueKey('qr-form-title')));
      expect(form.top, greaterThan(checkin.bottom));
      expect(title.top, greaterThanOrEqualTo(form.bottom));
      expect(find.text('Maklum balas program'), findsOneWidget);
      expect(find.text('Check in'), findsOneWidget);
    });

    testWidgets('desktop: side by side, the same size', (t) async {
      await _size(t, 1280);
      await t.pumpWidget(_app(
          const DoorCodes(checkinUrl: 'https://x/c?t=1', form: eventForm)));
      await t.pumpAndSettle();

      final checkin = t.getRect(find.byKey(const ValueKey('qr-checkin')));
      final form = t.getRect(find.byKey(const ValueKey('qr-form')));
      expect(form.top, checkin.top);
      expect(form.left, greaterThan(checkin.right));
      expect(form.size, checkin.size);
    });

    testWidgets('a long title wraps under its code at 320 px', (t) async {
      await _size(t, 320);
      const long = FormDoc(
          id: 'l', title: 'Borang maklum balas yang sangat panjang untuk '
              'program kesedaran alam sekitar peringkat kolej',
          status: 'open', standalone: true, isPublic: true);
      await t.pumpWidget(
          _app(const DoorCodes(checkinUrl: 'https://x/c?t=1', form: long)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('the organiser\'s switch', () {
    Future<void> pumpSwitch(WidgetTester t, FormDoc form) async {
      await _size(t, 375);
      var on = false;
      await t.pumpWidget(_app(StatefulBuilder(
        builder: (context, set) => FormQrSwitch(
          form: form,
          value: on,
          onChanged: (v) => set(() => on = v),
        ),
      )));
      await t.pumpAndSettle();
    }

    testWidgets('off by default; a tap turns it on', (t) async {
      await pumpSwitch(t, eventForm);
      final sw = find.byKey(const ValueKey('form-qr-switch'));
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(sw).value, isTrue);
      // A public form: no warning.
      expect(find.byKey(const ValueKey('form-qr-not-public')), findsNothing);
    });

    testWidgets('a private form warns that guests cannot answer', (t) async {
      await pumpSwitch(t, privateForm);
      expect(find.byKey(const ValueKey('form-qr-not-public')), findsNothing);
      await t.tap(find.byKey(const ValueKey('form-qr-switch')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('form-qr-not-public')), findsOneWidget);
    });
  });
}
