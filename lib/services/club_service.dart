import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/filter_rules.dart';

/// Clubs: pages run by student officers (supabase/migrations/20261022002*).
/// The database decides who may do what (can_act_as_club, RPC checks);
/// this file calls it, holds the models and the small pure rules the UI
/// uses to explain itself before a round trip.

// ---------------------------------------------------------------- models
class Club {
  final String id;
  final String handle;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String? category;
  final String? faculty;
  final String? contactEmail;
  final Map<String, String> socials;
  final bool isVerified;

  /// President-controlled: whether the club takes join requests at all.
  final bool recruitmentOpen;
  final String status; // pending | active | rejected | suspended
  final DateTime? createdAt;

  const Club({
    required this.id,
    required this.handle,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.category,
    this.faculty,
    this.contactEmail,
    this.socials = const {},
    this.isVerified = false,
    this.recruitmentOpen = true,
    this.status = 'active',
    this.createdAt,
  });

  bool get isActive => status == 'active';

  factory Club.fromJson(Map<String, dynamic> j) => Club(
        id: '${j['id']}',
        handle: '${j['handle'] ?? ''}',
        name: '${j['name'] ?? ''}',
        description: j['description'] as String?,
        logoUrl: j['logo_url'] as String?,
        coverUrl: j['cover_url'] as String?,
        category: j['category'] as String?,
        faculty: j['faculty'] as String?,
        contactEmail: j['contact_email'] as String?,
        socials: {
          for (final e in ((j['socials'] as Map?) ?? const {}).entries)
            if ('${e.value}'.trim().isNotEmpty) '${e.key}': '${e.value}',
        },
        isVerified: j['is_verified'] == true,
        // Defaults open, so an older row or a partial select still behaves
        // like every club did before the switch existed.
        recruitmentOpen: j['recruitment_open'] != false,
        status: '${j['status'] ?? 'active'}',
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

/// A club's private contact for its listings (20261023001100): the phone
/// and payment QR buyers get from `get_listing_contact` when they ask.
/// Officers and admins only — RLS on `club_private` enforces it.
class ClubContact {
  final String? phone;
  final String? paymentQrUrl;

  const ClubContact({this.phone, this.paymentQrUrl});

  static const empty = ClubContact();
}

class ClubMember {
  final String userId;
  final String role; // president | officer | member
  final String? position; // display title: secretary, treasurer, …
  final DateTime? joinedAt;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  const ClubMember({
    required this.userId,
    required this.role,
    this.position,
    this.joinedAt,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  bool get isOfficer => role == 'president' || role == 'officer';
  String get name => (displayName?.trim().isNotEmpty ?? false) ? displayName! : (username ?? '');
}

/// One recognised club from the admin-maintained registry
/// (supabase/migrations/20261024002100). Registration is select-only
/// against these entries.
class ClubRegistryEntry {
  final String id;
  final String code;
  final String name;
  final String? faculty;
  final String? category;
  final bool isActive;
  final String? clubId;
  final String? clubHandle;
  final String? clubStatus;

  const ClubRegistryEntry({
    required this.id,
    required this.code,
    required this.name,
    this.faculty,
    this.category,
    this.isActive = true,
    this.clubId,
    this.clubHandle,
    this.clubStatus,
  });

  bool get claimed => clubId != null;

  factory ClubRegistryEntry.fromJson(Map<String, dynamic> j) => ClubRegistryEntry(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        faculty: j['faculty'] as String?,
        category: j['category'] as String?,
        isActive: j['is_active'] != false,
        clubId: j['club_id'] == null ? null : '${j['club_id']}',
        clubHandle: j['club_handle'] as String?,
        clubStatus: j['club_status'] as String?,
      );
}

/// Positions the registration form and the roster know about.
const clubPositions = [
  'president',
  'vice_president',
  'secretary',
  'treasurer',
  'committee',
  'other',
];

/// What the club page needs to know about the viewer: already a member, or
/// a join request is waiting.
class ClubJoinState {
  final bool member;
  final bool pending;

  const ClubJoinState({this.member = false, this.pending = false});

  static const none = ClubJoinState();

  factory ClubJoinState.fromJson(Map<String, dynamic> j) => ClubJoinState(
        member: j['member'] == true,
        pending: j['pending'] == true,
      );
}

/// One entry of the "Post as" choice: yourself (clubId null) or a club
/// you are an officer of.
class PostAsOption {
  final String? clubId;
  final String label;
  final String? handle;
  final String? avatarUrl;
  final bool verified;

  const PostAsOption.self(this.label, {this.avatarUrl})
      : clubId = null,
        handle = null,
        verified = false;

  const PostAsOption.club({
    required String this.clubId,
    required this.label,
    required String this.handle,
    this.avatarUrl,
    this.verified = false,
  });

  bool get isClub => clubId != null;

  /// Adds/clears `club_id` on a row about to be inserted into posts,
  /// events or listings. RLS rejects it unless you're an officer.
  /// Pass `hasAnonymous: false` for tables without is_anonymous (events,
  /// listings).
  Map<String, dynamic> applyTo(Map<String, dynamic> row, {bool hasAnonymous = true}) =>
      {...row, 'club_id': clubId, if (isClub && hasAnonymous) 'is_anonymous': false};
}

/// What the caller may announce (can_post_announcement(), 20261023001100).
class AnnouncementAbility {
  final bool allowed;
  final List<String> categories; // kolej, jpk, club, event, general
  final List<Map<String, dynamic>> clubs; // {id, name, handle, logo_url}

  const AnnouncementAbility({required this.allowed, this.categories = const [], this.clubs = const []});

  static const none = AnnouncementAbility(allowed: false);

  factory AnnouncementAbility.fromJson(Map<String, dynamic> j) => AnnouncementAbility(
        allowed: j['allowed'] == true,
        categories: List<String>.from((j['categories'] as List?) ?? const []),
        clubs: [for (final c in (j['clubs'] as List?) ?? const []) Map<String, dynamic>.from(c as Map)],
      );
}

// ---------------------------------------------------------------- pure rules
enum HandleIssue { empty, tooShort, tooLong, badChars }

final _handleChars = RegExp(r'^[A-Za-z0-9_]+$');

/// Mirrors the DB check `^[A-Za-z0-9_]{3,30}$`.
HandleIssue? validateHandle(String raw) {
  final h = raw.trim();
  if (h.isEmpty) return HandleIssue.empty;
  if (!_handleChars.hasMatch(h)) return HandleIssue.badChars;
  if (h.length < 3) return HandleIssue.tooShort;
  if (h.length > 30) return HandleIssue.tooLong;
  return null;
}

/// A handle suggestion from a club name: "Debate Society UiTM" →
/// "DebateSocietyUiTM" (kept readable, trimmed to 30).
String suggestHandle(String name) {
  final words = name
      .replaceAll(RegExp(r'[^A-Za-z0-9 _]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  final joined = words.map((w) => w[0].toUpperCase() + w.substring(1)).join();
  return joined.length > 30 ? joined.substring(0, 30) : joined;
}

/// Mirrors register_club's page-handle derivation from the official code
/// (before the uniqueness suffix). Pure, for the registration preview.
String registryHandlePreview(String code, String name) {
  final base = code.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  final cut = base.length > 24 ? base.substring(0, 24) : base;
  if (cut.length < 3) return suggestHandle(name);
  return cut;
}

/// President first, then officers, then members; each by join date.
List<ClubMember> sortMembers(Iterable<ClubMember> members) {  int rank(String r) => switch (r) { 'president' => 0, 'officer' => 1, _ => 2 };
  final list = [...members];
  list.sort((a, b) {
    final r = rank(a.role).compareTo(rank(b.role));
    if (r != 0) return r;
    return (a.joinedAt ?? DateTime(0)).compareTo(b.joinedAt ?? DateTime(0));
  });
  return list;
}

bool canManageClub(String? myRole) => myRole == 'president' || myRole == 'officer';
bool isPresident(String? myRole) => myRole == 'president';

/// `CLUB:<code>` from a failed call, e.g. `handle_taken`, or null.
String? clubErrorCode(Object? e) {
  final text = e is PostgrestException ? e.message : '$e';
  final m = RegExp(r'CLUB:([a-z_]+)').firstMatch(text);
  return m?.group(1);
}

/// Normalises "@Name " → "Name".
String cleanUsername(String raw) => raw.trim().replaceFirst(RegExp(r'^@+'), '');

/// One row for the search screen's Clubs section (title / subtitle /
/// avatar / route). Pure, so the shape can be tested without Supabase.
Map<String, dynamic> clubSearchRow(Club c) => {
      'title': c.name,
      'subtitle': '@${c.handle}',
      'avatar_url': c.logoUrl,
      'route': '/c/${c.handle}',
    };

/// Socials the page shows, in display order, from the edit form values.
Map<String, String> buildSocials({String? instagram, String? tiktok, String? website}) => {
      if ((instagram ?? '').trim().isNotEmpty) 'instagram': cleanUsername(instagram!),
      if ((tiktok ?? '').trim().isNotEmpty) 'tiktok': cleanUsername(tiktok!),
      if ((website ?? '').trim().isNotEmpty) 'website': website!.trim(),
    };

// ---------------------------------------------------------------- service
class ClubService {
  ClubService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Test hook: widget tests run without a Supabase instance.
  static String? Function()? debugCurrentUserId;
  static String? get currentUserId =>
      debugCurrentUserId != null ? debugCurrentUserId!() : _db.auth.currentUser?.id;

  static const _clubColumns =
      'id, handle, name, description, logo_url, cover_url, category, faculty, '
      'contact_email, socials, is_verified, status, created_at';

  // ---- reading
  static Future<Club?> byHandle(String handle) async {
    final row = await _db
        .from('clubs')
        .select(_clubColumns)
        .ilike('handle', handle.replaceAll('%', '').replaceAll('_', r'\_'))
        .maybeSingle();
    return row == null ? null : Club.fromJson(row);
  }

  static Future<List<Club>> directory({String? search, String? category, int limit = 200}) async {
    var q = _db.from('clubs').select(_clubColumns).eq('status', 'active');
    if (category != null) q = q.eq('category', category);
    // A `.or()` filter is a string, not a parameter: `,` and `()` would add
    // conditions. [filterSafe] removes the filter syntax, not the words.
    final s = search == null ? null : filterSafe(search);
    if (s != null && s.isNotEmpty) q = q.or('name.ilike.%$s%,handle.ilike.%$s%');
    final rows = await q.order('name').limit(limit);
    return [for (final r in rows) Club.fromJson(r)];
  }

  /// Search source for [SearchScreen.clubSource] (wired in main.dart).
  static Future<List<Map<String, dynamic>>> searchRows(String term, int limit) async {
    final clubs = await directory(search: term, limit: limit);
    return [for (final c in clubs) clubSearchRow(c)];
  }

  static Future<Map<String, int>> followerCounts(List<String> clubIds) async {
    if (clubIds.isEmpty) return {};
    final rows = await _db.from('club_follower_counts').select().inFilter('club_id', clubIds);
    return {for (final r in rows) '${r['club_id']}': (r['followers'] as num).toInt()};
  }

  static Future<List<ClubMember>> members(String clubId) async {
    final rows = await _db
        .from('club_members')
        .select('user_id, role, position, joined_at')
        .eq('club_id', clubId);
    final ids = [for (final r in rows) '${r['user_id']}'];
    final profiles = ids.isEmpty
        ? const <dynamic>[]
        : await _db
            .from('profiles_public')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', ids);
    final byId = {for (final p in profiles) '${p['id']}': p};
    return sortMembers([
      for (final r in rows)
        ClubMember(
          userId: '${r['user_id']}',
          role: '${r['role']}',
          position: r['position'] as String?,
          joinedAt: DateTime.tryParse('${r['joined_at']}'),
          username: byId['${r['user_id']}']?['username'] as String?,
          displayName: byId['${r['user_id']}']?['display_name'] as String?,
          avatarUrl: byId['${r['user_id']}']?['avatar_url'] as String?,
        ),
    ]);
  }

  /// The caller's role in [clubId] (null when none / signed out).
  static Future<String?> myRole(String clubId) async {
    if (currentUserId == null) return null;
    final r = await _db.rpc('club_role', params: {'p_club_id': clubId});
    return r as String?;
  }

  static Future<List<Map<String, dynamic>>> myClubs() async {
    if (currentUserId == null) return const [];
    return List<Map<String, dynamic>>.from(await _db.rpc('my_clubs') as List);
  }

  /// "Post as" choices: yourself, then every ACTIVE club you're an
  /// officer of. Pass [selfLabel] (e.g. your display name).
  static Future<List<PostAsOption>> postAsOptions(String selfLabel, {String? selfAvatar}) async {
    if (debugPostAsOptions != null) return debugPostAsOptions!();
    final clubs = await myClubs();
    return [
      PostAsOption.self(selfLabel, avatarUrl: selfAvatar),
      for (final c in clubs)
        if (c['status'] == 'active')
          PostAsOption.club(
            clubId: '${c['id']}',
            label: '${c['name']}',
            handle: '${c['handle']}',
            avatarUrl: c['logo_url'] as String?,
            verified: c['is_verified'] == true,
          ),
    ];
  }

  static String? _abilityFor;
  static Future<AnnouncementAbility>? _ability;

  /// Cached per signed-in user; the create sheet asks on every open.
  static Future<AnnouncementAbility> canPostAnnouncement({bool refresh = false}) {
    if (debugAnnouncementAbility != null) return debugAnnouncementAbility!();
    final uid = currentUserId;
    if (uid == null) return Future.value(AnnouncementAbility.none);
    if (refresh || _abilityFor != uid || _ability == null) {
      _abilityFor = uid;
      _ability = _db
          .rpc('can_post_announcement')
          .then((r) => AnnouncementAbility.fromJson(Map<String, dynamic>.from(r as Map)))
          .catchError((Object _) {
        _ability = null;
        return AnnouncementAbility.none;
      });
    }
    return _ability!;
  }

  /// Test hook for [postAsOptions].
  static Future<List<PostAsOption>> Function()? debugPostAsOptions;

  /// Test hook for [canPostAnnouncement].
  static Future<AnnouncementAbility> Function()? debugAnnouncementAbility;

  /// Club phone / payment QR used for club listings (officers only).
  static Future<void> setContact(String clubId, {String? phone, String? paymentQrUrl}) =>
      _db.rpc('set_club_contact',
          params: {'p_club_id': clubId, 'p_phone': phone, 'p_payment_qr_url': paymentQrUrl});

  /// The club's saved phone / payment QR (officers and admins; RLS on
  /// `club_private`). Empty when nothing is set yet.
  static Future<ClubContact> contact(String clubId) async {
    final row = await _db
        .from('club_private')
        .select('contact_phone, payment_qr_url')
        .eq('club_id', clubId)
        .maybeSingle();
    if (row == null) return ClubContact.empty;
    return ClubContact(
      phone: row['contact_phone'] as String?,
      paymentQrUrl: row['payment_qr_url'] as String?,
    );
  }

  // ---- club-page pins (one at a time; never global)
  static Future<Map<String, dynamic>> clubPin(String postId, {bool replace = false}) async =>
      Map<String, dynamic>.from(await _db.rpc('club_pin_post',
          params: {'p_post_id': postId, 'p_replace': replace}) as Map);

  static Future<void> clubUnpin(String postId) =>
      _db.rpc('club_unpin_post', params: {'p_post_id': postId});

  // ---- content of a club page
  static Future<List<Map<String, dynamic>>> posts(String clubId, {int limit = 30}) async =>
      List<Map<String, dynamic>>.from(await _db
          .from('posts_public')
          .select('*')
          .eq('club_id', clubId)
          .order('is_pinned')
          .order('created_at', ascending: false)
          .limit(limit));

  static Future<List<Map<String, dynamic>>> events(String clubId) async =>
      List<Map<String, dynamic>>.from(await _db
          .from('events')
          .select()
          .eq('club_id', clubId)
          .order('start_datetime', ascending: false)
          .limit(50));

  static Future<List<Map<String, dynamic>>> listings(String clubId) async =>
      List<Map<String, dynamic>>.from(await _db
          .from('listings')
          .select()
          .eq('club_id', clubId)
          .order('created_at', ascending: false)
          .limit(50));

  // ---- following
  static Future<bool> isFollowing(String clubId) async {
    final uid = currentUserId;
    if (uid == null) return false;
    final r = await _db
        .from('club_followers')
        .select('club_id')
        .eq('club_id', clubId)
        .eq('user_id', uid)
        .maybeSingle();
    return r != null;
  }

  static Future<void> setFollowing(String clubId, bool follow) async {
    final uid = currentUserId!;
    if (follow) {
      await _db.from('club_followers').upsert({'club_id': clubId, 'user_id': uid});
    } else {
      await _db.from('club_followers').delete().eq('club_id', clubId).eq('user_id', uid);
    }
  }

  // ---- joining
  /// Whether the viewer is a member and/or has a pending request.
  static Future<ClubJoinState> myJoin(String clubId) async {
    if (currentUserId == null) return ClubJoinState.none;
    return ClubJoinState.fromJson(
      Map<String, dynamic>.from(await _db.rpc('my_club_join', params: {'p_club_id': clubId}) as Map),
    );
  }

  static Future<void> applyToClub(String clubId, {String? message}) =>
      _db.rpc('apply_to_club', params: {'p_club_id': clubId, 'p_message': message});

  /// Pending requests for a club (officers and admins).
  static Future<List<Map<String, dynamic>>> joinRequests(String clubId) async =>
      List<Map<String, dynamic>>.from(
          await _db.rpc('club_join_requests', params: {'p_club_id': clubId}) as List);

  static Future<void> decideJoin(String requestId, bool approve, {String? note}) =>
      _db.rpc('decide_club_join_request',
          params: {'p_request_id': requestId, 'p_approve': approve, 'p_note': note});

  /// Pending requests across every club (admin console).
  static Future<List<Map<String, dynamic>>> adminJoinRequests() async =>
      List<Map<String, dynamic>>.from(await _db.rpc('admin_join_requests') as List);

  // ---- registration & management
  /// Select-only registration: the club name/ID come from the admin
  /// registry, so there is no name/handle to type. Returns the new club's
  /// id and derived handle.
  static Future<Map<String, dynamic>> register({
    required String registryId,
    required String officialEmail,
    required String position,
    List<Map<String, String>> council = const [],
    String? note,
  }) async =>
      Map<String, dynamic>.from(await _db.rpc('register_club', params: {
        'p_registry_id': registryId,
        'p_official_email': officialEmail.trim(),
        'p_position': position,
        'p_council': council,
        'p_proof_note': note,
      }) as Map);

  /// Active registry entries no club has claimed (the registration picker).
  static Future<List<ClubRegistryEntry>> registryOpen() async => [
        for (final r in (await _db.rpc('club_registry_open') as List))
          ClubRegistryEntry.fromJson(Map<String, dynamic>.from(r as Map)),
      ];

  // ---- admin: registry
  static Future<List<ClubRegistryEntry>> adminRegistry() async => [
        for (final r in (await _db.rpc('admin_club_registry') as List))
          ClubRegistryEntry.fromJson(Map<String, dynamic>.from(r as Map)),
      ];

  static Future<void> saveRegistry({
    String? id,
    required String code,
    required String name,
    String? faculty,
    String? category,
    bool active = true,
  }) =>
      _db.rpc('admin_save_club_registry', params: {
        'p_id': id,
        'p_code': code.trim(),
        'p_name': name.trim(),
        'p_faculty': faculty,
        'p_category': category,
        'p_active': active,
      });

  static Future<void> update(
    String clubId, {
    required String name,
    String? description,
    String? logoUrl,
    String? coverUrl,
    String? category,
    String? faculty,
    String? contactEmail,
    Map<String, String> socials = const {},
  }) =>
      _db.rpc('update_club', params: {
        'p_club_id': clubId,
        'p_name': name,
        'p_description': description,
        'p_logo_url': logoUrl,
        'p_cover_url': coverUrl,
        'p_category': category,
        'p_faculty': faculty,
        'p_contact_email': contactEmail,
        'p_socials': socials,
      });

  /// Adds a roster member (president only). [position] is a display title.
  static Future<String> addMember(String clubId, String username, {String? position}) async =>
      '${await _db.rpc('add_club_member', params: {
            'p_club_id': clubId,
            'p_username': cleanUsername(username),
            'p_position': position,
          })}';

  static Future<void> removeMember(String clubId, String userId) =>
      _db.rpc('remove_club_member', params: {'p_club_id': clubId, 'p_user_id': userId});

  static Future<void> setMemberPosition(String clubId, String userId, String? position) =>
      _db.rpc('set_club_member_position',
          params: {'p_club_id': clubId, 'p_user_id': userId, 'p_position': position});

  static Future<void> setMemberRole(String clubId, String userId, String role) =>
      _db.rpc('set_club_member_role',
          params: {'p_club_id': clubId, 'p_user_id': userId, 'p_role': role});

  static Future<void> transferPresidency(String clubId, String userId) =>
      _db.rpc('transfer_presidency', params: {'p_club_id': clubId, 'p_user_id': userId});

  /// President only (enforced by the RPC).
  static Future<void> setRecruitment(String clubId, bool open) =>
      _db.rpc('set_club_recruitment',
          params: {'p_club_id': clubId, 'p_open': open});

  // ---- admin
  static Future<List<Map<String, dynamic>>> pendingRequests() async =>
      List<Map<String, dynamic>>.from(await _db.rpc('admin_pending_clubs') as List);

  /// Every club in one status, for the admin console (RLS lets admins read
  /// all of them). Pending still goes through [pendingRequests], which also
  /// carries the proof and the president.
  static Future<List<Map<String, dynamic>>> adminClubs(String status) async =>
      List<Map<String, dynamic>>.from(await _db
          .from('clubs')
          .select('id, handle, name, description, category, logo_url, is_verified, status, created_at')
          .eq('status', status)
          .order('name')
          .limit(200));

  static Future<void> decideRequest(String clubId, bool approve, String? reason) =>
      _db.rpc('admin_decide_club_request',
          params: {'p_club_id': clubId, 'p_approve': approve, 'p_reason': reason});

  static Future<void> setStatus(String clubId, String status, String reason) =>
      _db.rpc('admin_set_club_status',
          params: {'p_club_id': clubId, 'p_status': status, 'p_reason': reason});
}
