import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the server found at a Google Form link: the form's data, or a
/// [reason] it could not be read (`sign_in`, `closed`, `not_found`,
/// `rate_limited`, `bad_url`, `unavailable`, `too_big`, `no_data`, …; see
/// `import_google_form()` in 20261114001100_google_form_import.sql).
class GoogleFormFetch {
  final Object? data;
  final String? reason;
  const GoogleFormFetch.ok(this.data) : reason = null;
  const GoogleFormFetch.failed(this.reason) : data = null;

  bool get ok => reason == null;
}

/// Fetches a Google Form's question data through the server (a browser page
/// may not read docs.google.com directly). Swappable for tests.
abstract class GoogleFormImportService {
  Future<GoogleFormFetch> fetch(String url);

  static GoogleFormImportService instance = const SupabaseGoogleFormImportService();

  @visibleForTesting
  static void debugReset() => instance = const SupabaseGoogleFormImportService();
}

class SupabaseGoogleFormImportService implements GoogleFormImportService {
  const SupabaseGoogleFormImportService();

  @override
  Future<GoogleFormFetch> fetch(String url) async {
    final raw = await Supabase.instance.client
        .rpc('import_google_form', params: {'p_url': url});
    if (raw is! Map) return const GoogleFormFetch.failed('no_data');
    if (raw['ok'] == true) return GoogleFormFetch.ok(raw['data']);
    return GoogleFormFetch.failed('${raw['reason'] ?? 'no_data'}');
  }
}
