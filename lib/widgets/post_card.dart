import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/theme/app_themes.dart';
import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../screens/gallery_view_screen.dart';
import '../screens/tag_feed_screen.dart';
import '../services/post_service.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../utils/tags.dart';
import 'mention_text.dart';
import 'owner_menu.dart';
import 'pin_controls.dart';
import 'save_button.dart';

/// One post in a feed (or the head of a thread).
///
/// Hierarchy, top to bottom: author row (avatar, name, verified, @handle,
/// time) · optional title in the display face · body with @mentions ·
/// hashtags as plain text · photos (1 full / 2 side by side / 3–4 grid,
/// +N beyond) · shared event/listing · action row (comment, save, share,
/// pin, more). Pinned posts sit in a gold frame.
class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final bool showProfileHeader;

  /// Called after the author deletes this post from the card's menu (the
  /// card hides itself either way).
  final VoidCallback? onDeleted;

  /// Tapping a hashtag; defaults to opening its [TagFeedScreen].
  final ValueChanged<String>? onTagTap;

  /// The comment action; defaults to [onTap] (open the thread).
  final VoidCallback? onCommentTap;

  /// Thread head on the detail page: no outer margin.
  final bool expanded;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.showProfileHeader = true,
    this.onDeleted,
    this.onTagTap,
    this.onCommentTap,
    this.expanded = false,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Map<String, dynamic> _post;
  bool _deleted = false;
  bool _mine = false;
  StreamSubscription<PostChange>? _changes;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _checkOwner();
    // Edits/deletes made elsewhere (detail page, another card) apply here
    // too, so feeds don't need a refetch.
    _changes = PostService.changes.listen((c) {
      if (c.postId != _post['id'] || !mounted) return;
      setState(() {
        if (c.deleted) {
          _deleted = true;
        } else {
          _post = {..._post, ...?c.patch};
        }
      });
    });
  }

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.post, widget.post)) {
      if (old.post['id'] != widget.post['id']) _deleted = false;
      _post = widget.post;
      _checkOwner();
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _checkOwner() async {
    final sync = PostService.isMineSync(_post);
    if (sync != null) {
      _mine = sync;
      return;
    }
    _mine = false;
    final id = _post['id'];
    final mine = await PostService.isMine(_post);
    if (mounted && _post['id'] == id && mine != _mine) {
      setState(() => _mine = mine);
    }
  }

  Future<void> _delete() async {
    final ps = context.postL10nRead;
    final s = context.l10nRead;
    final ok = await confirmDelete(
      context,
      title: ps.deletePost,
      message: ps.deletePostConfirm,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.deletePost(_post);
      messenger.showSnackBar(SnackBar(content: Text(ps.postDeleted)));
      widget.onDeleted?.call();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.errorWithDetail.fill([e]))),
      );
    }
  }

  void _share() {
    final post = _post;
    final title = (post['title'] as String?)?.trim();
    final body = (post['body'] as String? ?? '').trim();
    ShareService.shareContent(
      context,
      (title == null || title.isEmpty) ? AppStrings.appName : title,
      body,
      PostService.photoUrlsOf(post),
      link: '/post/${post['id']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    final post = _post;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final photos = PostService.photoUrlsOf(post);
    final title = (post['title'] as String? ?? '').trim();
    final body = (post['body'] as String? ?? '').trim();
    final tags = List<String>.from(
      post['tags'] ?? const [],
    ).map(normalizeTag).where((t) => t.isNotEmpty).toSet();
    final pinned = post['is_pinned'] == true;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinned)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: PinBadge(post: post),
            ),
          if (widget.showProfileHeader) ...[
            _AuthorRow(post: post),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(height: 1.25),
                  ),
                  const SizedBox(height: 4),
                ],
                if (body.isNotEmpty)
                  MentionText(
                    body,
                    style:
                        (title.isEmpty
                                ? theme.textTheme.bodyLarge
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(color: scheme.onSurface, height: 1.45),
                  ),
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final tag in tags)
                          _TagLink(
                            tag: tag,
                            onTap: () => widget.onTagTap != null
                                ? widget.onTagTap!(tag)
                                : openTagFeed(context, tag),
                          ),
                      ],
                    ),
                  ),
                if (photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: PostPhotoLayout(urls: photos),
                  ),
                // Shared event / listing — compact, supports the post.
                if (post['events'] != null)
                  EmbedCard(
                    data: post['events'],
                    isEvent: true,
                    compact: true,
                    onTap: () => context.goEvent(post['events']),
                  )
                else if (post['listings'] != null)
                  EmbedCard(
                    data: post['listings'],
                    isEvent: false,
                    compact: true,
                    onTap: () => context.goItem(post['listings']),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _ActionRow(
            post: post,
            mine: _mine,
            onComment: widget.onCommentTap ?? widget.onTap,
            onShare: _share,
            onEdit: () => openPostEditor(context, post),
            onDelete: _delete,
          ),
        ],
      ),
    );

    return Card(
      margin: widget.expanded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      // Signature kerawang cut — DESIGN_SPEC §2. Pinned: gold frame.
      shape: RoundedRectangleBorder(
        borderRadius: kerawangCut,
        side: pinned
            ? BorderSide(color: scheme.tertiary, width: 1.5)
            : BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      color: theme.cardColor,
      child: InkWell(onTap: widget.onTap, child: content),
    );
  }
}

/// Avatar, name (+ verified), @handle · time. Anonymous posts get a masked
/// avatar and "Anonymous · Name hidden" — distinct, never mocking.
class _AuthorRow extends StatelessWidget {
  final Map<String, dynamic> post;

