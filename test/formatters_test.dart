import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/utils/formatters.dart';
import 'package:mykerawang/utils/roles.dart';

void main() {
  test('formatPrice uses one RM style', () {
    expect(formatPrice(12), 'RM 12.00');
    expect(formatPrice(3.5), 'RM 3.50');
    expect(formatPrice(null), 'RM 0.00');
  });

  test('formatEventRange: same day shows one date + both times', () {
    final start = DateTime(2026, 10, 12, 20);
    expect(formatEventRange(start, null), '12 Oct 2026, 8:00 PM');
    expect(formatEventRange(start, DateTime(2026, 10, 12, 22)),
        '12 Oct 2026, 8:00 PM – 10:00 PM');
    expect(formatEventRange(start, DateTime(2026, 10, 13, 2)),
        '12 Oct 2026, 8:00 PM – 13 Oct 2026, 2:00 AM');
  });

  test('parseLocal handles strings, DateTimes and junk', () {
    expect(parseLocal('2026-10-12T12:00:00Z')!.isUtc, isFalse);
    expect(parseLocal(null), isNull);
    expect(parseLocal('nope'), isNull);
  });

  test('fill replaces numbered placeholders', () {
    expect('Photos ({0}/{1})'.fill([2, 5]), 'Photos (2/5)');
  });

  test('roleLabel covers every role', () {
    const s = AppStrings.en;
    expect(roleLabel(s, 'club'), s.roleClub);
    expect(roleLabel(s, 'club_pending'), s.roleClubPending);
    expect(roleLabel(s, 'admin'), s.roleAdmin);
    expect(roleLabel(s, 'owner'), s.roleOwner);
    expect(roleLabel(s, 'student'), s.roleStudent);
    expect(roleLabel(s, null), s.roleStudent);
    expect(displayNameFor(s, {'display_name': 'Aina'}, anonymous: true),
        s.anonymous);
  });
}
