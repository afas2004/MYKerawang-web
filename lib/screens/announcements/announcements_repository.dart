import 'package:supabase_flutter/supabase_flutter.dart';

/// `posts.announcement_category` values, in tab order.
enum AnnouncementCategory {
  kolej('kolej'),
  jpk('jpk'),
  club('club'),
  event('event'),
  general('general');

  final String dbValue;
  const AnnouncementCategory(this.dbValue);

  static AnnouncementCategory fromDb(String? v) => values.firstWhere(
        (c) => c.dbValue == v,
        orElse: () => AnnouncementCategory.general,
      );
}

/// A call-to-action link on an announcement (`action_links`, max 2).
///
/// Either an external web link ([url], opened in the browser) or an
/// in-app path ([path], e.g. `/event/<id>`, `/c/<handle>`,
/// `/clubs/register`, opened with `context.push`).
class AnnouncementLink {
  final String label;

  /// External http(s) link; null for an in-app path.
  final Uri? url;

  /// In-app route path; null for an external link.
  final String? path;

  const AnnouncementLink.external(this.label, Uri this.url) : path = null;
  const AnnouncementLink.internal(this.label, String this.path) : url = null;

  bool get isInternal => path != null;

  /// A same-app path: one leading '/', not '//' (protocol-relative URL)
  /// and no backslashes (some browsers treat '/\' like '//').
  static bool isAppPath(String v) =>
      v.startsWith('/') && !v.startsWith('//') && !v.contains(r'\');

  /// Keeps labelled http(s) links and in-app paths; max two.
  static List<AnnouncementLink> parse(dynamic raw) {
    if (raw is! List) return const [];
    final out = <AnnouncementLink>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final label = (e['label'] ?? '').toString().trim();
      final value = (e['url'] ?? '').toString().trim();
      if (label.isEmpty || value.isEmpty) continue;
      if (isAppPath(value)) {
        out.add(AnnouncementLink.internal(label, value));
      } else {
        final uri = Uri.tryParse(value);
        if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
          continue;
        }
        out.add(AnnouncementLink.external(label, uri));
      }
      if (out.length == 2) break;
    }
    return out;
  }
}

/// Who an announcement is from: a club (posts_public.club) or, for
/// kolej/JPK/general notices, the author's profile.
class AnnouncementChannel {
  /// `club:<id>` or `user:<id>`: stable key for the chip filter.
  final String key;
  final String name;
  final String? avatarUrl;
  final bool verified;
  final bool isClub;

  /// Club handle (for /c/:handle) or user id (for /u/:id).
  final String ref;

  const AnnouncementChannel({
    required this.key,
    required this.name,
    required this.avatarUrl,
    required this.verified,
    required this.isClub,
    required this.ref,
  });
}

/// One announcement row, parsed from posts_public.
class Announcement {
  /// The posts_public row (the shape goPost expects).
  final Map<String, dynamic> post;
  final AnnouncementCategory category;
  final AnnouncementChannel? channel;
  final List<AnnouncementLink> links;
  final DateTime publishedAt;

  /// Featured in the hero (feature_until in the future).
  final bool featured;

  const Announcement({
    required this.post,
    required this.category,
    required this.channel,
    required this.links,
    required this.publishedAt,
    required this.featured,
  });

  factory Announcement.fromRow(Map<String, dynamic> row, {DateTime? now}) {
    final t = now ?? DateTime.now();
    DateTime? ts(String k) => DateTime.tryParse(row[k]?.toString() ?? '')?.toLocal();

    AnnouncementChannel? channel;
    final club = row['club'];
    final profile = row['profiles'];
    if (club is Map && club['id'] != null) {
      channel = AnnouncementChannel(
        key: 'club:${club['id']}',
        name: (club['name'] ?? '').toString(),
        avatarUrl: club['logo_url'] as String?,
        verified: club['is_verified'] == true,
        isClub: true,
        ref: (club['handle'] ?? club['id']).toString(),
      );
    } else if (profile is Map && profile['id'] != null) {
      channel = AnnouncementChannel(
        key: 'user:${profile['id']}',
        name: (profile['display_name'] ?? profile['username'] ?? '').toString(),
        avatarUrl: profile['avatar_url'] as String?,
        verified: profile['is_verified'] == true,
        isClub: false,
        ref: profile['id'].toString(),
      );
    }

    final featureUntil = ts('feature_until');
    return Announcement(
      post: row,
      category: AnnouncementCategory.fromDb(row['announcement_category'] as String?),
      channel: channel,
      links: AnnouncementLink.parse(row['action_links']),
      publishedAt: ts('publish_at') ??
          ts('created_at') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      featured: featureUntil != null && featureUntil.isAfter(t),
    );
  }

  String get id => post['id'] as String;
  bool get clubPinned => post['is_club_pinned'] == true;
  String get title => (post['title'] as String?)?.trim() ?? '';
  String get body => (post['body'] as String?)?.trim() ?? '';

  /// 16:9 cover for the hero / card thumbnail: cover_url, else the post's
  /// first photo, else a shared event's / listing's cover. Null → the UI
  /// draws a tinted category card.
  String? get coverUrl {
    String? str(dynamic v) => v is String && v.isNotEmpty ? v : null;
    String? img(dynamic m) => m is Map ? str(m['image_url']) : null;
    final gallery = post['gallery_urls'];
    return str(post['cover_url']) ??
        img(post) ??
        (gallery is List && gallery.isNotEmpty ? str(gallery.first) : null) ??
        img(post['events']) ??
        img(post['listings']);
  }
}

