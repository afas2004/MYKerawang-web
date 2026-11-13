import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when the database does not have 20261113001100_attendance_any_form
/// yet (missing column or RPC). Callers fall back to the old KI-only rule.
class CheckinFormUnsupported implements Exception {
  const CheckinFormUnsupported();
}

/// What the organiser chose last time, as the start pop-up needs it.
class CheckinFormState {
  /// The database knows `events.checkin_form_id`.
  final bool supported;

  /// The chosen form, or null for "nothing chosen" (old rule applies).
  final String? formId;

  const CheckinFormState({this.supported = true, this.formId});
}

/// True for "this function / column does not exist", which is how a database
/// without the migration answers.
bool isMissingSchema(Object e) {
  if (e is! PostgrestException) return false;
  final code = e.code ?? '';
  return code == 'PGRST202' || // function not found
      code == 'PGRST204' || // column not found (schema cache)
      code == '42883' || // undefined function
      code == '42703'; // undefined column
}

/// Which form the check-in success screen offers. Swappable for tests:
/// `CheckinFormService.instance = FakeCheckinForms()`.
abstract class CheckinFormService {
  /// The organiser's current choice for [eventId].
  Future<CheckinFormState> current(String eventId);

  /// Sets (or with null clears) the form offered after check-in. Throws
  /// [CheckinFormUnsupported] without the migration.
  Future<void> choose(String eventId, String? formId);

  /// The form a person who just checked in should be offered, or null.
  /// Throws [CheckinFormUnsupported] without the migration.
  Future<String?> offered(String eventId);

  static CheckinFormService instance = const SupabaseCheckinFormService();

  @visibleForTesting
  static void debugReset() => instance = const SupabaseCheckinFormService();
}

class SupabaseCheckinFormService implements CheckinFormService {
  const SupabaseCheckinFormService();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<CheckinFormState> current(String eventId) async {
    try {
      final row = await _db
          .from('events')
          .select('checkin_form_id')
          .eq('id', eventId)
          .maybeSingle();
      return CheckinFormState(formId: row?['checkin_form_id'] as String?);
    } catch (e) {
      if (isMissingSchema(e)) return const CheckinFormState(supported: false);
      rethrow;
    }
  }

  @override
  Future<void> choose(String eventId, String? formId) async {
    try {
      await _db.rpc('set_event_checkin_form',
          params: {'p_event_id': eventId, 'p_form_id': formId});
    } catch (e) {
      if (isMissingSchema(e)) throw const CheckinFormUnsupported();
      rethrow;
    }
  }

  @override
  Future<String?> offered(String eventId) async {
    try {
      final raw =
          await _db.rpc('event_checkin_form', params: {'p_event_id': eventId});
      return raw == null ? null : '$raw';
    } catch (e) {
      if (isMissingSchema(e)) throw const CheckinFormUnsupported();
      rethrow;
    }
  }
}
