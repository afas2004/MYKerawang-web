import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/announcement_rules.dart';
import 'club_service.dart';
import 'moderation_service.dart';
import 'post_service.dart';

/// Who may announce, and as what (from `can_post_announcement()`).
class AnnouncePermission {
  final bool allowed;
  final List<String> categories;

  /// Clubs you can announce as. Admins may also announce as themselves
  /// (kolej / JPK notices), shown as the "self" option.
  final List<PostAsOption> clubs;
  final bool isAdmin;

  const AnnouncePermission({
    required this.allowed,
    required this.categories,
    required this.clubs,
    this.isAdmin = false,
  });

  static const none =
      AnnouncePermission(allowed: false, categories: [], clubs: []);

  /// Parses the RPC result:
  /// `{allowed, categories[], clubs[{id,name,handle,logo_url}], is_admin?}`.
  factory AnnouncePermission.fromJson(Map<String, dynamic> j) {
    final cats = List<String>.from(j['categories'] ?? const [])
        .where(kAnnouncementCategories.contains)
        .toList();
    return AnnouncePermission(
      allowed: j['allowed'] == true,
      categories: cats,
      isAdmin: j['is_admin'] == true || cats.contains('kolej') || cats.contains('jpk'),
      clubs: [
        for (final c in (j['clubs'] as List? ?? const []))
          if (c is Map)
            PostAsOption.club(
              clubId: '${c['id']}',
              label: '${c['name']}',
              handle: '${c['handle']}',
              avatarUrl: c['logo_url'] as String?,
              verified: c['is_verified'] == true,
            ),
      ],
    );
  }
}

/// One announcement being written (the composer's state, saved as a
/// posts row with is_announcement = true).
class AnnouncementDraft {
  String? clubId;
  String? category;
  String title = '';
  String body = '';

  /// Cover (16:9) and extra photos: URLs (`String`) or picked LocalImages.
  final List<dynamic> cover = [];
  final List<dynamic> images = [];
  final List<ActionLink> actions = [];
  Map<String, dynamic>? linkedEvent;
  DateTime? publishAt; // null = now
  DateTime? featureUntil;
  bool commentsEnabled = true;
  bool showInFeed = true;

  AnnouncementDraft();

  /// Draft from an existing posts row (edit flow).
  factory AnnouncementDraft.fromPost(Map<String, dynamic> p) {
    final d = AnnouncementDraft()
      ..clubId = p['club_id'] as String?
      ..category = p['announcement_category'] as String?
      ..title = (p['title'] as String?) ?? ''
      ..body = (p['body'] as String?) ?? ''
      ..publishAt = DateTime.tryParse('${p['publish_at'] ?? ''}')?.toLocal()
      ..featureUntil = DateTime.tryParse('${p['feature_until'] ?? ''}')?.toLocal()
      ..commentsEnabled = p['comments_enabled'] != false
      ..showInFeed = p['show_in_feed'] != false;
    final cover = (p['cover_url'] ?? p['image_url']) as String?;
    if (cover != null && cover.isNotEmpty) d.cover.add(cover);
    d.images.addAll(List<String>.from(p['gallery_urls'] ?? const []));
    d.actions.addAll(ActionLink.listFrom(p['action_links']));
    final ev = p['linked_event'] ?? p['events'];
    if (ev is Map<String, dynamic>) d.linkedEvent = ev;
    if (p['linked_event_id'] != null && d.linkedEvent == null) {
      d.linkedEvent = {'id': p['linked_event_id']};
    }
    return d;
  }

  List<AnnouncementIssue> validate(List<String> allowed) => validateAnnouncement(
        title: title,
        body: body,
        category: category,
        allowedCategories: allowed,
        extraImages: images.length,
        actions: actions,
        publishAt: publishAt,
        featureUntil: featureUntil,
      );

  /// Columns for posts (after photos are uploaded).
  Map<String, dynamic> toRow({String? coverUrl, List<String> imageUrls = const []}) => {
        'is_announcement': true,
        'is_anonymous': false,
        'club_id': clubId,
        'announcement_category': category,
        'title': title.trim(),
        'body': body,
        'cover_url': coverUrl,
        // The hub and older cards read image_url; keep it as the cover.
        'image_url': coverUrl,
        'gallery_urls': imageUrls,
        'action_links': [for (final a in actions) a.toJson()],
        'linked_event_id': linkedEvent?['id'],
        'publish_at': (publishAt ?? DateTime.now()).toUtc().toIso8601String(),
        'feature_until': featureUntil?.toUtc().toIso8601String(),
        'comments_enabled': commentsEnabled,
        'show_in_feed': showInFeed,
      };
}

abstract final class AnnouncementService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Tests: skip the RPC.
  @visibleForTesting
  static Future<AnnouncePermission> Function()? debugPermission;

  /// What the signed-in user may announce. Uses `can_post_announcement()`;
  /// until that RPC exists, derives the same answer from the role and
  /// club memberships so the screen still works.
  static Future<AnnouncePermission> permission() async {
    if (debugPermission != null) return debugPermission!();
    try {
      final r = await _db.rpc('can_post_announcement');
      if (r is Map<String, dynamic>) return AnnouncePermission.fromJson(r);
      if (r is List && r.isNotEmpty && r.first is Map<String, dynamic>) {
        return AnnouncePermission.fromJson(r.first as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('can_post_announcement unavailable, deriving: $e');
    }
    final role = await ModerationService.myRole();
    final isAdmin = role == 'admin' || role == 'owner';
    final clubs = (await ClubService.postAsOptions('').catchError((_) => <PostAsOption>[]))
        .where((o) => o.isClub)
        .toList();
    if (!isAdmin && clubs.isEmpty) return AnnouncePermission.none;
    return AnnouncePermission(
      allowed: true,
      categories: isAdmin ? kAnnouncementCategories : kClubAnnouncementCategories,
      clubs: clubs,
      isAdmin: isAdmin,
    );
  }

  /// Uploads photos and inserts (or, with [editId], updates) the post.
  /// Returns the post id.
  static Future<String> save(AnnouncementDraft d, {String? editId}) async {
    final cover = await PostService.uploadPhotos(d.cover);
    final images = await PostService.uploadPhotos(d.images);
    final row = d.toRow(coverUrl: cover.firstOrNull, imageUrls: images);
    if (editId != null) {
      await _db.from('posts').update(row).eq('id', editId);
      return editId;
    }
    final inserted = await _db
        .from('posts')
        .insert({...row, 'user_id': _db.auth.currentUser!.id, 'tags': <String>[]})
        .select('id')
        .single();
    PostService.rememberMine(inserted['id']);
    return inserted['id'] as String;
  }

  /// Events the user (or their club) organises, newest first, for the
  /// "link an event" picker.
  static Future<List<Map<String, dynamic>>> linkableEvents({String? clubId}) async {
    final me = _db.auth.currentUser?.id;
    var q = _db.from('events').select('id, title, start_datetime, location, image_url');
    q = clubId != null ? q.eq('club_id', clubId) : q.eq('organizer_id', me ?? '');
    return List<Map<String, dynamic>>.from(
        await q.order('start_datetime', ascending: false).limit(30));
  }

  /// The event an announcement links to (detail page).
  static Future<Map<String, dynamic>?> event(String id) async {
    try {
      return await _db.from('events').select().eq('id', id).maybeSingle();
    } catch (_) {
      return null;
    }
  }
}
