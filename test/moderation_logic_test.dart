import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/moderation_strings.dart';
import 'package:mykerawang/utils/moderation_logic.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  final now = DateTime(2026, 10, 19, 12);

  Restriction r(ModScope s, {DateTime? until, String id = 'x'}) =>
      Restriction(id: id, scope: s, until: until, reason: 'because');

  group('blockingRestriction', () {
    test('none when nothing applies', () {
      expect(blockingRestriction([r(ModScope.market)], ModScope.post, now), isNull);
    });

    test('expired restrictions no longer block', () {
      final expired = r(ModScope.post, until: now.subtract(const Duration(minutes: 1)));
      expect(blockingRestriction([expired], ModScope.post, now), isNull);
    });

    test('account blocks every scope and wins over a scoped one', () {
      final scoped = r(ModScope.comment, id: 'c');
      final account = r(ModScope.account, until: now.add(const Duration(days: 1)), id: 'a');
      expect(blockingRestriction([scoped, account], ModScope.comment, now)!.id, 'a');
      expect(blockingRestriction([account], ModScope.market, now)!.id, 'a');
    });

    test('permanent beats temporary, then the longest', () {
      final short = r(ModScope.post, until: now.add(const Duration(days: 1)), id: 's');
      final long = r(ModScope.post, until: now.add(const Duration(days: 9)), id: 'l');
      final forever = r(ModScope.post, id: 'p');
      expect(blockingRestriction([short, long], ModScope.post, now)!.id, 'l');
      expect(blockingRestriction([short, forever, long], ModScope.post, now)!.id, 'p');
    });
  });

  group('parseModError', () {
    test('restriction with JSON detail', () {
      const e = PostgrestException(
        message: 'MOD:restricted:post',
        code: 'P0001',
        details: '{"scope":"post","until":"2026-10-20T00:00:00+00:00","reason":"spam"}',
      );
      final m = parseModError(e)!;
      expect(m.code, 'restricted');
      expect(m.scope, ModScope.post);
      expect(m.restriction!.reason, 'spam');
      expect(m.restriction!.until, isNotNull);
    });

    test('permanent account restriction', () {
      const e = PostgrestException(
          message: 'MOD:restricted:account',
          details: '{"scope":"account","until":null,"reason":"abuse"}');
      final m = parseModError(e)!;
      expect(m.scope, ModScope.account);
      expect(m.restriction!.permanent, isTrue);
    });

    test('rate limit carries limit and hours', () {
      const e = PostgrestException(
          message: 'MOD:rate_limited:comment', details: '{"limit":10,"hours":24}');
      final m = parseModError(e)!;
      expect(m.code, 'rate_limited');
      expect(m.sub, 'comment');
      expect(m.detail['limit'], 10);
    });

    test('duplicate report from the unique constraint', () {
      const e = PostgrestException(
          message: 'duplicate key value violates unique constraint "reports_one_per_reporter"',
          code: '23505');
      expect(parseModError(e)!.code, 'duplicate_report');
    });

    test('plain codes and non-moderation errors', () {
      expect(parseModError(const PostgrestException(message: 'MOD:pin_cap'))!.code, 'pin_cap');
      expect(parseModError(Exception('MOD:self_report'))!.code, 'self_report');
      expect(parseModError(const PostgrestException(message: 'JWT expired')), isNull);
      expect(parseModError(null), isNull);
    });

    test('malformed detail is ignored', () {
      const e = PostgrestException(message: 'MOD:restricted:post', details: '{oops');
      expect(parseModError(e)!.detail, isEmpty);
    });
  });

  test('compareCases: priority first, then oldest', () {
    final cases = [
      {'id': 'new-normal', 'priority': 0, 'first_reported_at': '2026-10-19T10:00:00Z'},
      {'id': 'old-normal', 'priority': 0, 'first_reported_at': '2026-10-10T10:00:00Z'},
      {'id': 'urgent', 'priority': 2, 'first_reported_at': '2026-10-19T11:00:00Z'},
      {'id': 'high', 'priority': 1, 'first_reported_at': '2026-10-18T11:00:00Z'},
    ]..sort(compareCases);
    expect(cases.map((c) => c['id']), ['urgent', 'high', 'old-normal', 'new-normal']);
  });

  test('compactAge', () {
    expect(compactAge(const Duration(seconds: 20)), '<1m');
    expect(compactAge(const Duration(minutes: 12)), '12m');
    expect(compactAge(const Duration(hours: 2, minutes: 5)), '2h 5m');
    expect(compactAge(const Duration(hours: 3)), '3h');
    expect(compactAge(const Duration(days: 3, hours: 4, minutes: 9)), '3d 4h');
    expect(compactAge(const Duration(days: 2)), '2d');
    expect(compactAge(const Duration(days: 1, hours: 2), day: 'h', hour: 'j'), '1h 2j');
  });

  test('toCsv quotes, escapes and JSON-encodes', () {
    final csv = toCsv(['a', 'b', 'c'], [
      {'a': 'plain', 'b': 'with, comma', 'c': {'k': 1}},
      {'a': 'say "hi"', 'b': 'line\nbreak', 'c': null},
    ]);
    expect(
      csv,
      'a,b,c\n'
      'plain,"with, comma","{""k"":1}"\n'
      '"say ""hi""","line\nbreak",\n',
    );
  });

  test('isSevereRestriction', () {
    expect(isSevereRestriction({ModScope.post}, const Duration(days: 7)), isFalse);
    expect(isSevereRestriction({ModScope.post}, null), isTrue);
    expect(isSevereRestriction({ModScope.account}, const Duration(days: 1)), isTrue);
  });

  test('isBulkEligible only for active all-spam cases', () {
    expect(isBulkEligible({'status': 'open', 'categories': ['spam']}), isTrue);
    expect(isBulkEligible({'status': 'hidden', 'categories': ['spam', 'scam']}), isFalse);
    expect(isBulkEligible({'status': 'dismissed', 'categories': ['spam']}), isFalse);
    expect(isBulkEligible({'status': 'open', 'categories': []}), isFalse);
  });

  test('Restriction.fromJson', () {
    final x = Restriction.fromJson({
      'id': 'r1', 'scope': 'market', 'until': null, 'reason': 'scam', 'automatic': true,
    })!;
    expect(x.scope, ModScope.market);
    expect(x.permanent, isTrue);
    expect(x.automatic, isTrue);
    expect(Restriction.fromJson({'scope': 'nope'}), isNull);
  });

  group('ModerationStrings', () {
    test('every category, type and scope has a label in every language', () {
      for (final s in [AppStrings.en, AppStrings.ms, AppStrings.ja]) {
        final m = s.mod;
        for (final c in kReportCategories) {
          expect(m.categoryLabel(c), isNotEmpty);
        }
        for (final t in kTargetTypes) {
          expect(m.typeLabel(t), isNotEmpty);
        }
        for (final sc in ModScope.values) {
          expect(m.scopeLabel(sc.db), isNotEmpty);
          expect(m.cantTitle(sc.db), isNotEmpty);
        }
      }
    });

    test('ms is Malay, ja falls back to English', () {
      expect(AppStrings.ms.mod.moderation, 'Moderasi');
      expect(identical(AppStrings.ja.mod, ModerationStrings.en), isTrue);
    });

    test('stored reason is always English', () {
      expect(ModerationStrings.categoryReason('scam'), 'Scam or fraud');
    });

    test('the reviewed-first defaults are real categories', () {
      expect(kDefaultPriorityCategories,
          ['harassment', 'inappropriate']);
      for (final c in kDefaultPriorityCategories) {
        expect(kReportCategories, contains(c));
      }
    });

    test('impersonation is reportable, with copy in every language', () {      expect(kReportCategories, contains('impersonation'));
      for (final s in [AppStrings.en, AppStrings.ms]) {
        final m = s.mod;
        expect(m.categoryLabel('impersonation'), isNotEmpty);
        expect(m.ui.categoryDescription('impersonation'), isNotEmpty);
      }
      expect(ModerationStrings.categoryReason('impersonation'),
          'Pretending to be someone else');
    });

    test('durationLabel', () {
      final m = ModerationStrings.en;
      expect(m.durationLabel(null), 'Permanent');
      expect(m.durationLabel(const Duration(days: 1)), '1 day');
      expect(m.durationLabel(const Duration(days: 7)), '7 days');
    });
  });
}
