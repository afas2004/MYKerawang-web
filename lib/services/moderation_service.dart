import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/moderation_logic.dart';

/// Talks to the moderation RPCs and views (supabase/migrations/
/// 20261019004*). Every decision is made server-side; this class only
/// calls, caches what's cheap to cache, and decodes errors into
/// [ModError] for the UI to explain.
class ModerationService {
  ModerationService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _uid => debugCurrentUserId != null
      ? debugCurrentUserId!()
      : _db.auth.currentUser?.id;

  /// The signed-in user's id (overridable in tests).
  static String? get currentUserId => _uid;

  /// Test hooks: widget tests run without a Supabase instance.
  static String? Function()? debugCurrentUserId;
  static Future<String?> Function()? debugMyRole;

  // ------------------------------------------------------------- roles
  static String? _roleFor;
  static Future<String?>? _role;

  /// The caller's `profiles.role`, cached per signed-in user.
  static Future<String?> myRole() {
    if (debugMyRole != null) return debugMyRole!();
    final uid = _uid;
    if (uid == null) return Future.value(null);
    if (_roleFor != uid || _role == null) {
      _roleFor = uid;
      _role = _db
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle()
          .then((r) => r?['role'] as String?)
          .catchError((_) {
        _role = null; // retry next time
        return null;
      });
    }
    return _role!;
  }

  static Future<bool> isAdmin() async {
    final r = await myRole();
    return r == 'admin' || r == 'owner';
  }

  static Future<bool> isOwner() async => (await myRole()) == 'owner';

  // ------------------------------------------------------------- my status
  static ModerationStatus? _status;
  static String? _statusFor;
  static DateTime? _statusAt;

