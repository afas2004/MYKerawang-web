import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_themes.dart' show kOnPhoto, photoScrim;
import '../../language_cubit.dart';
import '../../utils/app_nav.dart';
import '../../utils/club_mentions.dart';
import '../../utils/formatters.dart';
import '../../utils/url_rules.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/club_mention_chip.dart';
import '../../widgets/error_state.dart';
import '../../widgets/linear_refresher.dart';
import '../../widgets/profile_avatar_action.dart';
import '../../widgets/shell_actions.dart';
import '../../widgets/tap_card.dart';
import 'announcements_repository.dart';
import 'hub_strings.dart';

/// Official news hub: a hero carousel (featured → newest),
/// channel chips (clubs and staff), category tabs, upcoming official
/// events and the announcement list. Readable by guests; people allowed
/// to post announcements get a "New announcement" action.
class AnnouncementsScreen extends StatefulWidget {
  /// Injected in tests; defaults to the Supabase-backed repository.
  final AnnouncementsRepository? repository;

  /// Injected in tests; defaults to the `can_post_announcement()` RPC.
  final Future<bool> Function()? canPost;

  const AnnouncementsScreen({super.key, this.repository, this.canPost});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final AnnouncementsRepository _repo =
      widget.repository ?? AnnouncementsRepository();

  AnnouncementsData? _data;
  bool _loading = true;
  bool _failed = false;
  bool _canPost = false;

  /// null = All.
  AnnouncementCategory? _category;

  /// Selected channel key ('club:…' / 'user:…'); null = all.
  String? _channel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _failed = false;
    });
    unawaited(_checkCanPost());
    try {
      final data = await _repo.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Announcements load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _data == null;
      });
    }
  }

  Future<void> _checkCanPost() async {
    final ok = await (widget.canPost ?? canPostAnnouncement)();
    if (mounted && ok != _canPost) setState(() => _canPost = ok);
  }

  Future<void> _newAnnouncement() async {
    await context.push('/create/announcement');
    if (mounted) _load();
  }

  /// A club's chip acts as its front page: its pinned post leads.
  List<Announcement> _visible(AnnouncementsData d) {
    final rows = [
      for (final a in d.items)
        if ((_category == null || a.category == _category) &&
            (_channel == null || a.channel?.key == _channel))
          a,
    ];
    if (!_showClubPins) return rows;
    return [
      ...rows.where((a) => a.clubPinned),
      ...rows.where((a) => !a.clubPinned),
    ];
  }

  bool get _showClubPins => _channel?.startsWith('club:') ?? false;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: KBand.appBar(
        context,
        tone: KBand.news,
        title: Text(s.hub.title),
        actions: [
          const ShellSearchButton(),
          const ShellClubsButton(),
          if (_canPost)
            IconButton(
              tooltip: s.hub.newAnnouncement,
              icon: const Icon(AppIcons.compose),
              onPressed: _newAnnouncement,
            ),
          // No refresh button: pull down to refresh, like every other tab.
          const ProfileAvatarAction(),
          const SizedBox(width: KSpace.s),
        ],
        desktopActions: [
          if (_canPost)
            FilledButton.tonalIcon(
              onPressed: _newAnnouncement,
              icon: const Icon(AppIcons.compose, size: 18),
              label: Text(s.hub.newAnnouncement),
            ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.l10n;
    if (_loading) return const _HubSkeleton();
    if (_failed) return ErrorState(onRetry: _load);

    final data = _data ?? AnnouncementsData.empty;
    if (data.items.isEmpty && data.upcomingEvents.isEmpty) {
      return LinearRefresher(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: c.maxHeight,
              child: BrandEmptyState(
                illo: AppIllo.emptyFeed,
                title: s.hub.emptyTitle,
                message: s.hub.emptyBody,
                actionLabel: _canPost ? s.hub.newAnnouncement : null,
                onAction: _canPost ? _newAnnouncement : null,
              ),
            ),
          ),
        ),
      );
    }

    final visible = _visible(data);
    final filtering = _category != null || _channel != null;
    final channels = data.channels;
    final showEvents = data.upcomingEvents.isNotEmpty &&
        _channel == null &&
        (_category == null || _category == AnnouncementCategory.event);

    return LinearRefresher(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!filtering && data.featured.isNotEmpty)
            SliverToBoxAdapter(child: _HeroCarousel(items: data.featured)),
          SliverToBoxAdapter(
            child: _FilterRow(
              category: _category,
              channels: channels,
              channel: _channel,
              onCategory: (c) => setState(() => _category = c),
              onChannel: (key) => setState(() => _channel = key),
              onAll: () => setState(() {
                _category = null;
                _channel = null;
              }),
            ),
          ),
          if (showEvents)
            SliverToBoxAdapter(
              child: _UpcomingEvents(events: data.upcomingEvents),
            ),
          if (data.legacy && visible.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    KSpace.gutter, KSpace.m, KSpace.gutter, 0),
                child: Text(s.hub.earlierPosts,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: KSpace.l),
                child: _CategoryEmpty(category: _category),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  KSpace.gutter, KSpace.s, KSpace.gutter, KSpace.xxl),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: KSpace.m),
                itemBuilder: (context, i) =>
                    AnnouncementCard(
                        announcement: visible[i], showClubPin: _showClubPins),
              ),
            ),
        ],
      ),
    );
  }
}