  const _AuthorRow({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final fs = context.feedL10n;
    final isAnon = post['is_anonymous'] == true;

    final rawProfile = post['profiles'];
    final Map<String, dynamic>? profile =
        (rawProfile is List && rawProfile.isNotEmpty)
        ? rawProfile.first
        : (rawProfile is Map<String, dynamic> ? rawProfile : null);

    final displayName = displayNameFor(s, profile, anonymous: isAnon);
    final avatarUrl = isAnon ? null : profile?['avatar_url'] as String?;
    final username = isAnon ? null : profile?['username'] as String?;
    final verified = !isAnon && profile?['is_verified'] == true;
    final official = !isAnon && profile?['role'] == 'club';
    final created =
        DateTime.tryParse('${post['created_at']}') ?? DateTime.now();
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final canOpen = !isAnon && profile != null;

    return Row(
      children: [
        Tooltip(
          message: isAnon ? s.postedAnonymously : displayName,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canOpen ? () => context.goUser(profile['id']) : null,
            child: Padding(
              padding: const EdgeInsets.all(4), // 48 px target
              child: CircleAvatar(
                radius: 20,
                backgroundColor: isAnon
                    ? scheme.surfaceContainerHighest
                    : scheme.primaryContainer,
                backgroundImage: avatarUrl != null
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl == null
                    ? Icon(
                        isAnon ? Icons.visibility_off : Icons.person,
                        size: 20,
                        color: isAnon
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimaryContainer,
                      )
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isAnon
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: fs.verified,
                      child: Icon(
                        Icons.verified,
                        size: 16,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                  if (official) ...[
                    const SizedBox(width: 6),
                    Text(
                      fs.official.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
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
            ],
          ),
        ),
      ],
    );
  }
}

/// Comment · Save · Share ······ Pin · More. Every target is 48 px.
class _ActionRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool mine;
  final VoidCallback? onComment;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ActionRow({
    required this.post,
    required this.mine,
    required this.onComment,
    required this.onShare,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final fs = context.feedL10n;
    final count = (post['comment_count'] as num?)?.toInt() ?? 0;
    final muted = scheme.onSurfaceVariant;

    // Every icon button in the row (save, share, pin, the menus) gets a
    // 48 px target, also under compact desktop density.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: count == 0
                ? fs.commentAction
                : (count == 1 ? s.commentCountOne : s.commentCountMany).fill([
                    count,
                  ]),
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: onComment,
              style: TextButton.styleFrom(
                foregroundColor: muted,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: Text(count == 0 ? fs.commentAction : '$count'),
            ),
          ),
          SaveButton(
            type: SavedType.post,
            id: post['id'],
            iconSize: 20,
            color: muted,
          ),
          IconButton(
            tooltip: fs.shareAction,
            onPressed: onShare,
            icon: Icon(Icons.ios_share, size: 20, color: muted),
          ),
          const Spacer(),
          PinMenuButton(post: post),
          mine
              ? OwnerMenuButton(
                  onEdit: onEdit,
                  onDelete: onDelete,
                  tooltip: context.postL10n.postOptions,
                )
              : ReportMenuButton(targetId: post['id'], type: 'post'),
        ],
      ),
    );
  }
}

/// A hashtag as plain tappable text (no chip).
class _TagLink extends StatelessWidget {
  final String tag;
  final VoidCallback onTap;

  const _TagLink({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = displayTag(tag);
    return Semantics(
      button: true,
      label: context.postL10n.tagPostsLabel.fill([label]),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Post photos: 1 = full width, 2 = side by side, 3 = one large + two
/// stacked, 4+ = 2×2 with "+N" on the last tile. The block carries the
/// kerawang cut; each tile opens the gallery at its own photo.
class PostPhotoLayout extends StatelessWidget {
  final List<String> urls;

  const PostPhotoLayout({super.key, required this.urls});

  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    Widget tile(int i, {int extra = 0}) =>
        _PhotoTile(urls: urls, index: i, extra: extra);

    final n = urls.length;
    final Widget grid;
    final double ratio;
    if (n == 1) {
      ratio = 4 / 3;
      grid = tile(0);
    } else if (n == 2) {
      ratio = 2 / 1.2;
      grid = Row(
        children: [
          Expanded(child: tile(0)),
          const SizedBox(width: _gap),
          Expanded(child: tile(1)),
        ],
      );
    } else if (n == 3) {
      ratio = 4 / 3;
      grid = Row(
        children: [
          Expanded(flex: 2, child: tile(0)),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: tile(1)),
                const SizedBox(height: _gap),
                Expanded(child: tile(2)),
              ],
            ),
          ),
        ],
      );
    } else {
      ratio = 1;
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(0)),
                const SizedBox(width: _gap),
                Expanded(child: tile(1)),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(2)),
                const SizedBox(width: _gap),
                Expanded(child: tile(3, extra: n - 4)),
              ],
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: kerawangCut,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: AspectRatio(aspectRatio: ratio, child: grid),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final List<String> urls;
  final int index;
  final int extra;

  const _PhotoTile({required this.urls, required this.index, this.extra = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    void open() => showGallery(context, items: urls, initialIndex: index);

    return Semantics(
      button: true,
      image: true,
      label: context.postL10n.postPhoto.fill([index + 1, urls.length]),
      onTap: open,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: urls[index],
              fit: BoxFit.cover,
              memCacheWidth: (box.maxWidth * dpr).round().clamp(64, 2000),
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) =>
                  ColoredBox(color: scheme.surfaceContainerHighest),
              errorWidget: (_, __, ___) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (extra > 0)
              ColoredBox(
                color: photoScrim(),
                child: Center(
                  child: Text(
                    context.feedL10n.morePhotos.fill([extra]),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: kOnPhoto,
                    ),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: open),
            ),
          ],
        ),
      ),
    );
  }
}
