import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../theme/app_themes.dart' show kOnPhoto, photoScrim;
import '../../language_cubit.dart';
import '../../utils/app_nav.dart';
import '../../utils/formatters.dart';
import '../../utils/roles.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import '../../widgets/profile_avatar_action.dart';
import '../../widgets/shell_actions.dart';
import '../../widgets/tap_card.dart';
import 'announcements_repository.dart';
import 'hub_strings.dart';

/// Official news hub (tab 2): a hero carousel of pinned / featured posts,
/// official channel chips, category tabs, upcoming official events and the
/// announcement list. Readable by guests.
class AnnouncementsScreen extends StatefulWidget {
  /// Injected in tests; defaults to the Supabase-backed repository.
  final AnnouncementsRepository? repository;

  const AnnouncementsScreen({super.key, this.repository});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final AnnouncementsRepository _repo =
      widget.repository ?? AnnouncementsRepository();

  AnnouncementsData? _data;
  bool _loading = true;
  bool _failed = false;

  /// null = All.
  AnnouncementCategory? _category;

  /// Selected channel (author id); null = all channels.
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

  List<Announcement> _visible(AnnouncementsData d) => [
        for (final a in d.items)
          if ((_category == null || a.category == _category) &&
              (_channel == null || a.author['id'] == _channel))
            a,
      ];

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.hub.title),
        actions: [
          const ShellSearchButton(),
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(AppIcons.refresh),
            onPressed: _load,
          ),
          const ProfileAvatarAction(),
          const SizedBox(width: KSpace.s),
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
      return RefreshIndicator(
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
              ),
            ),
          ),
        ),
      );
    }

    final visible = _visible(data);
    final filtering = _category != null || _channel != null;
    final showEvents = data.upcomingEvents.isNotEmpty &&
        _channel == null &&
        (_category == null || _category == AnnouncementCategory.events);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (!filtering && data.featured.isNotEmpty)
            SliverToBoxAdapter(child: _HeroCarousel(items: data.featured)),
          if (data.channels.isNotEmpty)
            SliverToBoxAdapter(
              child: _ChannelRow(
                channels: data.channels,
                selected: _channel,
                onSelect: (id) => setState(() => _channel = id),
              ),
            ),
          SliverToBoxAdapter(
            child: _CategoryTabs(
              selected: _category,
              onSelect: (c) => setState(() => _category = c),
            ),
          ),
          if (showEvents)
            SliverToBoxAdapter(
              child: _UpcomingEvents(events: data.upcomingEvents),
            ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: KSpace.xl),
                child: BrandEmptyState(
                  compact: true,
                  icon: AppIcons.announcement,
                  title: s.hub.emptyFilterTitle,
                  message: s.hub.emptyFilterBody,
                ),
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
                    AnnouncementCard(announcement: visible[i]),
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
      AnnouncementCategory.clubs => s.hub.catClubs,
      AnnouncementCategory.events => s.hub.catEvents,
    };

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
            aspectRatio: 16 / 8,
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
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final image = item.imageUrl;
    final title = (item.post['title'] as String?)?.trim().isNotEmpty == true
        ? item.post['title'] as String
        : (item.post['body'] as String? ?? '');

    return TapCard(
      borderRadius: KRadius.card,
      onTap: () => context.goPost(item.post),
      semanticLabel: title,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              memCacheWidth: 1000,
              errorWidget: (_, __, ___) => _HeroFallback(scheme: scheme),
            )
          else
            _HeroFallback(scheme: scheme),
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
                  _Pill(
                    label: item.pinned ? s.hub.pinned : s.hub.featured,
                    icon: item.pinned ? AppIcons.pin : AppIcons.sparkle,
                  ),
                  const SizedBox(width: KSpace.s),
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
                  '${displayNameFor(s, item.author)} · ${formatRelative(context, item.createdAt)}',
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

class _HeroFallback extends StatelessWidget {
  final ColorScheme scheme;
  const _HeroFallback({required this.scheme});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.35)!],
          ),
        ),
        child: Align(
          alignment: const Alignment(0.85, -0.6),
          child: Icon(AppIcons.announcement,
              size: 56, color: kOnPhoto.withValues(alpha: 0.25)),
        ),
      );
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

