import 'package:supabase_flutter/supabase_flutter.dart';

/// One account's student verification, as stored.
///
/// A mailbox is all this proves: the address, whether it was accepted, and
/// when. There is deliberately no name here.
class StudentVerification {
  final String email;

  /// pending | verified | rejected | revoked | expired
  final String status;
  final String method;
  final DateTime? verifiedAt;
  final DateTime? updatedAt;

  const StudentVerification({
    required this.email,
    required this.status,
    required this.method,
    this.verifiedAt,
    this.updatedAt,
  });

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';

  static StudentVerification? fromRow(Map<String, dynamic>? row) {
    if (row == null) return null;
    return StudentVerification(
      email: (row['email'] as String?) ?? '',
      status: (row['status'] as String?) ?? '',
      method: (row['method'] as String?) ?? '',
      verifiedAt: DateTime.tryParse('${row['verified_at'] ?? ''}'),
      updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}'),
    );
  }
}

/// Client for the verification record. Requests go to security-definer
/// RPCs; the table itself is read-only for its owner.
class StudentVerificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// The owner's switch, readable by every signed-in account so the app
  /// can hide the entry points while the feature is off.
  static Future<bool> isEnabled() async {
    try {
      final p = await _db.rpc('access_policy') as Map;
      return p['verification_enabled'] == true;
    } catch (_) {
      // Unknown reads as off: never ask someone to verify into a closed door.
      return false;
    }
  }

  static Future<StudentVerification?> mine() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _db
          .from('student_verifications')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      return StudentVerification.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  /// Submits the address for an admin to check. Returns nothing; the
  /// request is read back through [mine].
  static Future<void> request(String email) => _db
      .rpc('request_student_verification', params: {'p_email': email.trim()});

  // ------------------------------------------------------------ admin
  static Future<List<Map<String, dynamic>>> queue() async =>
      List<Map<String, dynamic>>.from(
          await _db.rpc('admin_verification_queue') as List);

  static Future<void> approve(String userId, String email) =>
      _db.rpc('admin_set_student_verification', params: {
        'p_user_id': userId,
        'p_email': email,
        'p_status': 'verified',
      });

  static Future<void> reject(String userId) =>
      _db.rpc('admin_set_student_verification', params: {
        'p_user_id': userId,
        'p_email': '',
        'p_status': 'rejected',
      });
}
