import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/feed_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/report_helper.dart';
import '../utils/roles.dart';
import 'mention_text.dart';
import 'owner_menu.dart';

/// One row from `comments_public`: avatar on a thread line, name (or
/// "Anonymous · Name hidden"), @handle · time, body with @mentions, and
/// the report menu — or Edit/Delete when [onEdit]/[onDelete] are given
/// (the viewer wrote it).
class CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Draw the thread line under the avatar (every comment but the last).
  final bool threadLine;

  /// Author to mark with [highlightLabel] — e.g. the event's organiser,
  /// so their answers stand out in the questions thread.
  final String? highlightUserId;
  final String? highlightLabel;

  const CommentTile({
    super.key,
    required this.comment,
    this.onEdit,
    this.onDelete,
    this.threadLine = false,
    this.highlightUserId,
    this.highlightLabel,
  });

  /// Lets widget tests skip the Supabase session check.
  @visibleForTesting
  static bool? debugLoggedIn;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final fs = context.feedL10n;
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
    final created = DateTime.tryParse('${c['created_at']}') ?? DateTime.now();
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final mine = onEdit != null && onDelete != null;

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Tooltip(
                  message: isAnon ? s.postedAnonymously : displayName,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: authorId == null ? null : () => context.goUser(authorId),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: isAnon
                          ? scheme.surfaceContainerHighest
                          : scheme.primaryContainer,
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
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
                if (threadLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isAnon ? scheme.onSurfaceVariant : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (authorId != null &&
                            authorId == highlightUserId &&
                            highlightLabel != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(highlightLabel!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      [
                        if (isAnon) fs.anonymousSub,
                        if (username != null) '@$username',
                        formatRelative(context, created),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                    const SizedBox(height: 4),
                    MentionText(
                      c['body'] ?? '',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurface, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            mine
                ? OwnerMenuButton(
                    iconSize: 18,
                    tooltip: context.postL10n.commentOptions,
                    onEdit: onEdit!,
                    onDelete: onDelete!,
                  )
                : (debugLoggedIn ?? isLoggedIn)
                    ? ReportMenuButton(
                        targetId: c['id'], type: 'comment', iconSize: 18)
                    : GuardedReportButton(
                        targetId: c['id'], type: 'comment', iconSize: 18),
          ],
        ),
      ),
    );
  }
}