/// Label for a category tab / card.
String categoryLabel(AppStrings s, AnnouncementCategory c) => switch (c) {
      AnnouncementCategory.kolej => s.hub.catKolej,
      AnnouncementCategory.jpk => s.hub.catJpk,
      AnnouncementCategory.club => s.hub.catClubs,
      AnnouncementCategory.event => s.hub.catEvents,
      AnnouncementCategory.general => s.hub.catGeneral,
    };

/// Each category's colour, from the brand palette. Used for the card rail
/// and the no-photo cover; lifted on dark themes so the rail still reads.
Color categoryColor(AnnouncementCategory c, [Brightness b = Brightness.light]) {
  final base = switch (c) {
    AnnouncementCategory.kolej => KPalette.plum,
    AnnouncementCategory.jpk => KPalette.biruLaut,
    AnnouncementCategory.club => KPalette.jingga,
    AnnouncementCategory.event => KPalette.hijauPucuk,
    AnnouncementCategory.general => KPalette.kelabuArang,
  };
  return b == Brightness.dark ? Color.lerp(base, Colors.white, 0.45)! : base;
}

IconData categoryIcon(AnnouncementCategory c) => switch (c) {
      AnnouncementCategory.kolej => AppIcons.official,
      AnnouncementCategory.jpk => AppIcons.people,
      AnnouncementCategory.club => AppIcons.sparkle,
      AnnouncementCategory.event => AppIcons.events,
      AnnouncementCategory.general => AppIcons.announcement,
    };

/// Opens an announcement's action link in a new tab / the browser app.
///
/// The link is DB text, so it goes through the same scheme allowlist as every
/// other remote link: a host-less `https:javascript:…` is not launchable.
Future<void> openAnnouncementLink(Uri url) async {
  final safe = launchableUri(url.toString());
  if (safe == null) return;
  await launchUrl(safe, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
}

class _CategoryEmpty extends StatelessWidget {
  final AnnouncementCategory? category;
  const _CategoryEmpty({required this.category});

  @override
  Widget build(BuildContext context) {
    final h = context.l10n.hub;
    final title = switch (category) {
      null => h.emptyFilterTitle,
      AnnouncementCategory.kolej => h.emptyKolej,
      AnnouncementCategory.jpk => h.emptyJpk,
      AnnouncementCategory.club => h.emptyClub,
      AnnouncementCategory.event => h.emptyEvent,
      AnnouncementCategory.general => h.emptyGeneral,
    };
    return BrandEmptyState(
      compact: true,
      icon: category == null ? AppIcons.announcement : categoryIcon(category!),
      title: title,
      message: category == null ? h.emptyFilterBody : h.emptyCategoryBody,
    );
  }
}

// ---------------------------------------------------------------- hero

class _HeroCarousel extends StatefulWidget {
  final List<Announcement> items;
  const _HeroCarousel({required this.items});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;
  Timer? _auto;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Gentle auto-advance, never under reduced motion.
    _auto?.cancel();
    if (widget.items.length > 1 && !KMotion.reduced(context)) {
      _auto = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!_controller.hasClients) return;
        final next = (_page + 1) % widget.items.length;
        _controller.animateToPage(next,
            duration: const Duration(milliseconds: 400), curve: KMotion.curve);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: KSpace.s),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
                child: _HeroSlide(item: widget.items[i]),
              ),
            ),
          ),
          if (widget.items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: KSpace.s),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    AnimatedContainer(
                      duration: KMotion.of(context).fast,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? scheme.primary : scheme.outlineVariant,
                        borderRadius: KRadius.pill,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  final Announcement item;
  const _HeroSlide({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.l10n;
    final cover = item.coverUrl;
    final title = item.title.isNotEmpty ? item.title : _excerpt(item.body);
    final badge = item.featured ? (s.hub.featured, AppIcons.sparkle) : null;

    return TapCard(
      borderRadius: KRadius.card,
      onTap: () => context.goPost(item.post),
      semanticLabel: title,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            CachedNetworkImage(
              imageUrl: cover,
              fit: BoxFit.cover,
              memCacheWidth: 1200,
              errorWidget: (_, __, ___) => _CategoryCover(category: item.category),
            )
          else
            _CategoryCover(category: item.category),
          // Legibility wash for the text sitting on the photo.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [photoScrim(0), photoScrim(0.72)],
                stops: const [0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: KSpace.l,
            right: KSpace.l,
            bottom: KSpace.l,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (badge != null) ...[
                    _Pill(label: badge.$1, icon: badge.$2),
                    const SizedBox(width: KSpace.s),
                  ],
                  _Pill(label: categoryLabel(s, item.category)),
                ]),
                const SizedBox(height: KSpace.s),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: kOnPhoto, fontSize: 20),
                ),
                const SizedBox(height: KSpace.xs),
                Text(
                  [
                    if (item.channel != null) item.channel!.name,
                    formatRelative(context, item.publishedAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: kOnPhoto.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// No cover photo: the category's colour and its icon (no pattern — the
/// ground carries that — and no gradient placeholder).
class _CategoryCover extends StatelessWidget {
  final AnnouncementCategory category;
  const _CategoryCover({required this.category});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: categoryColor(category),
      child: Align(
        alignment: const Alignment(0.85, -0.6),
        child: Icon(categoryIcon(category),
            size: 56, color: kOnPhoto.withValues(alpha: 0.3)),
      ),
    );
  }
}

/// Small translucent label on the hero photo.
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _Pill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s + 2, vertical: 3),
      decoration: BoxDecoration(
        color: photoScrim(0.45),
        borderRadius: KRadius.pill,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: KTokens.of(context).accent),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: kOnPhoto)),
      ]),
    );
  }
}

