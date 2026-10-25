import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../language_cubit.dart';
import '../../l10n/access_strings.dart';
import '../../services/club_service.dart';
import '../../utils/app_nav.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import '../../widgets/post_card.dart';
import '../../widgets/universal_card.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

/// /c/:handle — a club's public page. Loads, then hands everything to
/// [ClubPageView] (which tests render with injected data).
class ClubPageScreen extends StatefulWidget {
  final String handle;
  const ClubPageScreen({super.key, required this.handle});

  @override
  State<ClubPageScreen> createState() => _ClubPageScreenState();
}

class _ClubPageScreenState extends State<ClubPageScreen> {
  late Future<_Loaded?> _future = _load();

  Future<_Loaded?> _load() async {
    if (validateHandle(widget.handle) != null) return null;
    final club = await ClubService.byHandle(widget.handle);
    if (club == null) return null;
    final results = await Future.wait([
      ClubService.myRole(club.id),
      ClubService.followerCounts([club.id]),
      ClubService.isFollowing(club.id),
      ClubService.myJoin(club.id),
    ]);
    return _Loaded(
      club,
      results[0] as String?,
      (results[1] as Map<String, int>)[club.id] ?? 0,
      results[2] as bool,
      results[3] as ClubJoinState,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return FutureBuilder<_Loaded?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(appBar: AppBar(), body: const _HeaderSkeleton());
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorState(onRetry: () => setState(() {
                  _future = _load();
                })),
          );
        }
        final d = snap.data;
        if (d == null) {
          return Scaffold(
            appBar: AppBar(),
            body: BrandEmptyState(
              illo: AppIllo.noResults,
              title: c.clubNotFound,
              message: c.clubNotFoundBody,
              actionLabel: c.directoryTitle,
              onAction: () => context.go('/clubs'),
            ),
          );
        }
        final id = d.club.id;
        return ClubPageView(
          club: d.club,
          myRole: d.role,
          followers: d.followers,
          following: d.following,
          join: d.join,
          signedIn: ClubService.currentUserId != null,
          onSetFollowing: (v) => ClubService.setFollowing(id, v),
          onJoin: () => ClubService.applyToClub(id),
          onManage: () async {
            await context.push('/c/${d.club.handle}/manage');
            if (mounted) {
              setState(() {
                _future = _load();
              });
            }
          },
          loadPosts: () => ClubService.posts(id),
          loadEvents: () => ClubService.events(id),
          loadListings: () => ClubService.listings(id),
          loadMembers: () => ClubService.members(id),
        );
      },
    );
  }
}

class _Loaded {
  final Club club;
  final String? role;
  final int followers;
  final bool following;
  final ClubJoinState join;
  const _Loaded(this.club, this.role, this.followers, this.following, this.join);
}

/// The page itself: header (cover, logo, name, follow / manage), status
/// banner for officers, and tabs Announcements / Events / Market /
/// Members. Pure UI: data and actions are injected.
class ClubPageView extends StatefulWidget {
  final Club club;
  final String? myRole;
  final int followers;
  final bool following;
  final bool signedIn;
  final Future<void> Function(bool follow) onSetFollowing;
  final VoidCallback onManage;
  final ClubJoinState join;
  final Future<void> Function()? onJoin;
  final Future<List<Map<String, dynamic>>> Function() loadPosts;
  final Future<List<Map<String, dynamic>>> Function() loadEvents;
  final Future<List<Map<String, dynamic>>> Function() loadListings;
  final Future<List<ClubMember>> Function() loadMembers;

  const ClubPageView({
    super.key,
    required this.club,
    required this.myRole,
    required this.followers,
    required this.following,
    required this.signedIn,
    required this.onSetFollowing,
    required this.onManage,
    this.join = ClubJoinState.none,
    this.onJoin,
    required this.loadPosts,
    required this.loadEvents,
    required this.loadListings,
    required this.loadMembers,
  });

  @override
  State<ClubPageView> createState() => _ClubPageViewState();
}

class _ClubPageViewState extends State<ClubPageView> {
  late bool _following = widget.following;
  late int _followers = widget.followers;
  late bool _pending = widget.join.pending;
  bool _busy = false;
  bool _joining = false;

  late Future<List<Map<String, dynamic>>> _posts = widget.loadPosts();
  late final Future<List<Map<String, dynamic>>> _events = widget.loadEvents();
  late final Future<List<Map<String, dynamic>>> _listings = widget.loadListings();
  late final Future<List<ClubMember>> _members = widget.loadMembers();

