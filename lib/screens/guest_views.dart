import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../widgets/brand/brand.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/roles.dart';
import '../widgets/comment_tile.dart';
import '../widgets/embed_card.dart';
import '../widgets/mention_text.dart';
import 'gallery_view_screen.dart';

/// Read-only pages for visitors who opened a shared /post or /u link
/// without logging in. They read only what `anon` may read (the
/// *_public views, events, listings) and offer login for every action.
///
/// The logged-in screens (PostDetailScreen, ProfileScreen) assume a
/// signed-in user throughout; if they learn to degrade for guests via
/// `requireLogin`, these can go.

AppBar _guestAppBar(BuildContext context, {Widget? title}) => AppBar(
      title: title,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(AppIcons.back),
        onPressed: () => popOrHome(context),
      ),
    );

Widget _guestBottomBar(BuildContext context, String label) {
  final theme = Theme.of(context);
  return bottomBarConstrained(
    context,
    Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.guestBanner,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            GuestActionBar(label: label),
          ],
        ),
      ),
    ),
  );
}

Widget _avatar(BuildContext context, String? url, {double radius = 20, bool anonymous = false}) {
  final scheme = Theme.of(context).colorScheme;
  return CircleAvatar(
    radius: radius,
    backgroundColor:
        anonymous ? scheme.surfaceContainerHighest : scheme.primaryContainer,
    backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
    child: url == null
        ? Icon(anonymous ? AppIcons.anonymous : AppIcons.person,
            size: radius,
            color: anonymous ? scheme.onSurfaceVariant : scheme.onPrimaryContainer)
        : null,
  );
}

// ======================================================================
// POST
// ======================================================================

class GuestPostScreen extends StatefulWidget {
  /// A row from `posts_public`.
  final Map<String, dynamic> post;

  const GuestPostScreen({super.key, required this.post});

  @override
  State<GuestPostScreen> createState() => _GuestPostScreenState();
}

class _GuestPostScreenState extends State<GuestPostScreen> {
  late Future<List<Map<String, dynamic>>> _comments;

  @override
  void initState() {
    super.initState();
    _comments = _fetchComments();
  }

