import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/events/attendance_live_screen.dart';
import 'package:mykerawang/screens/events/attendance_start_dialog.dart';
import 'package:mykerawang/screens/events/checkin_screens.dart';
import 'package:mykerawang/services/checkin_form_service.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/services/my_forms_service.dart';
import 'package:mykerawang/utils/attendance_rules.dart';
import 'package:mykerawang/utils/form_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Attendance with any form: the start pop-up's choices, which form the
/// success screen offers (and where it links), the attendance CSV with the
/// student-features switch, and KI wording only for KI forms.

const _kiField = FormFieldSpec(
    id: 'k1', kind: 'rating', label: 'KI1', analysis: 'ki_pre', kiCode: 1);
const _textField = FormFieldSpec(id: 't1', kind: 'short_text', label: 'Name');

const kiForm = FormDoc(
    id: 'ki', title: 'Laporan KI', status: 'open', eventId: 'ev1', fields: [_kiField]);
const feedback = FormDoc(
    id: 'fb', title: 'Feedback', status: 'open', standalone: true, fields: [_textField]);

class _Forms implements FormService {
  _Forms(this.views, {this.openId});
  final Map<String, FormView> views;
  final String? openId;

  @override
  Future<String?> openFormId(String eventId) async => openId;
  @override
  Future<FormView> load(String formId) async => views[formId]!;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Checkin implements CheckinFormService {
  _Checkin({this.id, this.unsupported = false});
  final String? id;
  final bool unsupported;

  @override
  Future<String?> offered(String eventId) async {
    if (unsupported) throw const CheckinFormUnsupported();
    return id;
  }

  @override
  Future<CheckinFormState> current(String eventId) async =>
      CheckinFormState(supported: !unsupported, formId: id);
  @override
  Future<void> choose(String eventId, String? formId) async {}
}

Widget _app(Widget child, {List<String>? visited}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: Center(child: child))),
    GoRoute(
        path: '/:rest(.*)',
        builder: (_, s) {
          visited?.add(s.uri.toString());
          return const Scaffold(body: Text('elsewhere'));
        }),
  ]);
  return BlocProvider(
    create: (_) => LanguageCubit(),
    child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true), routerConfig: router),
  );
}

