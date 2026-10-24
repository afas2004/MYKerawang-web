import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/theme/app_themes.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/moderation_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../screens/gallery_view_screen.dart';
import '../screens/tag_feed_screen.dart';
import '../services/moderation_service.dart';
import '../services/post_service.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/roles.dart';
import '../utils/tags.dart';
import 'mention_text.dart';
import 'owner_menu.dart';
import 'pin_controls.dart';
import 'save_button.dart';

/// One post in a feed (or the head of a thread).
///
/// Header: avatar · name ✓ @handle · time ········ more (edit/delete or
/// report, plus pin for those allowed). Then an optional title, the body
/// with @mentions, hashtags as plain links, photos, a shared event/listing,
/// and one action row: comment · save · share. Pinned posts are an
/// official [KCard] with a "Pinned" label.
/// Route of a post's page — what every share / copy-link points at.
String postSharePath(Object id) => '/post/$id';

/// Absolute URL of a post (origin of the running app on web).
String postShareUrl(Object id) => ShareService.absoluteUrl(postSharePath(id));

class PostCard extends StatefulWidget {
  /// Lets widget tests see what Share would send.
  @visibleForTesting
  static Future<void> Function(BuildContext context, String title, String body,
      dynamic images, {String? link})? debugShare;

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

  /// Show the club-page pin action (officers viewing their own club's page).
  /// Global pinning stays admin-only.
  final bool canClubPin;

  /// Called after a club-page pin/unpin, so the page can re-order.
  final VoidCallback? onClubPinChanged;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.showProfileHeader = true,
    this.onDeleted,
    this.onTagTap,
    this.onCommentTap,
    this.expanded = false,
    this.canClubPin = false,
    this.onClubPinChanged,
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
    final ok = await confirmDelete(context,
        title: ps.deletePost, message: ps.deletePostConfirm);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.deletePost(_post);
      messenger.showSnackBar(SnackBar(content: Text(ps.postDeleted)));
      widget.onDeleted?.call();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(s.errorWithDetail.fill([e]))));
    }
  }

  Future<void> _togglePin() async {
    final pinned = _post['is_pinned'] == true;
    final now = await PinActions.toggle(context, _post, pinned: pinned);
    if (mounted && now != pinned) {
      setState(() => _post = {..._post, 'is_pinned': now});
    }
  }

  Future<void> _toggleClubPin() async {
    final pinned = _post['is_club_pinned'] == true;
    final now = await PinActions.toggleClub(context, _post, pinned: pinned);
    if (mounted && now != pinned) {
      setState(() => _post = {..._post, 'is_club_pinned': now});
      widget.onClubPinChanged?.call();
    }
  }

  void _share() {
    final post = _post;
    final title = (post['title'] as String?)?.trim();
    final body = (post['body'] as String? ?? '').trim();
    final share = PostCard.debugShare ?? ShareService.shareContent;
    share(
      context,
      (title == null || title.isEmpty) ? AppStrings.appName : title,
      body,
      PostService.photoUrlsOf(post),
      // The route; the sheet makes it absolute (ShareService.absoluteUrl)
      // and appends it to the message.
      link: postSharePath(post['id']),
    );
  }

  Future<void> _copyLink() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = context.l10nRead;
    await Clipboard.setData(ClipboardData(text: postShareUrl(_post['id'])));
    messenger.showSnackBar(SnackBar(content: Text(s.linkCopied)));
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
    final tags = List<String>.from(post['tags'] ?? const [])
        .map(normalizeTag)
        .where((t) => t.isNotEmpty)
        .toSet();
    final pinned = post['is_pinned'] == true;
    final sharedIsEvent = post['events'] != null;
    final Map<String, dynamic>? shared =
        (post['events'] ?? post['listings']) as Map<String, dynamic>?;

    final more = _MoreMenu(
      post: post,
      mine: _mine,
      onEdit: () => openPostEditor(context, post),
      onDelete: _delete,
      onTogglePin: _togglePin,
      canClubPin: widget.canClubPin,
      onToggleClubPin: _toggleClubPin,
      onCopyLink: _copyLink,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showProfileHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.xs, 0),
            child: Row(
              children: [
                Expanded(child: _AuthorRow(post: post)),
                more,
              ],
            ),
          )
        else
          Align(alignment: Alignment.topRight, child: more),
        Padding(
          padding: EdgeInsets.fromLTRB(KSpace.l,
              widget.showProfileHeader ? KSpace.s : 0, KSpace.l, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) ...[
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
                ),
                const SizedBox(height: KSpace.xs),
              ],
              if (body.isNotEmpty)
                MentionText(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15, height: 1.45, color: scheme.onSurface),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: KSpace.xs),
                  child: Wrap(
                    spacing: KSpace.s,
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
              // A shared event / listing is the hero, right under the
              // text; the post's own photos shrink to a thumbnail strip.
              if (shared != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: KSpace.m),
                  child: SharedItemHero(
                    data: shared,
                    isEvent: sharedIsEvent,
                    onTap: () => sharedIsEvent
                        ? context.goEvent(shared)
                        : context.goItem(shared),
                  ),
                ),
                if (photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: KSpace.s),
                    child: PostPhotoStrip(urls: photos),
                  ),
              ] else if (photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: KSpace.m),
                  child: PostPhotoLayout(urls: photos),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.xs, KSpace.xs, KSpace.xs, KSpace.xs),
          child: _ActionRow(
            post: post,
            onComment: widget.onCommentTap ?? widget.onTap,
            onShare: _share,
          ),
        ),
      ],
    );

    return Padding(
      // Cards sit on the 16 px gutter, 12 px apart.
      padding: widget.expanded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(
              horizontal: KSpace.gutter, vertical: KSpace.m / 2),
      child: KCard(
        official: pinned,
        officialLabel: pinned ? context.l10n.mod.pinned : null,
        padding: EdgeInsets.zero,
        onTap: widget.onTap,
        child: content,
      ),
    );
  }
}

