import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/feed_strings.dart';
import '../l10n/moderation_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/report_helper.dart';
import '../utils/roles.dart';
import 'brand/brand.dart';
import 'mention_text.dart';

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

  /// Pin / unpin, offered to the post author, event organiser and admins.
  final VoidCallback? onTogglePin;

  const CommentTile({
    super.key,
    required this.comment,
    this.onEdit,
    this.onDelete,
    this.threadLine = false,
    this.highlightUserId,
    this.highlightLabel,
    this.onTogglePin,
  });

  /// Lets widget tests skip the Supabase session check.
  @visibleForTesting
  static bool? debugLoggedIn;

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
    final created = DateTime.tryParse('${c['created_at']}') ?? DateTime.now();
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final mine = onEdit != null && onDelete != null;
    final pinned = c['pinned_at'] != null;

    return Padding(
      padding: const EdgeInsets.only(left: KSpace.l, top: KSpace.m),
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
                          ? Icon(isAnon ? AppIcons.anonymous : AppIcons.person,
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
                      margin: const EdgeInsets.only(top: KSpace.xs),
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: KSpace.m),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: KSpace.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (pinned)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(children: [
                          Icon(AppIcons.pin, size: 12, color: scheme.primary),
                          const SizedBox(width: KSpace.xs),
                          Text(s.mod.pinned,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isAnon ? scheme.onSurfaceVariant : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (authorId != null &&
                            authorId == highlightUserId &&
                            highlightLabel != null) ...[
                          const SizedBox(width: KSpace.xs + 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: KRadius.small,
                            ),
                            child: Text(highlightLabel!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                        const SizedBox(width: KSpace.xs + 2),
                        // name · @handle · time on one line
                        Flexible(
                          child: Text(
                            [
                              if (username != null) '@$username',
                              formatRelative(context, created),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: KSpace.xs),
                    MentionText(
                      c['body'] ?? '',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurface, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            _CommentMenu(
              comment: c,
              mine: mine,
              pinned: pinned,
              onTogglePin: onTogglePin,
              onEdit: onEdit,
              onDelete: onDelete,
              loggedIn: debugLoggedIn ?? isLoggedIn,
            ),
          ],
        ),
      ),
    );
  }
}

/// ⋮ for a comment: Pin/Unpin (if allowed), Edit/Delete (yours) or
/// Report (others'; guests are asked to sign in).
class _CommentMenu extends StatelessWidget {
  final Map<String, dynamic> comment;
  final bool mine;
  final bool pinned;
  final bool loggedIn;
  final VoidCallback? onTogglePin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CommentMenu({
    required this.comment,
    required this.mine,
    required this.pinned,
    required this.loggedIn,
    this.onTogglePin,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final fs = context.feedL10n;

    PopupMenuItem<String> item(String v, IconData icon, String label, {bool danger = false}) =>
        PopupMenuItem(
          value: v,
          child: Row(children: [
            Icon(icon, size: 20, color: danger ? scheme.error : scheme.onSurface),
            const SizedBox(width: KSpace.m),
            Text(label, style: danger ? TextStyle(color: scheme.error) : null),
          ]),
        );

    return PopupMenuButton<String>(
      tooltip: context.postL10n.commentOptions,
      icon: Icon(AppIcons.more, size: 18, color: scheme.onSurfaceVariant),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      onSelected: (v) {
        switch (v) {
          case 'pin':
            onTogglePin?.call();
          case 'edit':
            onEdit?.call();
          case 'delete':
            onDelete?.call();
          default:
            if (!loggedIn && !requireLogin(context)) return;
            showReportDialog(context, '${comment['id']}', 'comment');
        }
      },
      itemBuilder: (_) => [
        if (onTogglePin != null)
          item('pin', AppIcons.pin, pinned ? fs.unpinComment : fs.pinComment),
        if (mine) ...[
          item('edit', AppIcons.edit, s.edit),
          item('delete', AppIcons.delete, s.delete, danger: true),
        ] else
          item('report', AppIcons.report, s.report, danger: true),
      ],
    );
  }
}