Future<void> _size(WidgetTester t, double w, {double h = 900}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Opens the pop-up from a button and returns the choice once it closes.
Future<AttendanceFormChoice?> Function() _openDialog(
    WidgetTester t, AttendanceStartDialog dialog) {
  AttendanceFormChoice? result;
  var done = false;
  return () async {
    await t.pumpWidget(_app(Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          result = await showDialog<AttendanceFormChoice>(
              context: context, builder: (_) => dialog);
          done = true;
        },
        child: const Text('open'),
      ),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return done ? result : null;
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    FormService.debugReset();
    CheckinFormService.debugReset();
  });

  group('the start pop-up', () {
    for (final w in [375.0, 1280.0]) {
      testWidgets('offers none / this event\'s form / one of my forms at $w',
          (t) async {
        await _size(t, w);
        final open = _openDialog(
            t,
            AttendanceStartDialog(
              ownForm: kiForm,
              pickForm: (_) async => const MyForm(id: 'fb', title: 'Feedback', status: 'open'),
            ));
        await open();
        expect(find.byKey(const ValueKey('af-none')), findsOneWidget);
        expect(find.byKey(const ValueKey('af-own')), findsOneWidget);
        expect(find.textContaining('Laporan KI'), findsOneWidget);
        expect(find.byKey(const ValueKey('af-other')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('picking one of my forms returns it', (t) async {
      await _size(t, 375);
      AttendanceFormChoice? got;
      await t.pumpWidget(_app(Builder(
        builder: (context) => FilledButton(
          onPressed: () async => got = await showDialog<AttendanceFormChoice>(
            context: context,
            builder: (_) => AttendanceStartDialog(
              ownForm: kiForm,
              pickForm: (_) async =>
                  const MyForm(id: 'fb', title: 'Feedback', status: 'open'),
            ),
          ),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('af-other')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('af-other-title')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('af-start')));
      await t.pumpAndSettle();
      expect(got?.kind, AttendanceFormKind.other);
      expect(got?.otherId, 'fb');
    });

    testWidgets('no own form: no "this event" choice, and a make-one link',
        (t) async {
      await _size(t, 375);
      AttendanceFormChoice? got;
      await t.pumpWidget(_app(Builder(
        builder: (context) => FilledButton(
          onPressed: () async => got = await showDialog<AttendanceFormChoice>(
              context: context, builder: (_) => const AttendanceStartDialog()),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('af-own')), findsNothing);
      await t.tap(find.byKey(const ValueKey('af-start')));
      await t.pumpAndSettle();
      expect(got?.kind, AttendanceFormKind.none);
    });

    testWidgets('before the migration only the event\'s own form is offered',
        (t) async {
      await _size(t, 375);
      await _openDialog(
          t, const AttendanceStartDialog(ownForm: kiForm, canPickAny: false))();
      expect(find.byKey(const ValueKey('af-other')), findsNothing);
      expect(find.byKey(const ValueKey('af-own')), findsOneWidget);
    });

    testWidgets('starts on the earlier choice', (t) async {
      await _size(t, 375);
      await _openDialog(
          t,
          const AttendanceStartDialog(
            ownForm: kiForm,
            initialKind: AttendanceFormKind.other,
            initialOtherId: 'fb',
            initialOtherTitle: 'Feedback',
          ))();
      expect(find.text('Feedback'), findsOneWidget);
      expect(find.byKey(const ValueKey('af-change')), findsOneWidget);
    });
  });

  group('the success-screen offer', () {
    test('a standalone form chosen by the organiser is offered', () async {
      FormService.instance = _Forms({'fb': const FormView(doc: feedback, canAnswer: true)});
      CheckinFormService.instance = _Checkin(id: 'fb');
      final f = await loadCheckinOffer('ev1');
      expect(f?.id, 'fb');
      expect(f?.answerPath, '/f/fb');
    });

    test('already answered: no offer', () async {
      FormService.instance = _Forms({
        'fb': const FormView(doc: feedback, canAnswer: true, mine: {'t1': 'x'})
      });
      CheckinFormService.instance = _Checkin(id: 'fb');
      expect(await loadCheckinOffer('ev1'), isNull);
    });

    test('without the migration: the old KI rule (after_checkin) still works',
        () async {
      FormService.instance = _Forms(
          {'ki': FormView(doc: kiForm.copyWith(afterCheckin: true), canAnswer: true)},
          openId: 'ki');
      CheckinFormService.instance = _Checkin(unsupported: true);
      expect((await loadCheckinOffer('ev1'))?.id, 'ki');

      FormService.instance =
          _Forms({'ki': const FormView(doc: kiForm, canAnswer: true)}, openId: 'ki');
      expect(await loadCheckinOffer('ev1'), isNull,
          reason: 'flag off: nothing offered, as before');
    });

    for (final w in [375.0, 1280.0]) {
      testWidgets('the button links to the standalone form at $w', (t) async {
        await _size(t, w);
        final visited = <String>[];
        await t.pumpWidget(_app(
            const SizedBox(width: 320, child: CheckinFormOffer(form: feedback)),
            visited: visited));
        await t.pumpAndSettle();
        expect(find.text('Answer the form'), findsOneWidget);
        expect(find.text('Answer the KI form'), findsNothing);
        expect(find.text('Feedback'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('offer-answer')));
        await t.pumpAndSettle();
        expect(visited, ['/f/fb']);
      });
    }

    testWidgets('a KI form keeps "Answer the KI form" and its event path',
        (t) async {
      await _size(t, 375);
      final visited = <String>[];
      await t.pumpWidget(_app(
          const SizedBox(width: 320, child: CheckinFormOffer(form: kiForm)),
          visited: visited));
      await t.pumpAndSettle();
      expect(find.text('Answer the KI form'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('offer-answer')));
      await t.pumpAndSettle();
      expect(visited, ['/event/ev1/form?f=ki']);
    });
  });

  group('the attendance CSV', () {
    final rows = [
      {
        'display_name': 'Aina',
        'student_id': '2023837334',
        'verified': true,
        'checked_in_at': '2026-11-13T10:00:00Z',
      },
    ];

    test('student features on: student_id and verified columns', () {
      final csv = attendanceCsv(rows).split('\n');
      expect(csv.first.trim(), 'name,student_id,verified,checked_in_at');
      expect(csv[1].trim(), 'Aina,2023837334,yes,2026-11-13T10:00:00Z');
    });

    test('student features off: those two columns are dropped', () {
      final csv = attendanceCsv(rows, studentFeatures: false).split('\n');
      expect(csv.first.trim(), 'name,checked_in_at');
      expect(csv[1].trim(), 'Aina,2026-11-13T10:00:00Z');
    });
  });

  group('KI labels only for KI forms', () {
    test('isKi follows the KI-tagged questions', () {
      expect(kiForm.isKi, isTrue);
      expect(feedback.isKi, isFalse);
    });

    Future<void> pumpSummary(WidgetTester t, FormDoc? form, double w) async {
      await _size(t, w, h: 1000);
      await t.pumpWidget(_app(SizedBox(
        width: 480,
        child: AttendanceSummary(
          title: 'Ujian',
          checkedIn: 12,
          form: form,
          formResponses: 9,
          onExport: ({required attendance, required responses}) {},
          onDone: () {},
        ),
      )));
      await t.pumpAndSettle();
    }

    for (final w in [375.0, 1280.0]) {
      testWidgets('a plain form says "Form responses" / "Responses CSV" at $w',
          (t) async {
        await pumpSummary(t, feedback, w);
        expect(find.text('Form responses'), findsOneWidget);
        expect(find.text('Responses CSV'), findsOneWidget);
        expect(find.text('KI reports'), findsNothing);
        expect(find.text('KI report CSV'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a KI form keeps "KI reports" / "KI report CSV"', (t) async {
      await pumpSummary(t, kiForm, 375);
      expect(find.text('KI reports'), findsOneWidget);
      expect(find.text('KI report CSV'), findsOneWidget);
      expect(find.text('Form responses'), findsNothing);
    });

    testWidgets('no form: only the attendance total and CSV', (t) async {
      await pumpSummary(t, null, 375);
      expect(find.byKey(const ValueKey('stat-responses')), findsNothing);
      expect(find.byKey(const ValueKey('export-responses')), findsNothing);
      expect(find.text('Attendance CSV'), findsOneWidget);
    });
  });
}