/// Avatar 40 · name (semibold) ✓ role · @handle · time — one line.
/// Anonymous posts: neutral avatar and just "Anonymous · time".
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
    final Map<String, dynamic>? profile = (rawProfile is List && rawProfile.isNotEmpty)
        ? rawProfile.first
        : (rawProfile is Map<String, dynamic> ? rawProfile : null);

    final displayName = displayNameFor(s, profile, anonymous: isAnon);
    final avatarUrl = isAnon ? null : profile?['avatar_url'] as String?;
    final username = isAnon ? null : profile?['username'] as String?;
    final verified = !isAnon && profile?['is_verified'] == true;
    final role = isAnon ? null : profile?['role'] as String?;
    final showRole = role == 'club' || role == 'admin' || role == 'owner';
    final created = DateTime.tryParse('${post['created_at']}') ?? DateTime.now();
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final canOpen = !isAnon && profile != null;

    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor:
          isAnon ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      backgroundImage:
          avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
      child: avatarUrl == null
          ? Icon(isAnon ? AppIcons.anonymous : AppIcons.person,
              size: 20,
              color: isAnon ? scheme.onSurfaceVariant : scheme.onPrimaryContainer)
          : null,
    );

    return Row(
      children: [
        Tooltip(
          message: isAnon ? s.postedAnonymously : displayName,
          child: canOpen
              ? InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.goUser(profile['id']),
                  child: avatar,
                )
              : avatar,
        ),
        const SizedBox(width: KSpace.m),
        Flexible(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (verified) ...[
          const SizedBox(width: KSpace.xs),
          Tooltip(
            message: fs.verified,
            child: Icon(AppIcons.verified, size: 16, color: scheme.primary),
          ),
        ],
        if (showRole) ...[
          const SizedBox(width: KSpace.xs + 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: KRadius.small,
            ),
            child: Text(
              roleLabel(s, role),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
        const SizedBox(width: KSpace.xs + 2),
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
    );
  }
}

/// Top-right "more" menu: Edit / Delete for the author, Report for
/// everyone else, plus Pin / Unpin for admins and clubs on their own posts.
class _MoreMenu extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool mine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final bool canClubPin;
  final VoidCallback onToggleClubPin;
  final VoidCallback onCopyLink;

  const _MoreMenu({
    required this.post,
    required this.mine,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.canClubPin,
    required this.onToggleClubPin,
    required this.onCopyLink,
  });

  void _report(BuildContext context) {
    if (ModerationService.currentUserId == null && !requireLogin(context)) return;
    showReportDialog(context, '${post['id']}', 'post');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final m = s.mod;
    final pinned = post['is_pinned'] == true;
    final clubPinned = post['is_club_pinned'] == true;

    PopupMenuItem<String> item(String value, IconData icon, String label,
            {bool danger = false}) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 20, color: danger ? scheme.error : scheme.onSurface),
              const SizedBox(width: KSpace.m),
              Text(label, style: danger ? TextStyle(color: scheme.error) : null),
            ],
          ),
        );

    return FutureBuilder<String?>(
      future: ModerationService.myRole(),
      builder: (context, snap) {
        final canPin = PinActions.canPin(post, snap.data);
        return PopupMenuButton<String>(
          tooltip: mine ? context.postL10n.postOptions : s.more,
          icon: Icon(AppIcons.more, size: 20, color: scheme.onSurfaceVariant),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          onSelected: (v) => switch (v) {
            'edit' => onEdit(),
            'delete' => onDelete(),
            'pin' => onTogglePin(),
            'clubPin' => onToggleClubPin(),
            'link' => onCopyLink(),
            _ => _report(context),
          },
          itemBuilder: (_) => [
            item('link', AppIcons.link, s.copyLink),
            if (canPin) item('pin', AppIcons.pin, pinned ? m.unpin : m.pin),
            if (canClubPin)
              item('clubPin', AppIcons.pin, clubPinned ? m.unpinFromClub : m.pinToClub),
            if (mine) ...[
              item('edit', AppIcons.edit, s.edit),
              item('delete', AppIcons.delete, s.delete, danger: true),
            ] else
              item('report', AppIcons.report, s.report, danger: true),
          ],
        );
      },
    );
  }
}

