import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/roles.dart';
import 'mention_text.dart';

/// One row from `comments_public`: author avatar + name (or "Anonymous"),
/// time, body with @mentions, and the report menu. Same look as the
/// comments under a post.
class CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;

  const CommentTile({super.key, required this.comment});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = comment;

    // The view nulls `profiles` on anonymous rows, so a missing profile
    // reads as anonymous too.
    final profile = c['profiles'] as Map<String, dynamic>?;
    final isAnon = c['is_anonymous'] == true || profile == null;
    final displayName = displayNameFor(s, profile, anonymous: isAnon);
    final avatarUrl = isAnon ? null : profile['avatar_url'] as String?;
    final username = isAnon ? null : profile['username'] as String?;
    final authorId = isAnon ? null : (c['user_id'] ?? profile['id']) as String?;
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Tooltip(
        message: isAnon ? s.postedAnonymously : displayName,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: authorId == null ? null : () => context.goUser(authorId),
          child: CircleAvatar(
            radius: 16,
            backgroundColor:
                isAnon ? scheme.surfaceContainerHighest : scheme.primaryContainer,
            backgroundImage:
                avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
            child: avatarUrl == null
                ? Icon(isAnon ? Icons.visibility_off : Icons.person,
                    size: 16,
                    color: isAnon
                        ? scheme.onSurfaceVariant
                        : scheme.onPrimaryContainer)
                : null,
          ),
        ),
      ),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(displayName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          if (username != null) Text("@$username", style: meta),
          Text("· ${formatRelative(context, DateTime.parse(c['created_at']))}",
              style: meta),
        ],
      ),
      subtitle: MentionText(c['body'] ?? ''),
      trailing:
          GuardedReportButton(targetId: c['id'], type: 'comment', iconSize: 18),
    );
  }
}
