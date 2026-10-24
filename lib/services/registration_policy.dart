import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the owner has opened signup to any email address.
///
/// Read through `access_policy()`, which is granted to `anon` because the
/// question matters most while signed out. Cached for the session: the
/// answer only changes when the owner flips the switch, and a stale
/// "open" is harmless (the database trigger is the real gate).
class RegistrationPolicy {
  static bool? _open;

  /// Last known answer; false until the first read lands. Failing closed
  /// means a network blip keeps the student-email message instead of
  /// wrongly promising that any address works.
  static bool get isOpen => _open ?? false;

  static Future<bool> refresh() async {
    try {
      final p = await Supabase.instance.client.rpc('access_policy') as Map;
      _open = p['registration_mode'] == 'open';
    } catch (_) {
      _open ??= false;
    }
    return _open ?? false;
  }

  static Future<bool> ensureLoaded() async =>
      _open == null ? refresh() : _open!;

  static void invalidate() => _open = null;
}
