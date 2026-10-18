import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import 'brand/brand.dart';

/// What the rail shows: upcoming (or, failing that, recent) events and
/// fresh Market items.
class RightRailData {
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> items;
  final bool pastEvents;
  const RightRailData(this.events, this.items, {this.pastEvents = false});
}

typedef RightRailLoader = Future<RightRailData> Function();

/// Desktop right rail (≥ 1200): discovery next to the feed.
class RightRail extends StatefulWidget {
  static const double width = Responsive.rightRailWidth;

  /// Defaults to Supabase; tests inject a fake.
  final RightRailLoader? loader;

  const RightRail({super.key, this.loader});

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> {
  late Future<RightRailData> _future = _load();

  Future<RightRailData> _load() => (widget.loader ?? _fromSupabase)();

  void _refresh() => setState(() => _future = _load());

  static Future<RightRailData> _fromSupabase() async {
    final supabase = Supabase.instance.client;
    final now = DateTime.now().toUtc().toIso8601String();
    final results = await Future.wait([
      supabase
          .from('events')
          .select()
          .gt('end_datetime', now)
          .order('start_datetime', ascending: true)
          .limit(3),
      supabase
          .from('listings')
          .select()
          .eq('is_sold', false)
          .order('created_at', ascending: false)
          .limit(4),
    ]);
    var events = results[0];
    var past = false;
    // No upcoming events: show the most recent ones rather than nothing.
    if (events.isEmpty) {
      events = await supabase
          .from('events')
          .select()
          .order('start_datetime', ascending: false)
          .limit(3);
      past = events.isNotEmpty;
    }
    return RightRailData(events, results[1], pastEvents: past);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return SizedBox(
      width: RightRail.width,
      child: FutureBuilder<RightRailData>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final data = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: s.refresh,
                  onPressed: loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (snap.hasError)
                _RailCard(
                  child: Column(
                    children: [
                      Text(s.connectionError, textAlign: TextAlign.center),
                      TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(s.social.retry),
                      ),
                    ],
                  ),
                )
              else ...[
                _RailCard(
                  header: SectionHeader(
                    title: data?.pastEvents == true
                        ? s.pastEvents
                        : s.eventsThisWeek,
                    seeAllLabel: s.seeAll,
                    onSeeAll: () => context.go('/events'),
                    padding: EdgeInsets.zero,
                  ),
                  child: loading
                      ? const _SkeletonList()
                      : data!.events.isEmpty
                          ? const _RailEmpty()
                          : Column(
                              children: [
                                for (final e in data.events) _EventRow(e),
                              ],
                            ),
                ),
                const SizedBox(height: KSpace.l),
                _RailCard(
                  header: SectionHeader(
                    title: s.newInMarket,
                    seeAllLabel: s.seeAll,
                    onSeeAll: () => context.go('/market'),
                    padding: EdgeInsets.zero,
                  ),
                  child: loading
                      ? const _SkeletonGrid()
                      : data!.items.isEmpty
                          ? const _RailEmpty()
                          : _ItemGrid(data.items),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  final Widget? header;
  final Widget child;
  const _RailCard({this.header, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(KSpace.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: KRadius.cut,
        border: Border.all(color: KTokens.of(context).cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header!, const SizedBox(height: KSpace.s)],
          child,
        ],
      ),
    );
  }
}

class _RailEmpty extends StatelessWidget {
  const _RailEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpace.m),
      child: Text(context.l10n.shell.railNothing,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventRow(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = parseLocal(event['start_datetime']);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.goEvent(event),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: KSpace.xs),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.primary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(event['title'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall),
              Text(
                [
                  if (start != null) formatEventDate(start),
                  if ((event['location'] ?? '').toString().isNotEmpty)
                    event['location'],
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _ItemGrid(this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final item in items)
          Semantics(
            button: true,
            label: '${item['title'] ?? ''}, ${formatPrice(item['price'] as num?)}',
            child: InkWell(
              borderRadius: KRadius.cut,
              onTap: () => context.goItem(item),
              child: ClipRRect(
                borderRadius: KRadius.cut,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: item['image_url'] ?? '',
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      errorWidget: (_, __, ___) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.storefront, size: 20)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: photoScrim(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        child: Text(
                          formatPrice(item['price'] as num?),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: kOnPhoto, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < 3; i++) ...const [
            KSkeleton(width: 180, height: 14),
            SizedBox(height: KSpace.s),
            KSkeleton(width: 120, height: 10),
            SizedBox(height: KSpace.m),
          ],
        ],
      );
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: KSpace.s,
        crossAxisSpacing: KSpace.s,
        children: [
          for (int i = 0; i < 4; i++)
            const KSkeleton(height: 100, borderRadius: KRadius.cut),
        ],
      );
}
