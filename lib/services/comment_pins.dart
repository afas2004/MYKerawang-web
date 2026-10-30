import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../utils/moderation_logic.dart';
import '../widgets/moderation_ui.dart';
import '../widgets/app_toast.dart';

/// Pinned comments (migration 20261022003200): the post's author, the
/// event's organiser, or an admin pins up to [kMaxPinnedComments] per
/// post / event; pinned ones are listed first with a "Pinned" label.
const kMaxPinnedComments = 3;

/// Whether a comments_public row is pinned.
bool isCommentPinned(Map<String, dynamic> c) => c['pinned_at'] != null;

/// Pinned comments first (in the order they were pinned), then the rest
/// in their original order.
List<Map<String, dynamic>> pinnedFirst(Iterable<Map<String, dynamic>> rows) {
  final list = rows.toList();
  final pinned = list.where(isCommentPinned).toList()
    ..sort((a, b) => '${a['pinned_at']}'.compareTo('${b['pinned_at']}'));
  return [...pinned, ...list.where((c) => !isCommentPinned(c))];
}

abstract final class CommentPins {
  /// Test hook replacing the `pin_comment` RPC.
  @visibleForTesting
  static Future<Object?> Function(String commentId, bool pin)? debugRpc;

  static Future<Object?> _rpc(String id, bool pin) =>
      debugRpc?.call(id, pin) ??
      Supabase.instance.client
          .rpc('pin_comment', params: {'p_comment_id': id, 'p_pin': pin});

  /// Pins or unpins [comment]. Returns the new pinned state, or null when
  /// nothing changed (with a snackbar either way). At the limit it says
  /// "Unpin one first".
  static Future<bool?> toggle(
      BuildContext context, Map<String, dynamic> comment) async {
    final pin = !isCommentPinned(comment);
    final fs = context.feedL10nRead;
    try {
      await _rpc('${comment['id']}', pin);
      showToast(pin ? fs.commentPinnedToast : fs.commentUnpinnedToast);
      return pin;
    } catch (e) {
      final err = parseModError(e);
      if (err?.code == 'comment_pin_limit') {
        final max = err!.detail['max'] ?? kMaxPinnedComments;
        showToast(fs.commentPinLimit.fill([max]));
      } else if (context.mounted) {
        showModError(context, e);
      }
      return null;
    }
  }
}