  Future<void> _toggleFollow() async {
    final next = !_following;
    setState(() {
      _busy = true;
      _following = next;
      _followers += next ? 1 : -1;
    });
    try {
      await widget.onSetFollowing(next);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _following = !next;
        _followers += next ? -1 : 1;
      });
      showClubSnack(context, context.l10nRead.club.genericError, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final cb = widget.onJoin;
    if (cb == null) return;
    final c = context.l10nRead.club;
    setState(() => _joining = true);
    try {
      await cb();
      if (!mounted) return;
      setState(() => _pending = true);
      showClubSnack(context, c.joinRequested);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final club = widget.club;
    final tabs = [c.tabAnnouncements, c.tabEvents, c.tabMarket, c.tabMembers];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: Text(club.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _header(context)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final t in tabs) Tab(text: t)],
                ),
                Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _PostsTab(
                future: _posts,
                canClubPin: widget.club.isActive && canManageClub(widget.myRole),
                onClubPinChanged: () => setState(() {
                  _posts = widget.loadPosts();
                }),
              ),
              _CardsTab(future: _events, emptyTitle: c.noEvents, illo: AppIllo.noEvents, isEvent: true),
              _CardsTab(future: _listings, emptyTitle: c.noListings, illo: AppIllo.emptyMarket, isEvent: false),
              _MembersTab(
                future: _members,
                onJoin: (widget.signedIn &&
                        club.isActive &&
                        widget.myRole == null)
                    ? _join
                    : null,
                pending: _pending,
                joining: _joining,
                recruitmentOpen: club.recruitmentOpen,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final club = widget.club;
    final officer = canManageClub(widget.myRole);
    final meta = [
      if ((club.category ?? '').isNotEmpty) c.categoryLabel(club.category),
      if ((club.faculty ?? '').isNotEmpty) club.faculty!,
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 140,
                  margin: const EdgeInsets.symmetric(horizontal: KSpace.l),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: club.coverUrl == null
                      ? null
                      : CachedNetworkImage(
                          imageUrl: club.coverUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                ),
                Positioned(
                  left: KSpace.xl,
                  bottom: -36,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: ClubLogo(url: club.logoUrl, name: club.name, size: 80),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 44),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClubNameLine(name: club.name, verified: club.isVerified, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text('@${club.handle} · ${c.followerLabel(_followers)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: KSpace.s),
                    Wrap(spacing: KSpace.s, runSpacing: KSpace.xs, children: [for (final m in meta) ClubPill(m)]),
                  ],
                  if ((club.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: KSpace.m),
                    Text(club.description!, style: theme.textTheme.bodyMedium),
                  ],
                  if (club.socials.isNotEmpty || (club.contactEmail ?? '').isNotEmpty) ...[
                    const SizedBox(height: KSpace.s),
                    Wrap(
                      spacing: KSpace.m,
                      runSpacing: KSpace.xs,
                      children: [
                        if ((club.contactEmail ?? '').isNotEmpty) _InfoChip(AppIcons.email, club.contactEmail!),
                        for (final e in club.socials.entries)
                          _InfoChip(e.key == 'website' ? AppIcons.website : AppIcons.mention, e.value),
                      ],
                    ),
                  ],
                  const SizedBox(height: KSpace.l),
                  Row(
                    children: [
                      if (widget.signedIn && club.isActive)
                        Expanded(
                          child: _following
                              ? OutlinedButton.icon(
                                  onPressed: _busy ? null : _toggleFollow,
                                  icon: const Icon(AppIcons.following, size: 18),
                                  label: Text(c.following),
                                )
                              : FilledButton.icon(
                                  onPressed: _busy ? null : _toggleFollow,
                                  icon: const Icon(AppIcons.follow, size: 18),
                                  label: Text(c.follow),
                                ),
                        ),
                      if (officer) ...[
                        if (widget.signedIn && club.isActive) const SizedBox(width: KSpace.s),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.onManage,
                            icon: const Icon(AppIcons.settings, size: 18),
                            label: Text(c.manage),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Membership requests live in the Members tab now, not
                  // as a full-width button under the header.
                  if (officer && !club.isActive) ...[
                    const SizedBox(height: KSpace.m),
                    ClubStatusBanner(status: club.status),
                  ],
                  const SizedBox(height: KSpace.s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: KSpace.xs),
        Flexible(
          child: SelectableText(text,
              maxLines: 1, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;
  _TabBarDelegate(this.tabBar, this.background);

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: background,
        child: Column(children: [tabBar, const Divider(height: 1)]),
      );

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) => old.tabBar != tabBar || old.background != background;
}

/// Loading / error / empty / content for a tab.
class _AsyncTab<T> extends StatelessWidget {
  final Future<List<T>> future;
  final Widget empty;
  final Widget Function(List<T>) builder;
  const _AsyncTab({required this.future, required this.empty, required this.builder});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Padding(padding: const EdgeInsets.all(KSpace.l), child: KSkeleton.lines(4));
          }
          if (snap.hasError) {
            return BrandEmptyState(icon: AppIcons.error, title: context.l10n.club.genericError, compact: true);
          }
          if (snap.data!.isEmpty) return empty;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: builder(snap.data!)),
          );
        },
      );
}

class _PostsTab extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final bool canClubPin;
  final VoidCallback onClubPinChanged;
  const _PostsTab({
    required this.future,
    required this.canClubPin,
    required this.onClubPinChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return _AsyncTab<Map<String, dynamic>>(
      future: future,
      empty: BrandEmptyState(illo: AppIllo.emptyFeed, title: c.noAnnouncements, compact: true),
      builder: (posts) {
        final pinned = posts.where((p) => p['is_club_pinned'] == true).toList();
        final rest = posts.where((p) => p['is_club_pinned'] != true).toList();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: KSpace.s),
          children: [
            if (pinned.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, 0),
                child: Text(c.pinnedAnnouncement, style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final p in pinned)
                PostCard(
                  post: p,
                  onTap: () => context.goPost(p),
                  canClubPin: canClubPin,
                  onClubPinChanged: onClubPinChanged,
                ),
            ],
            for (final p in rest)
              PostCard(
                post: p,
                onTap: () => context.goPost(p),
                canClubPin: canClubPin,
                onClubPinChanged: onClubPinChanged,
              ),
          ],
        );
      },
    );
  }
}

