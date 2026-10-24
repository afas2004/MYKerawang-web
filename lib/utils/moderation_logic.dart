import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Pure moderation logic: no widgets, no network. The database is the
/// source of truth (supabase/migrations/20261019004*); this mirrors just
/// enough of it for the app to explain itself before and after a write.

/// Write scopes a restriction can cover. [db] is the stored value.
enum ModScope {
  post('post'),
  comment('comment'),
  market('market'),
  events('events'),
  account('account');

  final String db;
  const ModScope(this.db);

  static ModScope? fromDb(String? v) =>
      ModScope.values.where((s) => s.db == v).firstOrNull;
}

/// Report categories, in the order the report sheet lists them. Stored in
/// `reports.category`; the thresholds in moderation_settings use these.
const kReportCategories = [
  'spam',
  'scam',
  'harassment',
  'impersonation',
  'inappropriate',
  'minor_safety',
  'misinformation',
  'other',
];

/// Reportable target types (`reports.target_type`).
const kTargetTypes = ['post', 'comment', 'event', 'listing', 'user'];

/// Types that can be hidden / removed (a profile can only be warned or
/// restricted).
bool isHideableType(String type) => type != 'user';

/// One active or past restriction, as returned by my_moderation_status()
/// or the moderation_restrictions view.
class Restriction {
  final String id;
  final ModScope scope;
  final DateTime? until; // null = permanent
  final String reason;
  final bool automatic;
  final String? appealStatus;

  const Restriction({
    required this.id,
    required this.scope,
    required this.until,
    required this.reason,
    this.automatic = false,
    this.appealStatus,
  });

  bool get permanent => until == null;

  bool isActiveAt(DateTime now) => until == null || until!.isAfter(now);

  static Restriction? fromJson(Map<String, dynamic> j) {
    final scope = ModScope.fromDb(j['scope'] as String?);
    if (scope == null) return null;
    final until = j['until'];
    return Restriction(
      id: '${j['id'] ?? ''}',
      scope: scope,
      until: until == null ? null : DateTime.tryParse('$until')?.toLocal(),
      reason: '${j['reason'] ?? ''}',
      automatic: j['automatic'] == true,
      appealStatus: j['appeal_status'] as String?,
    );
  }
}

/// The restriction that stops [scope] right now, if any. An account
/// restriction blocks every scope. Permanent beats temporary, then the
/// one that lasts longest — the one worth explaining.
Restriction? blockingRestriction(
    Iterable<Restriction> all, ModScope scope, DateTime now) {
  final hits = all
      .where((r) => r.isActiveAt(now))
      .where((r) => r.scope == scope || r.scope == ModScope.account)
      .toList();
  if (hits.isEmpty) return null;
  hits.sort((a, b) {
    final acc = (b.scope == ModScope.account ? 1 : 0) -
        (a.scope == ModScope.account ? 1 : 0);
    if (acc != 0) return acc;
    if (a.until == null) return b.until == null ? 0 : -1;
    if (b.until == null) return 1;
    return b.until!.compareTo(a.until!);
  });
  return hits.first;
}

/// A server error from the moderation layer, decoded.
///
/// The database raises `MOD:<code>[:<sub>]` with optional JSON detail
/// (see 20261019004200). A duplicate report is Postgres 23505 on
/// `reports_one_per_reporter`; it is mapped to [code] `duplicate_report`.
class ModError {
  final String code;
  final String? sub;
  final Map<String, dynamic> detail;

  const ModError(this.code, {this.sub, this.detail = const {}});

  ModScope? get scope => code == 'restricted'
      ? ModScope.fromDb(sub ?? detail['scope'] as String?)
      : null;

  /// Restriction carried by a `restricted` error, if the server sent one.
  Restriction? get restriction {
    final s = scope;
    if (s == null) return null;
    final until = detail['until'];
    return Restriction(
      id: '',
      scope: s,
      until: until == null ? null : DateTime.tryParse('$until')?.toLocal(),
      reason: '${detail['reason'] ?? ''}',
    );
  }

  @override
  String toString() => 'ModError($code${sub == null ? '' : ':$sub'})';
}

final _modPattern = RegExp(r'MOD:([a-z_]+)(?::([a-z_]+))?');

ModError? parseModError(Object? e) {
  if (e == null) return null;
  String message;
  Object? details;
  String? code;
  if (e is PostgrestException) {
    message = e.message;
    details = e.details;
    code = e.code;
  } else {
    message = e.toString();
  }

  if (code == '23505' && message.contains('reports_one_per_reporter')) {
    return const ModError('duplicate_report');
  }

  final m = _modPattern.firstMatch(message);
  if (m == null) return null;

  Map<String, dynamic> detail = const {};
  if (details is Map<String, dynamic>) {
    detail = details;
  } else if (details is String && details.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(details);
      if (decoded is Map<String, dynamic>) detail = decoded;
    } catch (_) {}
  }
  return ModError(m.group(1)!, sub: m.group(2), detail: detail);
}

/// Queue order: priority first (2 urgent, 1 high, 0 normal), then the
/// oldest first report — nobody waits behind newer noise.
int compareCases(Map<String, dynamic> a, Map<String, dynamic> b) {
  final p = ((b['priority'] ?? 0) as num).compareTo((a['priority'] ?? 0) as num);
  if (p != 0) return p;
  final at = DateTime.tryParse('${a['first_reported_at']}') ?? DateTime(9999);
  final bt = DateTime.tryParse('${b['first_reported_at']}') ?? DateTime(9999);
  return at.compareTo(bt);
}

/// Compact age for the queue header, e.g. "3d 4h", "2h 5m", "12m",
/// "<1m". Units are passed in so the caller can localise them.
String compactAge(Duration d,
    {String day = 'd', String hour = 'h', String minute = 'm', String lessThanMinute = '<1m'}) {
  if (d.isNegative || d.inMinutes < 1) return lessThanMinute;
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days$day $hours$hour' : '$days$day';
  if (d.inHours > 0) {
    return minutes > 0 ? '${d.inHours}$hour $minutes$minute' : '${d.inHours}$hour';
  }
  return '$minutes$minute';
}

/// RFC 4180 CSV. Fields with a comma, quote or newline are quoted, and
/// quotes doubled. Maps/lists are written as JSON.
String toCsv(List<String> columns, Iterable<Map<String, dynamic>> rows) {
  String cell(Object? v) {
    if (v == null) return '';
    final s = (v is Map || v is List) ? jsonEncode(v) : '$v';
    final needsQuotes =
        s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r');
    return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final b = StringBuffer()..writeln(columns.map(cell).join(','));
  for (final r in rows) {
    b.writeln(columns.map((c) => cell(r[c])).join(','));
  }
  return b.toString();
}

/// Durations the restrict dialog offers. null = permanent.
const kRestrictionDurations = <Duration?>[
  Duration(days: 1),
  Duration(days: 3),
  Duration(days: 7),
  Duration(days: 30),
  null,
];

/// Whether an admin action needs the extra "this is serious" confirm:
/// permanent restrictions and whole-account bans are human-only decisions
/// that the app double-checks.
bool isSevereRestriction(Set<ModScope> scopes, Duration? duration) =>
    duration == null || scopes.contains(ModScope.account);

/// The cases bulk actions may touch: only those whose every category is
/// spam (the server enforces the same rule).
bool isBulkEligible(Map<String, dynamic> c) {
  final cats = (c['categories'] as List?)?.cast<String>() ?? const [];
  final active = c['status'] == 'open' || c['status'] == 'hidden';
  return active && cats.isNotEmpty && cats.every((x) => x == 'spam');
}
