import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/safe_links.dart';

/// One row of `allowed_link_domains`.
@immutable
class AllowedDomain {
  final String domain;
  final String? note;
  final DateTime? createdAt;

  const AllowedDomain(this.domain, {this.note, this.createdAt});

  factory AllowedDomain.fromRow(Map row) => AllowedDomain(
        row['domain'] as String,
        note: row['note'] as String?,
        createdAt: DateTime.tryParse('${row['created_at']}'),
      );
}

/// The sites whose links are tappable (see `utils/safe_links.dart`).
///
/// Read once per session and cached, like `FeatureFlags`. Until the read
/// lands, or if it fails, the built-in starter list
/// ([kSeedAllowedDomains]) is used, so links still work offline-ish but
/// nothing outside the starter list ever becomes tappable by accident.
///
/// Rebuild on change with
/// `ValueListenableBuilder(valueListenable: AllowedLinks.listenable, …)`.
class AllowedLinks {
  AllowedLinks._();

  static final ValueNotifier<Set<String>> _domains =
      ValueNotifier(Set.unmodifiable(kSeedAllowedDomains));
  static bool _loaded = false;
  static Future<Set<String>>? _inFlight;

  static ValueListenable<Set<String>> get listenable => _domains;

  /// Last known list.
  static Set<String> get current => _domains.value;

  /// Tests: set the list without a database.
  @visibleForTesting
  static void debugSet(Iterable<String> domains) =>
      _domains.value = Set.unmodifiable(domains);

  /// Tests: back to the starter list, not loaded.
  @visibleForTesting
  static void debugReset() {
    _domains.value = Set.unmodifiable(kSeedAllowedDomains);
    _loaded = false;
  }

  /// Reads once per session; later calls return the cache.
  static Future<Set<String>> ensureLoaded() async =>
      _loaded ? _domains.value : refresh();

  /// Reads again. Never throws; on error the last known list stays.
  static Future<Set<String>> refresh() =>
      _inFlight ??= _read().whenComplete(() => _inFlight = null);

  static Future<Set<String>> _read() async {
    try {
      final rows = await Supabase.instance.client
          .from('allowed_link_domains')
          .select('domain') as List;
      _domains.value = Set.unmodifiable(
          rows.map((r) => (r as Map)['domain'] as String));
      _loaded = true;
    } catch (e) {
      debugPrint('AllowedLinks: read failed, keeping last list: $e');
    }
    return _domains.value;
  }

  // ------------------------------------------------------------ admin

  /// Admin list with notes, newest first. Throws on error.
  static Future<List<AllowedDomain>> fetchAll() async {
    final rows = await Supabase.instance.client
        .from('allowed_link_domains')
        .select('domain, note, created_at')
        .order('created_at', ascending: false)
        .order('domain') as List;
    final list = [for (final r in rows) AllowedDomain.fromRow(r as Map)];
    _domains.value = Set.unmodifiable(list.map((d) => d.domain));
    _loaded = true;
    return list;
  }

  /// Admins only (RLS refuses everyone else). [domain] must already be
  /// cleaned by [normalizeDomainInput].
  static Future<void> add(String domain, {String? note}) async {
    await Supabase.instance.client.from('allowed_link_domains').insert({
      'domain': domain,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    _domains.value = Set.unmodifiable({..._domains.value, domain});
  }

  /// Admins only. RLS turns a refused delete into "0 rows", so that is
  /// reported as an error instead of a silent no-op.
  static Future<void> remove(String domain) async {
    final gone = await Supabase.instance.client
        .from('allowed_link_domains')
        .delete()
        .eq('domain', domain)
        .select('domain') as List;
    if (gone.isEmpty) throw StateError('allowed_link_domains: nothing removed');
    _domains.value =
        Set.unmodifiable(_domains.value.where((d) => d != domain));
  }
}
