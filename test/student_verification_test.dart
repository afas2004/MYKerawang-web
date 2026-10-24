import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/student_verification.dart';

void main() {
  test('fromRow reads the stored record', () {
    final v = StudentVerification.fromRow({
      'email': 'ali@student.uitm.edu.my',
      'status': 'verified',
      'method': 'admin',
      'verified_at': '2026-10-25T01:02:03.000Z',
      'updated_at': '2026-10-25T01:02:03.000Z',
    })!;
    expect(v.email, 'ali@student.uitm.edu.my');
    expect(v.isVerified, isTrue);
    expect(v.isPending, isFalse);
    expect(v.verifiedAt?.toUtc().year, 2026);
  });

  test('pending is not verified', () {
    final v = StudentVerification.fromRow({
      'email': 'a@student.uitm.edu.my',
      'status': 'pending',
      'method': 'admin',
      'verified_at': null,
    })!;
    expect(v.isVerified, isFalse);
    expect(v.isPending, isTrue);
    expect(v.verifiedAt, isNull);
  });

  test('a missing row is null, and bad dates do not throw', () {
    expect(StudentVerification.fromRow(null), isNull);
    final v = StudentVerification.fromRow({
      'email': 'a@x.my',
      'status': 'rejected',
      'method': 'admin',
      'verified_at': 'not a date',
    })!;
    expect(v.verifiedAt, isNull);
    expect(v.isVerified, isFalse);
  });
}
