import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';

/// @mention notifications for posts and comments.
///
/// Anonymous posts/comments must not reveal their author to the people
/// they mention, so those notifications carry no `actor_id` and no name.
/// The `notify_mentions` RPC reads the anonymity flag from the row itself;
/// the direct insert below is only a fallback for databases that don't
/// have the 20261019001100 migration yet.
class MentionService {
  MentionService._();

  static final _mention = RegExp(r"@(\w+)");

  /// Unique usernames mentioned in [text], without the `@`.
  static Set<String> usernamesIn(String text) =>
      _mention.allMatches(text).map((m) => m.group(1)!).toSet();

  /// Notifies everyone @mentioned in [text] (except the author).
  ///
  /// [commentId] null means the mention is in the post itself.
  /// [alreadyNotified] skips usernames from a previous version of the
  /// text, so editing doesn't ping the same people twice.
  /// Never throws — a failed notification must not fail the post.
  static Future<void> notify({
    required String text,
    required String postId,
    String? commentId,
    required bool anonymous,
    Set<String> alreadyNotified = const {},
  }) async {
    final usernames = usernamesIn(text).difference(alreadyNotified);
    if (usernames.isEmpty) return;

    // Read by the recipient, so written in the canonical language.
    const n = AppStrings.en;
    final isComment = commentId != null;
    final title =
        isComment ? n.notifMentionCommentTitle : n.notifMentionTitle;
    final body = isComment
        ? n.notifMentionCommentBody.fill([text])
        : n.notifMentionPostBody;

    final db = Supabase.instance.client;
    try {
      await db.rpc('notify_mentions', params: {
        'p_post_id': postId,
        'p_comment_id': commentId,
        'p_usernames': usernames.toList(),
        'p_title': title,
        'p_body': body,
      });
    } on PostgrestException catch (e) {
      // PGRST202: function not found (migration not applied yet).
      if (e.code != 'PGRST202') {
        debugPrint("Mention notify failed: ${e.message}");
        return;
      }
      await _insertDirectly(db, usernames,
          postId: postId,
          commentId: commentId,
          anonymous: anonymous,
          title: title,
          body: body);
    } catch (e) {
      debugPrint("Mention notify failed: $e");
    }
  }

  static Future<void> _insertDirectly(
    SupabaseClient db,
    Set<String> usernames, {
    required String postId,
    required String? commentId,
    required bool anonymous,
    required String title,
    required String body,
  }) async {
    try {
      final myId = db.auth.currentUser!.id;
      final users = await db
          .from('profiles')
          .select('id')
          .inFilter('username', usernames.toList());
      final rows = [
        for (final u in users)
          if (u['id'] != myId)
            {
              'user_id': u['id'],
              if (!anonymous) 'actor_id': myId,
              'type': 'mention',
              'title': title,
              'body': body,
              'data': {'post_id': postId, 'comment_id': commentId},
            }
      ];
      if (rows.isNotEmpty) await db.from('notifications').insert(rows);
    } catch (e) {
      debugPrint("Mention notify failed: $e");
    }
  }
}