  /// Restrictions and decisions about the caller. Cached for a minute so
  /// create buttons can check before every write without a round trip.
  static Future<ModerationStatus> myStatus({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return ModerationStatus.empty;
    final fresh = _statusAt != null &&
        DateTime.now().difference(_statusAt!) < const Duration(minutes: 1);
    if (!force && _statusFor == uid && fresh && _status != null) {
      return _status!;
    }
    final raw = await _db.rpc('my_moderation_status');
    _status = ModerationStatus.fromJson(Map<String, dynamic>.from(raw as Map));
    _statusFor = uid;
    _statusAt = DateTime.now();
    return _status!;
  }

  static void invalidateStatus() => _statusAt = null;

  static Future<String> submitAppeal(
      {String? caseId, String? restrictionId, required String message}) async {
    final id = await _db.rpc('submit_appeal', params: {
      'p_case_id': caseId,
      'p_restriction_id': restrictionId,
      'p_message': message,
    });
    invalidateStatus();
    return '$id';
  }

  // ------------------------------------------------------------- reports
  static Future<ReportOutcome> report({
    required String targetId,
    required String targetType,
    required String category,
    required String reason,
  }) async {
    final uid = _uid;
    if (uid == null) return const ReportOutcome(ReportResult.failed);
    try {
      await _db.from('reports').insert({
        'reporter_id': uid,
        'target_id': targetId,
        'target_type': targetType,
        'category': category,
        'reason': reason,
      });
      return const ReportOutcome(ReportResult.received);
    } catch (e) {
      final m = parseModError(e);
      return switch (m?.code) {
        'duplicate_report' => const ReportOutcome(ReportResult.duplicate),
        'self_report' => const ReportOutcome(ReportResult.ownContent),
        'target_missing' => const ReportOutcome(ReportResult.missing),
        'restricted' => ReportOutcome(ReportResult.restricted, error: m),
        _ => const ReportOutcome(ReportResult.failed),
      };
    }
  }

  // ------------------------------------------------------------- pins
  static Future<Map<String, dynamic>> pin(String postId, {bool replace = false}) async {
    final r = await _db.rpc('pin_post', params: {'p_post_id': postId, 'p_replace': replace});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> unpin(String postId) =>
      _db.rpc('unpin_post', params: {'p_post_id': postId});

  // ------------------------------------------------------------- admin: cases
  static Future<Map<String, dynamic>> queueSummary() async =>
      Map<String, dynamic>.from(await _db.rpc('admin_queue_summary') as Map);

  /// [status]: 'active' (open + hidden), a single status, or null for all.
  static Future<List<Map<String, dynamic>>> cases({
    String? status = 'active',
    String? type,
    String? category,
    int limit = 100,
  }) async {
    var q = _db.from('moderation_queue').select();
    if (status == 'active') {
      q = q.inFilter('status', ['open', 'hidden']);
    } else if (status == 'resolved') {
      q = q.inFilter('status', ['actioned', 'dismissed', 'closed']);
    } else if (status != null) {
      q = q.eq('status', status);
    }
    if (type != null) q = q.eq('target_type', type);
    if (category != null) q = q.contains('categories', [category]);

    final rows = await (status == 'active'
        ? q.order('priority').order('first_reported_at', ascending: true).limit(limit)
        : q.order('last_reported_at').limit(limit));
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Map<String, dynamic>> resolveCase(
      String caseId, String decision, String reason) async {
    final r = await _db.rpc('admin_resolve_case',
        params: {'p_case_id': caseId, 'p_decision': decision, 'p_reason': reason});
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<void> undoCase(String caseId) =>
      _db.rpc('admin_undo_case', params: {'p_case_id': caseId});

  static Future<int> bulkResolve(List<String> caseIds, String decision, String reason) async {
    final n = await _db.rpc('admin_bulk_resolve',
        params: {'p_case_ids': caseIds, 'p_decision': decision, 'p_reason': reason});
    return (n as num).toInt();
  }

  /// Unmasks an anonymous post/comment author. Logged with [reason].
  static Future<Map<String, dynamic>?> unmask(
      String targetType, String targetId, String reason) async {
    final rows = await _db.rpc('admin_unmask', params: {
      'p_target_type': targetType,
      'p_target_id': targetId,
      'p_reason': reason,
    });
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : list.first;
  }

  // ------------------------------------------------------------- admin: restrictions
  /// Either [userId] or [caseId] (to act on an anonymous author).
  static Future<List<String>> restrict({
    String? userId,
    String? caseId,
    required Set<ModScope> scopes,
    required Duration? duration,
    required String reason,
  }) async {
    final until = duration == null ? null : DateTime.now().toUtc().add(duration);
    final ids = await _db.rpc('admin_restrict_user', params: {
      'p_user_id': userId,
      'p_case_id': caseId,
      'p_scopes': scopes.map((s) => s.db).toList(),
      'p_until': until?.toIso8601String(),
      'p_reason': reason,
    });
    return List<String>.from((ids as List).map((e) => '$e'));
  }

  static Future<List<Map<String, dynamic>>> restrictions({bool activeOnly = true}) async {
    var q = _db.from('moderation_restrictions').select();
    if (activeOnly) q = q.eq('active', true);
    return List<Map<String, dynamic>>.from(
        await q.order('created_at').limit(200));
  }

  static Future<void> liftRestriction(String id, String reason) =>
      _db.rpc('admin_lift_restriction', params: {'p_id': id, 'p_reason': reason});

  static Future<void> reinstateRestriction(String id) =>
      _db.rpc('admin_reinstate_restriction', params: {'p_id': id});

  /// Resolves a username for "restrict a user" from the Restrictions tab.
  static Future<Map<String, dynamic>?> findUser(String username) async {
    final name = username.trim().replaceFirst('@', '');
    if (name.isEmpty) return null;
    return _db
        .from('profiles')
        .select('id, username, display_name, avatar_url, role')
        .ilike('username', name)
        .maybeSingle();
  }

  // ------------------------------------------------------------- admin: clubs, appeals
  static Future<List<Map<String, dynamic>>> clubRequests() async =>
      List<Map<String, dynamic>>.from(await _db.rpc('admin_club_requests') as List);

  static Future<void> decideClub(String userId, bool approve, String? reason) =>
      _db.rpc('admin_decide_club',
          params: {'p_user_id': userId, 'p_approve': approve, 'p_reason': reason});

  static Future<List<Map<String, dynamic>>> appeals({bool pendingOnly = true}) async {
    var q = _db.from('moderation_appeals').select();
    if (pendingOnly) q = q.eq('status', 'pending');
    return List<Map<String, dynamic>>.from(
        await q.order('created_at', ascending: pendingOnly).limit(200));
  }

  static Future<void> handleAppeal(String id, bool accept, String note) =>
      _db.rpc('admin_handle_appeal',
          params: {'p_appeal_id': id, 'p_accept': accept, 'p_note': note});

  // ------------------------------------------------------------- admin: log, settings
  static Future<List<Map<String, dynamic>>> log({
    String? action,
    String? actor,
    int limit = 500,
  }) async {
    var q = _db.from('moderation_log').select();
    if (action != null && action.isNotEmpty) q = q.ilike('action', '%$action%');
    if (actor != null) q = q.eq('actor', actor);
    return List<Map<String, dynamic>>.from(await q.order('created_at').limit(limit));
  }

  static Future<Map<String, dynamic>> settings() async =>
      Map<String, dynamic>.from(
          await _db.from('moderation_settings').select().eq('id', true).single());

  /// Owner only (RLS). Returns false when no row was updated, which is
  /// what RLS does to a non-owner instead of raising.
  static Future<bool> saveSettings(Map<String, dynamic> values) async {
    final rows = await _db
        .from('moderation_settings')
        .update(values)
        .eq('id', true)
        .select('id');
    return (rows as List).isNotEmpty;
  }
}

class ModerationStatus {
  final List<Restriction> restrictions;
  final List<Map<String, dynamic>> cases;
  final bool banned;

  const ModerationStatus(
      {required this.restrictions, required this.cases, required this.banned});

  static const empty = ModerationStatus(restrictions: [], cases: [], banned: false);

  factory ModerationStatus.fromJson(Map<String, dynamic> j) => ModerationStatus(
        restrictions: ((j['restrictions'] as List?) ?? const [])
            .map((e) => Restriction.fromJson(Map<String, dynamic>.from(e as Map)))
            .whereType<Restriction>()
            .toList(),
        cases: ((j['cases'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        banned: j['banned'] == true,
      );

  /// What stops [scope] now. A legacy `is_banned` flag without a
  /// restriction row reads as a permanent account restriction.
  Restriction? blocking(ModScope scope) {
    final r = blockingRestriction(restrictions, scope, DateTime.now());
    if (r != null || !banned) return r;
    return const Restriction(id: '', scope: ModScope.account, until: null, reason: '');
  }

  bool get clean => restrictions.isEmpty && cases.isEmpty && !banned;
}

enum ReportResult { received, duplicate, ownContent, missing, restricted, failed }

class ReportOutcome {
  final ReportResult result;
  final ModError? error;
  const ReportOutcome(this.result, {this.error});
}
