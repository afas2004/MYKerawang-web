import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/moderation_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/admin/admin_overview.dart';
import 'package:mykerawang/screens/admin/case_detail.dart';
import 'package:mykerawang/screens/admin/case_workspace.dart';
import 'package:mykerawang/screens/admin/restrict_dialog.dart';
import 'package:mykerawang/screens/standing_screen.dart';
import 'package:mykerawang/services/moderation_service.dart';
import 'package:mykerawang/utils/moderation_logic.dart';
import 'package:mykerawang/widgets/report_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moderation surfaces with injected data — no Supabase. Each layout is
/// rendered at phone (375), tablet (768) and desktop (1280) widths;
/// any RenderFlex overflow fails the test.
void main() {
  const widths = [375.0, 768.0, 1280.0];
  const m = ModerationStrings.en;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
  }

  final now = DateTime.now().toUtc();
  Map<String, dynamic> kase(String id,
          {int priority = 0,
          String status = 'open',
          String type = 'post',
          bool anonymous = false,
          List<String> categories = const ['harassment'],
          String title = 'A fairly long post title that should be ellipsised in narrow lists'}) =>
      {
        'id': id,
        'target_type': type,
        'target_id': 't$id',
        'status': status,
        'priority': priority,
        'auto_hidden': status == 'hidden',
        'target_anonymous': anonymous,
        'owner': anonymous
            ? null
            : {'id': 'u1', 'username': 'amir', 'display_name': 'Amir bin Abdullah', 'avatar_url': null},
        'owner_strikes': 1,
        'report_count': 4,
        'trusted_reporters': 3,
        'categories': categories,
        'first_reported_at': now.subtract(const Duration(days: 2, hours: 3)).toIso8601String(),
        'preview': {'title': title, 'body': 'Body text ' * 30},
      };

  final cases = [
    kase('1', priority: 2, status: 'hidden', categories: ['scam', 'spam']),
    kase('2', priority: 1, anonymous: true, type: 'comment'),
    kase('3', type: 'listing'),
  ];

  Future<Map<String, dynamic>> detail(String id) async => {
        'reports': [
          {'category': 'scam', 'note': 'Asked for a deposit by bank transfer', 'created_at': now.toIso8601String(), 'counted': true},
          {'category': 'spam', 'note': null, 'created_at': now.toIso8601String(), 'counted': false},
        ],
        'history': id == '2'
            ? []
            : [
                {'target_type': 'post', 'status': 'actioned', 'decision': 'warned', 'decision_reason': 'Rude', 'strike': true, 'first_reported_at': now.toIso8601String()},
              ],
        'restrictions': [
          {'scope': 'market', 'until': now.add(const Duration(days: 3)).toIso8601String(), 'automatic': true},
        ],
      };

  final acted = <String>[];
  Future<bool> rec(String s) async {
    acted.add(s);
    return true;
  }

  CaseActions actions() => CaseActions(
        dismissOrRestore: (c) => rec('dismiss ${c['id']}'),
        remove: (c) => rec('remove ${c['id']}'),
        warn: (c) => rec('warn ${c['id']}'),
        restrict: (c) => rec('restrict ${c['id']}'),
        unmask: (c) => rec('unmask ${c['id']}'),
        open: (c) => acted.add('open ${c['id']}'),
      );

  Widget workspace({String? selected = '1'}) => StatefulBuilder(
        builder: (context, setState) => CaseWorkspace(
          cases: cases,
          selectedId: selected,
          onSelect: (c) => setState(() => selected = '${c['id']}'),
          detailFor: detail,
          actions: actions(),
        ),
      );

  for (final w in widths) {
    testWidgets('case workspace lays out at ${w.toInt()} px', (tester) async {
      acted.clear();
      await pumpAt(tester, w, workspace());
      expect(find.byType(CaseWorkspace), findsOneWidget);
      if (w >= kCaseMasterDetailWidth) {
        // Master–detail: list and the selected case's detail side by side.
        expect(find.byType(CaseDetailPane), findsOneWidget);
        expect(find.textContaining('Asked for a deposit', skipOffstage: false), findsOneWidget);
        expect(find.text(m.actionRestore), findsOneWidget); // hidden case → Restore
        await tester.tap(find.text(m.actionRestore));
        expect(acted, ['dismiss 1']);
        // Selecting another row swaps the detail.
        await tester.tap(find.textContaining('Comment').first);
        await tester.pumpAndSettle();
        expect(find.text(m.ui.historyAnon, skipOffstage: false), findsOneWidget);
      } else {
        // Compact: list only; a row pushes the detail page.
        expect(find.byType(CaseDetailPane), findsNothing);
        await tester.tap(find.textContaining('Listing').first);
        await tester.pumpAndSettle();
        expect(find.byType(CaseDetailPane), findsOneWidget);
        expect(find.text(m.actionDismiss), findsOneWidget);
        await tester.tap(find.text(m.actionDismiss));
        await tester.pumpAndSettle();
        expect(acted, ['dismiss 3']);
        expect(find.byType(CaseDetailPane), findsNothing, reason: 'completed action closes the page');
      }
    });

    testWidgets('overview stat cards fit at ${w.toInt()} px', (tester) async {
      await pumpAt(
        tester,
        w,
        AdminOverview(summary: {
          'open_cases': 12,
          'hidden_cases': 3,
          'oldest_open_at': now.subtract(const Duration(days: 4)).toIso8601String(),
          'club_requests': 2,
          'pending_appeals': 1,
        }),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('4d'), findsOneWidget);
    });

    testWidgets('standing view lays out at ${w.toInt()} px', (tester) async {
      final appealed = <String>[];
      final status = ModerationStatus.fromJson({
        'banned': false,
        'restrictions': [
          {'id': 'r1', 'scope': 'comment', 'until': now.add(const Duration(days: 7)).toIso8601String(), 'reason': 'Repeated insults in comments', 'automatic': true},
          {'id': 'r2', 'scope': 'market', 'until': null, 'reason': 'Scam listing', 'appeal_status': 'pending'},
        ],
        'cases': [
          {'id': 'c1', 'target_type': 'post', 'status': 'actioned', 'decision': 'removed', 'reason': 'Harassment', 'categories': ['harassment'], 'decided_at': now.toIso8601String(), 'preview': {'title': 'My post'}},
          {'id': 'c2', 'target_type': 'listing', 'status': 'hidden', 'categories': ['scam'], 'hidden_at': now.toIso8601String(), 'preview': {'title': 'Used textbook'}},
        ],
      });
      await pumpAt(
        tester,
        w,
        StandingView(
          status: status,
          onAppealRestriction: (id) => appealed.add(id),
          onAppealCase: (id) => appealed.add(id),
        ),
      );
      expect(find.text(m.cantComment), findsOneWidget);
      expect(find.text(m.appealPending), findsOneWidget);
      // r1, c1 and c2 can be appealed; r2 already was.
      expect(find.text(m.appeal), findsNWidgets(3));
      await tester.tap(find.text(m.appeal).first);
      expect(appealed, ['r1']);
    });

    testWidgets('clean standing at ${w.toInt()} px', (tester) async {
      await pumpAt(
        tester,
        w,
        StandingView(status: ModerationStatus.empty, onAppealRestriction: (_) {}, onAppealCase: (_) {}),
      );
      expect(find.text(m.goodStanding), findsOneWidget);
    });

    testWidgets('report sheet flow at ${w.toInt()} px', (tester) async {
      String? sentNote;
      await pumpAt(
        tester,
        w,
        ReportSheet(
          targetId: 'p1',
          targetType: 'post',
          submit: ({required targetId, required targetType, required category, required reason, note}) async {
            sentNote = note;
            return const ReportOutcome(ReportResult.received);
          },
        ),
      );
      final send = find.widgetWithText(FilledButton, m.ui.reportSubmit);
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'needs a category first');
      await tester.tap(find.text(m.catScam));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Asked me to pay first');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sentNote, 'Asked me to pay first');
      expect(find.text(m.ui.reportDoneTitle), findsOneWidget);
    });
  }

  testWidgets('report sheet shows duplicate state', (tester) async {
    await pumpAt(
      tester,
      375,
      ReportSheet(
        targetId: 'p1',
        targetType: 'post',
        submit: ({required targetId, required targetType, required category, required reason, note}) async =>
            const ReportOutcome(ReportResult.duplicate),
      ),
    );
    await tester.tap(find.text(m.catSpam));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, m.ui.reportSubmit);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text(m.ui.reportDupTitle), findsOneWidget);
  });

  testWidgets('keyboard shortcuts call their actions', (tester) async {
    final calls = <String>[];
    await pumpAt(
      tester,
      1280,
      CaseShortcuts(
        onNext: () => calls.add('next'),
        onPrev: () => calls.add('prev'),
        onOpen: () => calls.add('open'),
        onDismiss: () => calls.add('dismiss'),
        onHide: () => calls.add('hide'),
        onRestore: () => calls.add('restore'),
        child: const SizedBox.expand(),
      ),
    );
    for (final k in [
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyR,
    ]) {
      await tester.sendKeyEvent(k);
    }
    expect(calls, ['next', 'prev', 'dismiss', 'hide', 'restore']);
  });

  testWidgets('restrict dialog previews the experience', (tester) async {
    await pumpAt(tester, 375, const RestrictDialog(who: 'Amir', initialScopes: {ModScope.post}));
    expect(find.textContaining("won't be able to post"), findsOneWidget);
    await tester.tap(find.text(m.scopeComment));
    await tester.pumpAndSettle();
    expect(find.text("They won't be able to post or comment."), findsOneWidget);
    await tester.tap(find.text(m.durationPermanent));
    await tester.pumpAndSettle();
    expect(find.text(m.ui.previewForever), findsOneWidget);
    expect(find.text(m.severeWarning), findsOneWidget);
  });

  test('restrictionPreview wording', () {
    final at = DateTime(2026, 10, 19, 15);
    expect(restrictionPreview(m, {}, null, at), [m.ui.previewPick]);
    final lines = restrictionPreview(
        m, {ModScope.post, ModScope.comment, ModScope.market}, const Duration(days: 1), at);
    expect(lines.first, "They won't be able to post, comment or sell in the Market.");
    expect(lines[1], contains('20 Oct 2026'));
    expect(restrictionPreview(m, {ModScope.account, ModScope.post}, null, at).first,
        "They won't be able to post, comment, sell, join events, follow or report.");
    expect(restrictionPreview(ModerationStrings.ms, {ModScope.post}, null, at).first,
        'Mereka tidak boleh menyiarkan.');
  });
}