  Future<List<Map<String, dynamic>>> _fetchComments() async {
    final rows = await Supabase.instance.client
        .from('comments_public')
        .select('*')
        .eq('post_id', widget.post['id'])
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = widget.post;

    final profile = p['profiles'] as Map<String, dynamic>?;
    final isAnon = p['is_anonymous'] == true || profile == null;
    final images = <String>[
      if (p['image_url'] != null) p['image_url'],
      ...?(p['gallery_urls'] as List?)?.whereType<String>(),
    ];
    final event = p['events'] as Map<String, dynamic>?;
    final listing = p['listings'] as Map<String, dynamic>?;
    final title = (p['title'] ?? '').toString();
    final createdAt = DateTime.tryParse(p['created_at'] ?? '');

    return Scaffold(
      appBar: _guestAppBar(context),
      bottomNavigationBar: _guestBottomBar(context, s.loginToComment),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: InkWell(
                customBorder: const CircleBorder(),
                onTap: isAnon ? null : () => context.goUser(profile['id']),
                child: _avatar(context, isAnon ? null : profile['avatar_url'],
                    anonymous: isAnon),
              ),
              title: Text(displayNameFor(s, profile, anonymous: isAnon),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([
                if (!isAnon && profile['username'] != null) "@${profile['username']}",
                if (createdAt != null) formatRelative(context, createdAt),
              ].join(' · ')),
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 8),
            MentionText(p['body'] ?? '',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(height: 1.5, color: scheme.onSurface)),
            for (var i = 0; i < images.length; i++) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: KRadius.card,
                child: InkWell(
                  onTap: () =>
                      showGallery(context, items: images, initialIndex: i),
                  child: CachedNetworkImage(
                      imageUrl: images[i], fit: BoxFit.cover),
                ),
              ),
            ],
            if (event != null) ...[
              const SizedBox(height: 12),
              EmbedCard(
                  data: event,
                  isEvent: true,
                  compact: true,
                  onTap: () => context.goEvent(event)),
            ],
            if (listing != null) ...[
              const SizedBox(height: 12),
              EmbedCard(
                  data: listing,
                  isEvent: false,
                  compact: true,
                  onTap: () => context.goItem(listing)),
            ],
            const SizedBox(height: 16),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(s.comments,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _comments,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                        child: Text(s.noComments,
                            style: TextStyle(color: scheme.onSurfaceVariant))),
                  );
                }
                return Column(
                  children: [for (final c in rows) CommentTile(comment: c)],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// PROFILE
// ======================================================================

class GuestProfileScreen extends StatefulWidget {
  final String userId;

  const GuestProfileScreen({super.key, required this.userId});

  @override
  State<GuestProfileScreen> createState() => _GuestProfileScreenState();
}

class _GuestProfileData {
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? counts;
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> listings;

  _GuestProfileData(
      this.profile, this.counts, this.posts, this.events, this.listings);
}

class _GuestProfileScreenState extends State<GuestProfileScreen> {
  late final Future<_GuestProfileData> _data = _fetch();

  Future<_GuestProfileData> _fetch() async {
    final db = Supabase.instance.client;
    final id = widget.userId;
    final results = await Future.wait([
      db.from('profiles_public').select().eq('id', id).maybeSingle(),
      db.from('follow_counts').select().eq('user_id', id).maybeSingle(),
      db.from('posts_public').select('*').eq('user_id', id)
          .order('created_at', ascending: false).limit(20),
      db.from('events').select().eq('organizer_id', id)
          .order('start_datetime', ascending: false).limit(20),
      db.from('listings').select().eq('seller_id', id)
          .order('created_at', ascending: false).limit(20),
    ].map((f) => f.then<Object?>((v) => v, onError: (_) => null)));

    List<Map<String, dynamic>> list(Object? v) =>
        v is List ? List<Map<String, dynamic>>.from(v) : const [];

    return _GuestProfileData(
      results[0] as Map<String, dynamic>?,
      results[1] as Map<String, dynamic>?,
      list(results[2]),
      list(results[3]),
      list(results[4]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return FutureBuilder<_GuestProfileData>(
      future: _data,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: _guestAppBar(context),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data;
        final profile = data?.profile;
        if (profile == null) {
          return Scaffold(
            appBar: _guestAppBar(context),
            body: Center(child: Text(s.userNotFound)),
          );
        }
        return Scaffold(
          appBar: _guestAppBar(context,
              title: Text(profile['username'] != null
                  ? "@${profile['username']}"
                  : s.profileTitle)),
          bottomNavigationBar: _guestBottomBar(context, s.loginToFollow),
          body: PageBody(child: _body(context, s, data!)),
        );
      },
    );
  }

  Widget _body(BuildContext context, AppStrings s, _GuestProfileData d) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = d.profile!;
    final bio = (p['bio'] ?? '').toString().trim();

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        );

    Widget stat(int? n, String label) => Column(
          children: [
            Text("${n ?? 0}",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: _avatar(context, p['avatar_url'], radius: 40)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(displayNameFor(s, p),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (p['is_verified'] == true) ...[
              const SizedBox(width: 4),
              Icon(AppIcons.verified, size: 18, color: scheme.tertiary),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(roleLabel(s, p['role']),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant)),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(bio, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            stat(d.posts.length, s.posts),
            stat(d.counts?['followers'] as int?, s.followers),
            stat(d.counts?['following'] as int?, s.following),
          ],
        ),
        if (d.events.isNotEmpty) ...[
          section(s.eventsTitle),
          for (final e in d.events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EmbedCard(
                  data: e,
                  isEvent: true,
                  compact: true,
                  onTap: () => context.goEvent(e)),
            ),
        ],
        if (d.listings.isNotEmpty) ...[
          section(s.marketplaceTitle),
          for (final l in d.listings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EmbedCard(
                  data: l,
                  isEvent: false,
                  compact: true,
                  onTap: () => context.goItem(l)),
            ),
        ],
        section(s.posts),
        if (d.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
                child: Text(s.noPostsYet,
                    style: TextStyle(color: scheme.onSurfaceVariant))),
          )
        else
          for (final post in d.posts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                (post['title'] ?? '').toString().isNotEmpty
                    ? post['title']
                    : (post['body'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: post['created_at'] == null
                  ? null
                  : Text(formatRelative(
                      context, DateTime.parse(post['created_at']))),
              trailing: const Icon(AppIcons.chevronRight),
              onTap: () => context.goPost(post),
            ),
      ],
    );
  }
}
