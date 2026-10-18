import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/theme/app_themes.dart';
import '../l10n/app_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../screens/create_post_screen.dart';
import '../screens/gallery_view_screen.dart';
import '../services/post_service.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import 'mention_text.dart';
import 'owner_menu.dart';

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final bool showProfileHeader;

  /// Called after the author deletes this post from the card's menu (the
  /// card hides itself either way).
  final VoidCallback? onDeleted;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.showProfileHeader = true,
    this.onDeleted,
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

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    final post = _post;
    final onTap = widget.onTap;
    final showProfileHeader = widget.showProfileHeader;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final isAnon = post['is_anonymous'] ?? false;
    final photos = PostService.photoUrlsOf(post);
    
    // Safety check for date
    final createdVal = post['created_at'];
    final date = createdVal != null ? DateTime.parse(createdVal) : DateTime.now();

    // Data parsing
    final rawProfile = post['profiles'];
    final Map<String, dynamic>? profile = (rawProfile is List && rawProfile.isNotEmpty) 
        ? rawProfile.first 
        : (rawProfile is Map<String, dynamic> ? rawProfile : null);

    final String displayName = displayNameFor(s, profile, anonymous: isAnon);
    final String? avatarUrl = isAnon ? null : profile?['avatar_url'];
    final String? username = isAnon ? null : profile?['username'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      // Signature kerawang cut — DESIGN_SPEC §2
      shape: RoundedRectangleBorder(
        borderRadius: kerawangCut,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      color: theme.cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // 1. HEADER (User + PFP)
              if (showProfileHeader)
                Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: (isAnon || profile == null)
                          ? null
                        : () => context.goUser(profile['id']),
                    child: Tooltip(
                      message: isAnon ? s.postedAnonymously : displayName,
                      child: CircleAvatar(
                        radius: 16, // Slightly larger for better visibility
                        backgroundColor: isAnon ? scheme.surfaceContainerHighest : scheme.primaryContainer,
                        backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                        child: (avatarUrl == null)
                            ? Icon(isAnon ? Icons.visibility_off : Icons.person, size: 16, color: isAnon ? scheme.onSurfaceVariant : scheme.onPrimaryContainer)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Name & Time Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isAnon && username != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                "@$username",
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ]
                          ],
                        ),
                        Text(
                          formatRelative(context, date),
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  
                  
                ],
              ),
              const SizedBox(height: 12),

              // Tag
                  if (post['tags'] != null && (post['tags'] as List).isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "#${post['tags'][0]}",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ),
                
                const SizedBox(height: 12),

              // 2. TITLE
              Text(
                post['title'] ?? s.untitled,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 6),

              // 3. BODY PREVIEW
              if (post['body'] != null)
                MentionText(post['body'] ?? ''),

              if (photos.isNotEmpty) _PostPhotos(urls: photos),

              // 4. SHARED CONTENT (Event OR Listing) — same embed language
              // as the feed, compact so it supports rather than dominates.
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

              const SizedBox(height: 16),

              // 5. FOOTER (comment count + report)
              Row(
                children: [
                  // Comment Count
                  Icon(Icons.chat_bubble_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Builder(builder: (context) {
                    final count = post['comment_count'] ?? 0;
                    return Text(
                      (count == 1 ? s.commentCountOne : s.commentCountMany).fill([count]),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }),
                  
                  const Spacer(),
                  _mine
                      ? OwnerMenuButton(
                          onEdit: () => openPostEditor(context, post),
                          onDelete: _delete,
                        )
                      : ReportMenuButton(targetId: post['id'], type: 'post'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Cover photo with the kerawang cut; a counter when there are more.
/// Tapping opens the gallery at the cover.
class _PostPhotos extends StatelessWidget {
  final List<String> urls;

  const _PostPhotos({required this.urls});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ps = context.postL10n;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        button: true,
        label: ps.postPhoto.fill([1, urls.length]),
        child: ClipRRect(
          borderRadius: kerawangCut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Material(
                color: scheme.surfaceContainerHighest,
                child: InkWell(
                  onTap: () => showGallery(context, items: urls),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Ink.image(
                        image: CachedNetworkImageProvider(urls.first),
                        fit: BoxFit.cover,
                      ),
                      if (urls.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: photoScrim(),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_outlined,
                                    size: 14, color: kOnPhoto),
                                const SizedBox(width: 4),
                                Text("${urls.length}",
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                            color: kOnPhoto,
                                            fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}