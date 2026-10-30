import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../widgets/brand/brand.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/event_live.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/guest_access.dart';
import '../utils/roles.dart';
import '../widgets/embed_card.dart';

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
        color: theme.colorScheme.surface,
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
      [...list(results[3])]..sort(compareForBrowse),
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