/// Everything the hub shows, loaded together.
class AnnouncementsData {
  /// Newest first.
  final List<Announcement> items;

  /// Upcoming events from clubs / announcement authors.
  final List<Map<String, dynamic>> upcomingEvents;

  /// True when there are no flagged announcements yet and [items] are
  /// legacy posts from official authors (pre-v1.4 data).
  final bool legacy;

  const AnnouncementsData({
    required this.items,
    required this.upcomingEvents,
    this.legacy = false,
  });

  static const empty = AnnouncementsData(items: [], upcomingEvents: []);

  /// Hero: featured (feature_until > now), else newest 3. Pins aren't news:
  /// they live in Home's pin bar.
  List<Announcement> get featured {
    final f = items.where((a) => a.featured).toList();
    if (f.isNotEmpty) return f.take(5).toList();
    return items.take(3).toList();
  }

  /// Channel chips: clubs first, then admin / staff authors, each once,
  /// in order of their latest announcement.
  List<AnnouncementChannel> get channels {
    final seen = <String>{};
    final clubs = <AnnouncementChannel>[];
    final people = <AnnouncementChannel>[];
    for (final a in items) {
      final c = a.channel;
      if (c == null || !seen.add(c.key)) continue;
      (c.isClub ? clubs : people).add(c);
    }
    return [...clubs, ...people];
  }

  /// Orders rows: newest published first.
  static List<Announcement> sorted(Iterable<Announcement> items) =>
      items.toList()
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
}

/// Can the signed-in user post announcements? Asks the
/// `can_post_announcement()` RPC; any failure (guest, RPC missing) → no.
Future<bool> canPostAnnouncement({SupabaseClient? client}) async {
  try {
    final db = client ?? Supabase.instance.client;
    if (db.auth.currentSession == null) return false;
    final res = await db.rpc('can_post_announcement');
    final row = res is List ? (res.isEmpty ? null : res.first) : res;
    if (row is Map) return row['allowed'] == true;
    return res == true;
  } catch (_) {
    return false;
  }
}

/// Reads the Announcements hub from `posts_public` where
/// `is_announcement = true`. The view hides scheduled (future
/// `publish_at`) rows from everyone but their authors, and still applies
/// anonymity and moderation hiding. All of it is guest-readable.
///
/// Fallback: until anything is flagged as an announcement, the hub shows
/// recent posts from official authors (clubs, admins, verified) so it
/// isn't empty right after the upgrade. Those are categorised as Kolej /
/// Club by author.
class AnnouncementsRepository {
  final SupabaseClient? _client;

  AnnouncementsRepository({SupabaseClient? client}) : _client = client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  Future<AnnouncementsData> load() async {
    final rows = await _db
        .from('posts_public')
        .select('*')
        .eq('is_announcement', true)
        .order('created_at', ascending: false)
        .limit(80);
    final seen = {for (final r in rows) r['id']};

    var items = AnnouncementsData.sorted([
      for (final r in rows) Announcement.fromRow(r),
      for (final r in await _clubPins())
        if (!seen.contains(r['id'])) Announcement.fromRow(r),
    ]);
    var legacy = false;
    if (items.isEmpty) {
      items = await _legacy();
      legacy = items.isNotEmpty;
    }

    return AnnouncementsData(
      items: items,
      upcomingEvents: await _upcomingEvents(items),
      legacy: legacy,
    );
  }

  /// Club pins older than the newest 80 still lead their club's chip.
  Future<List<Map<String, dynamic>>> _clubPins() async {
    try {
      return List<Map<String, dynamic>>.from(await _db
          .from('posts_public')
          .select('*')
          .eq('is_announcement', true)
          .eq('is_club_pinned', true)
          .limit(20));
    } catch (_) {
      return const []; // only the order under a chip depends on it
    }
  }

  /// Pre-v1.4: official authors' recent posts.
  Future<List<Announcement>> _legacy() async {
    final people = await _db
        .from('profiles_public')
        .select('id, role')
        .or('role.in.(club,admin,owner),is_verified.eq.true')
        .limit(60);
    if (people.isEmpty) return const [];
    final roles = {for (final p in people) p['id'] as String: p['role']};
    final rows = await _db
        .from('posts_public')
        .select('*')
        .inFilter('user_id', roles.keys.toList())
        .order('created_at', ascending: false)
        .limit(40);
    return AnnouncementsData.sorted([
      for (final r in rows)
        Announcement.fromRow({
          ...r,
          'announcement_category':
              r['club'] != null || roles[r['user_id']] == 'club' ? 'club' : 'kolej',
        }),
    ]);
  }

  /// Upcoming, visible events by clubs or by announcement authors.
  Future<List<Map<String, dynamic>>> _upcomingEvents(
      List<Announcement> items) async {
    final authors = {
      for (final a in items)
        if (a.post['user_id'] != null) a.post['user_id'] as String
    };
    final who = authors.isEmpty
        ? 'club_id.not.is.null'
        : 'club_id.not.is.null,organizer_id.in.(${authors.join(',')})';
    try {
      final rows = await _db
          .from('events')
          .select()
          .or(who)
          .eq('is_hidden', false)
          .isFilter('cancelled_at', null)
          .gt('end_datetime', DateTime.now().toUtc().toIso8601String())
          .order('start_datetime', ascending: true)
          .limit(10);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return const []; // the strip is optional
    }
  }
}