/// comment · save · share — left aligned, 20 px icons, 48 px targets.
class _ActionRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onComment;
  final VoidCallback onShare;

  const _ActionRow({
    required this.post,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final fs = context.feedL10n;
    final count = (post['comment_count'] as num?)?.toInt() ?? 0;
    final muted = scheme.onSurfaceVariant;

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
                : (count == 1 ? s.commentCountOne : s.commentCountMany).fill([count]),
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: onComment,
              style: TextButton.styleFrom(
                foregroundColor: muted,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
              ),
              icon: const Icon(AppIcons.comment, size: 20),
              label: Text(count == 0 ? fs.commentAction : '$count'),
            ),
          ),
          SaveButton(type: SavedType.post, id: post['id'], iconSize: 20, color: muted),
          IconButton(
            tooltip: fs.shareAction,
            onPressed: onShare,
            icon: Icon(AppIcons.share, size: 20, color: muted),
          ),
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
        borderRadius: KRadius.small,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.s, horizontal: 2),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Post photos, full width with the 16 px card radius: 1 = one 4:3 photo,
/// 2 = side by side, 3 = one large + two stacked, 4+ = 2×2 with "+N".
/// Each tile opens the gallery at its own photo.
class PostPhotoLayout extends StatelessWidget {
  final List<String> urls;

  const PostPhotoLayout({super.key, required this.urls});

  static const double _gap = KSpace.xs;

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
      grid = Row(children: [
        Expanded(child: tile(0)),
        const SizedBox(width: _gap),
        Expanded(child: tile(1)),
      ]);
    } else if (n == 3) {
      ratio = 4 / 3;
      grid = Row(children: [
        Expanded(flex: 2, child: tile(0)),
        const SizedBox(width: _gap),
        Expanded(
          child: Column(children: [
            Expanded(child: tile(1)),
            const SizedBox(height: _gap),
            Expanded(child: tile(2)),
          ]),
        ),
      ]);
    } else {
      ratio = 1;
      grid = Column(children: [
        Expanded(
          child: Row(children: [
            Expanded(child: tile(0)),
            const SizedBox(width: _gap),
            Expanded(child: tile(1)),
          ]),
        ),
        const SizedBox(height: _gap),
        Expanded(
          child: Row(children: [
            Expanded(child: tile(2)),
            const SizedBox(width: _gap),
            Expanded(child: tile(3, extra: n - 4)),
          ]),
        ),
      ]);
    }

    return ClipRRect(
      borderRadius: KRadius.card,
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
                child: Icon(AppIcons.photo, color: scheme.onSurfaceVariant),
              ),
            ),
            if (extra > 0)
              ColoredBox(
                color: photoScrim(),
                child: Center(
                  child: Text(
                    context.feedL10n.morePhotos.fill([extra]),
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: kOnPhoto, fontWeight: FontWeight.w600),
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

/// The post's own photos when a shared event/listing is the hero: a row
/// of small thumbnails, each opening the gallery.
class PostPhotoStrip extends StatelessWidget {
  final List<String> urls;

  const PostPhotoStrip({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: KSpace.s),
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: KRadius.small,
          child: SizedBox.square(
            dimension: 64,
            child: _PhotoTile(urls: urls, index: i),
          ),
        ),
      ),
    );
  }
}