class _ChannelRow extends StatelessWidget {
  final List<Map<String, dynamic>> channels;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _ChannelRow({
    required this.channels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: s.hub.channels),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: KSpace.s),
                child: ChoiceChip(
                  label: Text(s.hub.allChannels),
                  selected: selected == null,
                  onSelected: (_) => onSelect(null),
                ),
              ),
              for (final c in channels)
                Padding(
                  padding: const EdgeInsets.only(right: KSpace.s),
                  child: ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: c['avatar_url'] != null
                          ? CachedNetworkImageProvider(c['avatar_url'] as String)
                          : null,
                      child: c['avatar_url'] == null
                          ? Icon(AppIcons.people,
                              size: 12, color: theme.colorScheme.onPrimaryContainer)
                          : null,
                    ),
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(displayNameFor(s, c)),
                      if (c['is_verified'] == true) ...[
                        const SizedBox(width: 4),
                        Icon(AppIcons.verified,
                            size: 14, color: KTokens.of(context).accent),
                      ],
                    ]),
                    selected: selected == c['id'],
                    onSelected: (on) => onSelect(on ? c['id'] as String : null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ categories

class _CategoryTabs extends StatelessWidget {
  final AnnouncementCategory? selected;
  final ValueChanged<AnnouncementCategory?> onSelect;

  const _CategoryTabs({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final options = <(AnnouncementCategory?, String)>[
      (null, s.hub.catAll),
      for (final c in AnnouncementCategory.values) (c, categoryLabel(s, c)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: KSpace.m),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter),
          children: [
            for (final (value, label) in options)
              Padding(
                padding: const EdgeInsets.only(right: KSpace.s),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected == value,
                  showCheckmark: false,
                  onSelected: (_) => onSelect(value),
                ),
              ),
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
    final scheme = theme.colorScheme;
    final start = parseLocal(event['start_datetime']);
    final image = event['image_url'] as String?;
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
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: scheme.surfaceContainerHighest),
                    )
                  : ColoredBox(
                      color: scheme.primaryContainer,
                      child: Icon(AppIcons.events,
                          color: scheme.onPrimaryContainer)),
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

/// One announcement in the list: category label, official badge, author,
/// date, title and a two-line preview; pinned ones carry the accent frame.
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  const AnnouncementCard({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final a = announcement;
    final title = (a.post['title'] as String?)?.trim() ?? '';
    final body = (a.post['body'] as String?)?.trim() ?? '';
    final image = a.imageUrl;

    return KCard(
      official: a.pinned,
      officialLabel: a.pinned ? s.hub.pinned : null,
      onTap: () => context.goPost(a.post),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(categoryLabel(s, a.category).toUpperCase(),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.tertiary)),
                  const SizedBox(width: KSpace.s),
                  Flexible(
                    child: Text(formatRelative(context, a.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ),
                ]),
                const SizedBox(height: KSpace.xs + 2),
                if (title.isNotEmpty)
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: KSpace.xs),
                  Text(body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
                const SizedBox(height: KSpace.s),
                Row(children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage: a.author['avatar_url'] != null
                        ? CachedNetworkImageProvider(a.author['avatar_url'] as String)
                        : null,
                  ),
                  const SizedBox(width: KSpace.s),
                  Flexible(
                    child: Text(displayNameFor(s, a.author),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium),
                  ),
                  const SizedBox(width: KSpace.xs),
                  Tooltip(
                    message: s.hub.official,
                    child: Icon(AppIcons.verified,
                        size: 14, color: KTokens.of(context).accent),
                  ),
                ]),
              ],
            ),
          ),
          if (image != null) ...[
            const SizedBox(width: KSpace.m),
            ClipRRect(
              borderRadius: KRadius.small,
              child: CachedNetworkImage(
                imageUrl: image,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                memCacheWidth: 228,
                errorWidget: (_, __, ___) => const SizedBox(width: 76, height: 76),
              ),
            ),
          ],
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
              aspectRatio: 16 / 8,
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
