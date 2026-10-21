import 'package:supabase_flutter/supabase_flutter.dart';

/// Announcement categories shown as tabs in the hub.
enum AnnouncementCategory { kolej, jpk, clubs, events }

/// One official post in the hub.
class Announcement {
  /// The posts_public row (shape PostCard / goPost expect).
  final Map<String, dynamic> post;

  /// The author's profiles_public row (role, is_verified, avatar…).
  final Map<String, dynamic> author;

  final AnnouncementCategory category;

  const Announcement({
    required this.post,
    required this.author,
    required this.category,
  });

  String get id => post['id'] as String;
  bool get pinned => post['is_pinned'] == true;
  DateTime get createdAt =>
      DateTime.tryParse(post['created_at']?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Photo for the hero / thumbnail: the post's own, else a shared
  /// event's or listing's cover.
  String? get imageUrl {
    String? pick(dynamic m) =>
        m is Map && (m['image_url'] as String?)?.isNotEmpty == true
            ? m['image_url'] as String
            : null;
    return pick(post) ?? pick(post['events']) ?? pick(post['listings']);
  }
}

/// Everything the hub shows, loaded together.
class AnnouncementsData {
  final List<Announcement> items;

  /// Official authors (verified clubs / admins), for the channel chips.
  final List<Map<String, dynamic>> channels;

  /// Upcoming events organised by official authors.
  final List<Map<String, dynamic>> upcomingEvents;

  const AnnouncementsData({
    required this.items,
    required this.channels,
    required this.upcomingEvents,
  });

  static const empty =
      AnnouncementsData(items: [], channels: [], upcomingEvents: []);

  /// Pinned first (newest pin first), else the newest few, for the hero.
  List<Announcement> get featured {
    final pinned = items.where((a) => a.pinned).toList();
    if (pinned.isNotEmpty) return pinned.take(5).toList();
    return items.take(3).toList();
  }
}

/// Reads the Announcements hub.
///
/// **Today:** an announcement is any post (from `posts_public`, so
/// anonymity and moderation hiding still apply) whose author is official —
/// role club / admin / owner, or verified. The category is inferred
/// ([categorize]). Everything read here is readable by guests
/// (posts_public, profiles_public, public events).
///
/// **Later:** when posts gain `club_id` / `is_announcement` /
/// `announcement_category` (clubs work), replace [load]'s post query with
/// `.eq('is_announcement', true)` and [categorize] with the stored
/// category. The screen only depends on [AnnouncementsData].
class AnnouncementsRepository {
  final SupabaseClient? _client;

  AnnouncementsRepository({SupabaseClient? client}) : _client = client;

  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static const officialRoles = ['club', 'admin', 'owner'];

  static bool isOfficial(Map<String, dynamic>? profile) =>
      profile != null &&
      (officialRoles.contains(profile['role']) || profile['is_verified'] == true);

  /// Best guess until posts carry an explicit category:
  ///  * tagged #jpk → JPK
  ///  * shares an event, or tagged #event / #acara → Events
  ///  * written by a club → Clubs
  ///  * otherwise (admins, owner, verified staff) → Kolej
  static AnnouncementCategory categorize(
      Map<String, dynamic> post, Map<String, dynamic>? author) {
    final tags = [
      for (final t in (post['tags'] as List?) ?? const []) t.toString().toLowerCase()
    ];
    if (tags.contains('jpk')) return AnnouncementCategory.jpk;
    if (post['events'] != null ||
        tags.contains('event') ||
        tags.contains('events') ||
        tags.contains('acara')) {
      return AnnouncementCategory.events;
    }
    if (author?['role'] == 'club') return AnnouncementCategory.clubs;
    return AnnouncementCategory.kolej;
  }

  Future<AnnouncementsData> load() async {
    final channelRows = await _db
        .from('profiles_public')
        .select('id, username, display_name, avatar_url, role, is_verified')
        .or('role.in.(${officialRoles.join(',')}),is_verified.eq.true')
        .limit(60);
    final channels = List<Map<String, dynamic>>.from(channelRows);
    if (channels.isEmpty) return AnnouncementsData.empty;

    final byId = {for (final c in channels) c['id'] as String: c};
    final ids = byId.keys.toList();
    final now = DateTime.now().toUtc().toIso8601String();

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _db
          .from('posts_public')
          .select('*')
          .inFilter('user_id', ids)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(60),
      _db
          .from('events')
          .select()
          .inFilter('organizer_id', ids)
          .eq('is_hidden', false)
          .isFilter('cancelled_at', null)
          .gt('end_datetime', now)
          .order('start_datetime', ascending: true)
          .limit(10),
    ]);

    final items = [
      for (final p in results[0])
        Announcement(
          post: p,
          author: byId[p['user_id']] ?? const {},
          category: categorize(p, byId[p['user_id']]),
        ),
    ];

    // Channels with recent posts first, so the chip row leads with activity.
    final active = {for (final a in items) a.author['id']};
    channels.sort((a, b) {
      final aa = active.contains(a['id']) ? 0 : 1;
      final bb = active.contains(b['id']) ? 0 : 1;
      return aa != bb
          ? aa - bb
          : (a['display_name'] ?? '').toString().compareTo(
              (b['display_name'] ?? '').toString());
    });

    return AnnouncementsData(
      items: items,
      channels: channels,
      upcomingEvents: results[1],
    );
  }
}