class _CardsTab extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> future;
  final String emptyTitle;
  final AppIllo illo;
  final bool isEvent;
  const _CardsTab({required this.future, required this.emptyTitle, required this.illo, required this.isEvent});

  @override
  Widget build(BuildContext context) => _AsyncTab<Map<String, dynamic>>(
        future: future,
        empty: BrandEmptyState(illo: illo, title: emptyTitle, compact: true),
        builder: (rows) => LayoutBuilder(builder: (context, box) {
          final cols = Responsive.gridColumns(box.maxWidth, minTileWidth: 220);
          return GridView.builder(
            padding: const EdgeInsets.all(KSpace.l),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: KSpace.m,
              crossAxisSpacing: KSpace.m,
              childAspectRatio: 0.78,
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) => UniversalCard(
              data: rows[i],
              onTap: () => isEvent ? context.goEvent(rows[i]) : context.goItem(rows[i]),
            ),
          );
        }),
      );
}

class _MembersTab extends StatelessWidget {
  final Future<List<ClubMember>> future;

  /// Null when the viewer can't ask (guest, already a member, inactive
  /// club). When null, no request entry point is shown at all.
  final VoidCallback? onJoin;
  final bool pending;
  final bool joining;
  final bool recruitmentOpen;

  const _MembersTab({
    required this.future,
    this.onJoin,
    this.pending = false,
    this.joining = false,
    this.recruitmentOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final scheme = Theme.of(context).colorScheme;
    // The request entry point is a footer, not part of the roster list:
    // a club with no members still needs a way in, and joining should be
    // a deliberate look below the names rather than a header button.
    final footer = onJoin == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.m),
            child: pending
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(AppIcons.clock, size: 18),
                    label: Text(c.joinPending),
                  )
                : recruitmentOpen
                    ? FilledButton.tonalIcon(
                        onPressed: joining ? null : onJoin,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        icon: const Icon(AppIcons.person, size: 18),
                        label: Text(context.l10n.clubRequestJoin),
                      )
                    : Text(
                        context.l10n.clubRecruitmentClosed,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
          );

    return Column(
      children: [
        Expanded(
          child: _AsyncTab<ClubMember>(
            future: future,
            empty: BrandEmptyState(
                icon: AppIcons.people, title: c.tabMembers, compact: true),
            builder: (members) => ListView(
              padding: const EdgeInsets.symmetric(vertical: KSpace.s),
              children: [
                for (final m in members)
                  ListTile(
                    minTileHeight: 56,
                    leading: CircleAvatar(
                      backgroundColor: scheme.surfaceContainerHighest,
                      backgroundImage: m.avatarUrl == null
                          ? null
                          : CachedNetworkImageProvider(m.avatarUrl!),
                      child: m.avatarUrl == null
                          ? Icon(AppIcons.person,
                              size: 20, color: scheme.onSurfaceVariant)
                          : null,
                    ),
                    title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: m.username == null ? null : Text('@${m.username}'),
                    trailing: ClubPill(
                      c.rosterLabel(m.position, m.role),
                      background:
                          m.role == 'president' ? scheme.primaryContainer : null,
                      foreground:
                          m.role == 'president' ? scheme.onPrimaryContainer : null,
                    ),
                    onTap: () => context.goUser(m.userId),
                  ),
              ],
            ),
          ),
        ),
        if (footer != null) SafeArea(top: false, child: footer),
      ],
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(KSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KSkeleton(height: 140),
            const SizedBox(height: KSpace.l),
            const KSkeleton.circle(size: 72),
            const SizedBox(height: KSpace.m),
            const KSkeleton(width: 200, height: 22),
            const SizedBox(height: KSpace.s),
            KSkeleton.lines(3),
          ],
        ),
      );
}
