import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/image_compressor.dart';
import '../utils/local_image.dart';

/// Something changed about one post: either [deleted], or [patch] holds
/// the new column values (title, body, tags, image_url, gallery_urls).
class PostChange {
  final String postId;
  final Map<String, dynamic>? patch;
  final bool deleted;

  const PostChange.updated(this.postId, Map<String, dynamic> this.patch)
      : deleted = false;
  const PostChange.deleted(this.postId)
      : patch = null,
        deleted = true;
}

/// Author-side operations on posts and comments.
///
/// Anonymous rows come from posts_public / comments_public with user_id
/// blanked, so "is this mine?" is asked of security-definer RPCs that
/// only answer about the caller's own rows (migration 20261019001100).
class PostService {
  PostService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _myId => _db.auth.currentUser?.id;

  /// Max photos on one post.
  static const maxPhotos = 4;

  // ---------------------------------------------------------- changes

  static final _changes = StreamController<PostChange>.broadcast();

  /// Edits and deletions made on this device, so every card showing the
  /// post (feed, profile, detail) can update without a refetch.
  static Stream<PostChange> get changes => _changes.stream;

  // ---------------------------------------------------------- ownership

  static String? _cacheOwner;
  static Future<Set<String>>? _myPostIds;

  /// Ids of the signed-in user's posts, anonymous ones included.
  /// Fetched once per user and kept current by [rememberMine]/[deletePost].
  static Future<Set<String>> myPostIds() {
    final me = _myId;
    if (me == null) return Future.value(<String>{});
    if (_cacheOwner != me || _myPostIds == null) {
      _cacheOwner = me;
      _myPostIds = _fetchMyPostIds();
    }
    return _myPostIds!;
  }

  static Future<Set<String>> _fetchMyPostIds() async {
    try {
      final rows = await _db.rpc('my_post_ids') as List;
      return rows.map((id) => id.toString()).toSet();
    } catch (e) {
      debugPrint("my_post_ids failed: $e");
      _myPostIds = null; // retry next time
      return <String>{};
    }
  }

  /// Synchronous answer when the post isn't anonymous; null means "ask
  /// [isMine]".
  static bool? isMineSync(Map<String, dynamic> post) {
    final me = _myId;
    if (me == null) return false;
    if (post['user_id'] != null) return post['user_id'] == me;
    if (post['is_anonymous'] != true) return false;
    return null;
  }

  static Future<bool> isMine(Map<String, dynamic> post) async =>
      isMineSync(post) ?? (await myPostIds()).contains(post['id']);

  /// Call after creating a post so its menu shows without a refetch.
  static void rememberMine(String postId) =>
      _myPostIds?.then((ids) => ids.add(postId));

  /// Ids of the signed-in user's comments on [postId].
  static Future<Set<String>> myCommentIds(String postId) async {
    if (_myId == null) return {};
    try {
      final rows = await _db
          .rpc('my_comment_ids', params: {'p_post_id': postId}) as List;
      return rows.map((id) => id.toString()).toSet();
    } catch (e) {
      debugPrint("my_comment_ids failed: $e");
      return {};
    }
  }

  // ---------------------------------------------------------- posts

  static Future<void> updatePost(
    String postId, {
    required String? title,
    required String body,
    required List<String> tags,
    required List<String> photoUrls,
    List<String> removedPhotoUrls = const [],
  }) async {
    final patch = {
      'title': title,
      'body': body,
      'tags': tags,
      'image_url': photoUrls.firstOrNull,
      'gallery_urls': photoUrls.skip(1).toList(),
    };
    await _db.rpc('update_my_post', params: {
      'p_post_id': postId,
      'p_title': title,
      'p_body': body,
      'p_tags': tags,
      'p_image_url': patch['image_url'],
      'p_gallery_urls': patch['gallery_urls'],
    });
    _changes.add(PostChange.updated(postId, patch));
    _removePhotos(removedPhotoUrls);
  }

  /// Deletes the post with its comments and notifications.
  static Future<void> deletePost(Map<String, dynamic> post) async {
    final id = post['id'] as String;
    await _db.rpc('delete_my_post', params: {'p_post_id': id});
    _myPostIds?.then((ids) => ids.remove(id));
    _changes.add(PostChange.deleted(id));
    _removePhotos(photoUrlsOf(post));
  }

  // ---------------------------------------------------------- comments

  static Future<void> updateComment(String commentId, String body) =>
      _db.rpc('update_my_comment',
          params: {'p_comment_id': commentId, 'p_body': body});

  static Future<void> deleteComment(String commentId) =>
      _db.rpc('delete_my_comment', params: {'p_comment_id': commentId});

  // ---------------------------------------------------------- photos

  /// Cover first, then the gallery — the order the picker shows.
  static List<String> photoUrlsOf(Map<String, dynamic> post) => [
        if (post['image_url'] != null) post['image_url'] as String,
        ...List<String>.from(post['gallery_urls'] ?? const []),
      ];

  /// Uploads the [LocalImage]s in [items] to the `images` bucket under
  /// `posts/` and returns every item as a URL, order kept.
  static Future<List<String>> uploadPhotos(List<dynamic> items) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! LocalImage) {
        urls.add(item as String);
        continue;
      }
      final bytes = await ImageCompressor.compressBytes(item.bytes);
      final path = 'posts/${stamp}_$i.jpg';
      await _db.storage.from('images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: imageContentType(bytes)),
          );
      urls.add(_db.storage.from('images').getPublicUrl(path));
    }
    return urls;
  }

  /// Best effort: storage policies may not let authors delete objects,
  /// and a leftover file is harmless.
  static void _removePhotos(List<String> urls) {
    const marker = '/object/public/images/';
    final paths = [
      for (final url in urls)
        if (url.contains(marker)) Uri.decodeFull(url.split(marker).last)
    ];
    if (paths.isEmpty) return;
    _db.storage.from('images').remove(paths).catchError((Object e) {
      debugPrint("Photo cleanup failed: $e");
      return <FileObject>[];
    });
  }
}