// ------------------------------------------------------------ channels

class _ChannelAvatar extends StatelessWidget {
  final AnnouncementChannel channel;
  final double radius;
  const _ChannelAvatar({required this.channel, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = channel.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage:
          url != null && url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url == null || url.isEmpty
          ? Icon(channel.isClub ? AppIcons.people : AppIcons.official,
              size: radius, color: scheme.onPrimaryContainer)
          : null,
    );
  }
}

// --------------------------------------------------------------- filters

/// One row of filters: All, the categories, then the official channels
/// (with their avatars) after a thin divider. All clears both; a category
/// and a channel can be combined.
class _FilterRow extends StatelessWidget {
  final AnnouncementCategory? category;
  final List<AnnouncementChannel> channels;
  final String? channel;
  final ValueChanged<AnnouncementCategory?> onCategory;
  final ValueChanged<String?> onChannel;
  final VoidCallback onAll;

  const _FilterRow({
    required this.category,
    required this.channels,
    required this.channel,
    required this.onCategory,
    required this.onChannel,
    required this.onAll,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    Widget gap(Widget child) =>
        Padding(padding: const EdgeInsets.only(right: KSpace.s), child: child);
    return Padding(
      padding: const EdgeInsets.only(top: KSpace.m),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter),
          children: [
            gap(ChoiceChip(
              label: Text(s.hub.catAll),
              selected: category == null && channel == null,
              showCheckmark: false,
              onSelected: (_) => onAll(),
            )),
            for (final c in AnnouncementCategory.values)
              gap(ChoiceChip(
                label: Text(categoryLabel(s, c)),
                selected: category == c,
                showCheckmark: false,
                onSelected: (on) => onCategory(on ? c : null),
              )),
            if (channels.isNotEmpty)
              Center(
                child: Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.only(right: KSpace.s),
                  color: scheme.outlineVariant,
                ),
              ),
            for (final c in channels)
              gap(ChoiceChip(
                avatar: _ChannelAvatar(channel: c, radius: 12),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c.name),
                  if (c.verified) ...[
                    const SizedBox(width: 4),
                    Icon(AppIcons.verified,
                        size: 14, color: KTokens.of(context).accent),
                  ],
                ]),
                selected: channel == c.key,
                showCheckmark: false,
                onSelected: (on) => onChannel(on ? c.key : null),
              )),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------- upcoming events

class _UpcomingEvents extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const _UpcomingEvents({required this.events});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: s.hub.upcomingOfficial,
          onSeeAll: () => context.go('/events'),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(width: KSpace.m),
            itemBuilder: (context, i) => _EventTile(event: events[i]),
          ),
        ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = parseLocal(event['start_datetime']);
    final image = event['image_url'] as String?;
    final seed = '${event['id'] ?? event['title']}';
    // No photo: the same calm tint cover as Home's event cards.
    final tint = KTintCover(seed: seed, color: KPalette.forKey(seed));
    return SizedBox(
      width: 220,
      child: KCard(
        padding: EdgeInsets.zero,
        onTap: () => context.goEvent(event),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 104,
              width: double.infinity,
              child: image != null && image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      memCacheWidth: 500,
                      errorWidget: (_, __, ___) => tint,
                    )
                  : tint,
            ),
            Padding(
              padding: const EdgeInsets.all(KSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event['title'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: KSpace.xs),
                  if (start != null)
                    Text(formatEventDate(start),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ list card

/// One announcement: category, club/author (verified badge), date, title,
/// two-line preview, cover thumbnail and the first action link as a small
/// CTA. Pinned ones carry the accent frame.
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;

  /// Under a club's chip: mark the club's pinned post.
  final bool showClubPin;

  /// Opens an external CTA link; tests inject a recorder.
  final Future<void> Function(Uri url) openLink;

  /// Opens an in-app CTA path; defaults to `context.push(path)`.
  final void Function(BuildContext context, String path)? openPath;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    this.showClubPin = false,
    this.openLink = openAnnouncementLink,
    this.openPath,
  });

  void _open(BuildContext context, AnnouncementLink link) {
    if (link.isInternal) {
      (openPath ?? (c, p) => c.push(p))(context, link.path!);
    } else {
      openLink(link.url!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final a = announcement;
    final cover = a.coverUrl;
    final cta = a.links.isEmpty ? null : a.links.first;
    final channel = a.channel;

    return KCard(
      official: showClubPin && a.clubPinned,
      officialLabel: showClubPin && a.clubPinned ? s.hub.pinned : null,
      onTap: () => context.goPost(a.post),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      // Category colour rail.
                      Container(
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(
                          color: categoryColor(a.category, theme.brightness),
                          borderRadius: const BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(width: KSpace.s),
                      Text(categoryLabel(s, a.category),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: scheme.tertiary)),
                      const SizedBox(width: KSpace.s),
                      Flexible(
                        child: Text(formatRelative(context, a.publishedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ),
                    ]),
                    const SizedBox(height: KSpace.xs + 2),
                    if (a.title.isNotEmpty)
                      Text(a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                    if (a.body.isNotEmpty) ...[
                      const SizedBox(height: KSpace.xs),
                      Text(_excerpt(a.body),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (cover != null) ...[
                const SizedBox(width: KSpace.m),
                ClipRRect(
                  borderRadius: KRadius.small,
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    memCacheWidth: 228,
                    errorWidget: (_, __, ___) =>
                        const SizedBox(width: 76, height: 76),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: KSpace.s),
          Row(children: [
            if (channel != null) ...[
              _ChannelAvatar(channel: channel, radius: 10),
              const SizedBox(width: KSpace.s),
              Flexible(
                child: Text(channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium),
              ),
              if (channel.verified) ...[
                const SizedBox(width: KSpace.xs),
                Tooltip(
                  message: s.hub.official,
                  child: Icon(AppIcons.verified,
                      size: 14, color: KTokens.of(context).accent),
                ),
              ],
            ] else
              const Spacer(),
            if (cta != null) ...[
              const SizedBox(width: KSpace.s),
              if (channel != null) const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _open(context, cta),
                icon: Icon(
                    cta.isInternal ? AppIcons.forward : AppIcons.externalLink,
                    size: 14),
                label: Text(cta.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- loading

class _HubSkeleton extends StatelessWidget {
  const _HubSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.hub.title,
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(KSpace.gutter),
          children: [
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: KSkeleton(borderRadius: KRadius.card),
            ),
            const SizedBox(height: KSpace.xl),
            Row(children: const [
              KSkeleton(width: 90, height: 32, borderRadius: KRadius.pill),
              SizedBox(width: KSpace.s),
              KSkeleton(width: 110, height: 32, borderRadius: KRadius.pill),
              SizedBox(width: KSpace.s),
              KSkeleton(width: 80, height: 32, borderRadius: KRadius.pill),
            ]),
            const SizedBox(height: KSpace.xl),
            for (var i = 0; i < 3; i++) ...[
              KCard(child: KSkeleton.lines(3)),
              const SizedBox(height: KSpace.m),
            ],
          ],
        ),
      ),
    );
  }
}

/// A body shown as plain text: club mentions read as the club's name.
String _excerpt(String body) {
  ClubMentionDirectory.ensureLoaded();
  return plainClubMentions(body, ClubMentionDirectory.names);
}
