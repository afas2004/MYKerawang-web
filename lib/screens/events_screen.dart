import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'create_event_screen.dart';
import 'events_cubit.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/categories.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/error_state.dart';
import '../widgets/status_badge.dart';
import '../widgets/brand/brand.dart';

/// "Today" / "Tomorrow" / "In 3 days" for upcoming events less than a
/// week away, "Happening now" while one runs; null otherwise. Counted in
/// calendar days, so 11pm tonight is still "Today".
String? eventCountdown(AppStrings s, Map<String, dynamic> event, {DateTime? now}) {
  if (isEventClosed(event)) return null;
  final start = parseLocal(event['start_datetime']);
  if (start == null) return null;
  final current = now ?? DateTime.now();
  if (!start.isAfter(current)) return s.eventHappeningNow;
  final days = DateUtils.dateOnly(start).difference(DateUtils.dateOnly(current)).inDays;
  if (days == 0) return s.eventToday;
  if (days == 1) return s.eventTomorrow;
  if (days < 7) return s.eventInDays.fill([days]);
  return null;
}

/// Which list section an event belongs to.
enum EventSection { thisWeek, later, ended }

EventSection eventSectionOf(Map<String, dynamic> event, {DateTime? now}) {
  if (isEventClosed(event)) return EventSection.ended;
  final start = parseLocal(event['start_datetime']);
  final current = now ?? DateTime.now();
  if (start == null) return EventSection.later;
  final days = DateUtils.dateOnly(start).difference(DateUtils.dateOnly(current)).inDays;
  return days < 7 ? EventSection.thisWeek : EventSection.later;
}

/// Layout widths (of the space this screen is given, not the window).
const double _kFilterColumnFrom = 900;
const double _kFilterColumnWidth = 240;

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Provide the Cubit
    return BlocProvider(
      create: (_) => EventsCubit(),
      child: const EventsView(),
    );
  }
}

class EventsView extends StatefulWidget {
  const EventsView({super.key});

  @override
  State<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends State<EventsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<String> _tags = ['All', ...kEventTags];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreate(BuildContext context) async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CreateEventScreen()));
    if (result == true && context.mounted) {
      context.read<EventsCubit>().loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EventsCubit, EventsState>(
      builder: (context, state) {
        final s = context.l10n;
        return LayoutBuilder(builder: (context, constraints) {
          final withFilterColumn = constraints.maxWidth >= _kFilterColumnFrom;
          return Scaffold(
            appBar: AppBar(
              title: Text(s.navEvents),
              // Desktop has no FAB, so creation lives here instead (H1.1).
              actions: [
                if (isWide(context))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: () => _openCreate(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.createEvent),
                    ),
                  ),
              ],
              bottom: withFilterColumn
                  ? LatticeBand.preferred()
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(52 + 9),
                      child: Column(
                        children: [
                          _TagChipRow(tags: _tags, selected: state.selectedTag),
                          const LatticeBand(),
                        ],
                      ),
                    ),
            ),
            body: LinearRefresher(
              offset: 0.0,
              onRefresh: () async => context.read<EventsCubit>().loadData(),
              child: withFilterColumn
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _kFilterColumnWidth,
                          child: _FilterColumn(
                            tags: _tags,
                            selected: state.selectedTag,
                            search: _searchField(context),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _content(context, state, withSearch: false)),
                      ],
                    )
                  : _content(context, state, withSearch: true),
            ),
            // Desktop creates from the header — a FAB floating in the
            // far corner of a wide window is a phone pattern (G5).
            floatingActionButton: isWide(context)
                ? null
                : FloatingActionButton(
                    heroTag: 'events_fab',
                    tooltip: s.createEvent,
                    onPressed: () => _openCreate(context),
                    child: const Icon(Icons.add),
                  ),
          );
        });
      },
    );
  }

  Widget _searchField(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) {
        context.read<EventsCubit>().updateSearch(v);
        setState(() {}); // show / hide the clear button
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: s.searchEvents,
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: s.clearSearch,
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  context.read<EventsCubit>().updateSearch('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _emptyState(BuildContext context, EventsState state) {
    final s = context.l10n;
    final filtered = state.searchQuery.isNotEmpty || state.selectedTag != 'All';
    return BrandEmptyState(
      icon: Icons.event_outlined,
      title: s.noEventsFound,
      message: filtered ? null : s.noEventsYetHint,
      actionLabel: filtered ? null : s.createEvent,
      onAction: filtered ? null : () => _openCreate(context),
    );
  }

  Widget _content(BuildContext context, EventsState state, {required bool withSearch}) {
    final s = context.l10n;
    final cubit = context.read<EventsCubit>();

    if (state.isLoading && state.allEvents.isEmpty) {
      return const _EventListSkeleton();
    }
    if (state.errorMessage != null && state.allEvents.isEmpty) {
      return ErrorState(onRetry: cubit.loadData);
    }

    final now = DateTime.now();
    final bySection = <EventSection, List<Map<String, dynamic>>>{
      for (final sec in EventSection.values) sec: [],
    };
    for (final e in state.displayedEvents) {
      bySection[eventSectionOf(e, now: now)]!.add(e);
    }

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1000 ? 3 : (width >= Responsive.mediumBreakpoint ? 2 : 1);
      const gap = KSpace.l;

      List<Widget> section(EventSection sec, String title) {
        final events = bySection[sec]!;
        if (events.isEmpty) return const [];
        Widget card(Map<String, dynamic> e) => EventCard(
              event: e,
              goingCount: state.goingCounts[e['id']],
              organiser: state.organisers[e['organizer_id']],
              onTap: () => context.goEvent(e),
            );
        return [
          SliverToBoxAdapter(
            child: SectionHeader(
              title: title,
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xl, KSpace.l, KSpace.m),
              trailing: Text('${events.length}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
            sliver: columns == 1
                ? SliverList.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: gap),
                    itemBuilder: (_, i) => card(events[i]),
                  )
                : SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                      mainAxisExtent: EventCard.gridExtent,
                    ),
                    itemCount: events.length,
                    itemBuilder: (_, i) => card(events[i]),
                  ),
          ),
        ];
      }

      return CustomScrollView(
        slivers: [
          if (withSearch)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _searchField(context),
              ),
            ),
          if (state.displayedEvents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState(context, state),
            ),
          ...section(EventSection.thisWeek, s.sectionThisWeek),
          ...section(EventSection.later, s.sectionLater),
          ...section(EventSection.ended, s.sectionEnded),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Event card
// ---------------------------------------------------------------------------

/// Date-led event card: a calendar block (day number in the display face)
/// beside the title, time, place, countdown, going count and organiser.
/// Used in the events list; sized to [gridExtent] in multi-column grids.
class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final int? goingCount;

  /// `profiles_public` row of the organiser, if loaded.
  final Map<String, dynamic>? organiser;
  final VoidCallback? onTap;

  const EventCard({
    super.key,
    required this.event,
    this.goingCount,
    this.organiser,
    this.onTap,
  });

  /// Fixed tile height for grid layouts.
  static const double gridExtent = 340;

  static final _time = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final start = parseLocal(event['start_datetime']) ?? DateTime.now();
    final end = parseLocal(event['end_datetime']);
    final cancelled = isEventCancelled(event);
    final closed = isEventClosed(event);
    final countdown = eventCountdown(s, event);
    final sameDay = end == null || DateUtils.isSameDay(start, end);
    final timeText = sameDay
        ? [_time.format(start), if (end != null) _time.format(end)].join(' – ')
        : formatEventRange(start, end);
    final meta = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final title = (event['title'] ?? '').toString();

    return Opacity(
      // Ended / cancelled stay visible but recede (spec §6)
      opacity: closed ? 0.6 : 1,
      child: KCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        // Official organisers get the gold frame + corner lattice.
        official: isOfficialProfile(organiser) && !closed,
        borderRadius: KRadius.cut,
        semanticLabel: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- cover ----
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: event['image_url'] ?? '',
                    memCacheWidth: 900, // decode at card size, not camera size
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(Icons.event, color: scheme.onSurfaceVariant, size: 36),
                      ),
                    ),
                  ),
                  if (closed)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: StatusBadge(cancelled ? s.cancelled : s.ended),
                    )
                  else if (countdown != null)
                    Positioned(top: 10, left: 10, child: CountdownChip(countdown)),
                ],
              ),
            ),

            // ---- date block + details ----
            Padding(
              padding: const EdgeInsets.all(KSpace.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DateBlock(date: start, muted: closed),
                  const SizedBox(width: KSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        _iconLine(Icons.schedule, timeText, meta, scheme),
                        const SizedBox(height: 2),
                        _iconLine(Icons.location_on_outlined,
                            (event['location'] ?? s.locationTba).toString(), meta, scheme),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (goingCount != null && goingCount! > 0)
                              _iconLine(Icons.group_outlined,
                                  s.goingCount.fill([goingCount]), meta, scheme,
                                  shrink: true),
                            if (organiser != null) _OrganiserLine(profile: organiser!),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconLine(IconData icon, String text, TextStyle? style, ColorScheme scheme,
      {bool shrink = false}) {
    final label = Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return Row(
      mainAxisSize: shrink ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        shrink ? Flexible(child: label) : Expanded(child: label),
      ],
    );
  }
}

/// Calendar block: weekday, big day number, month. Shared by the list
/// card and the event page.
class DateBlock extends StatelessWidget {
  final DateTime date;
  final bool muted;
  final double size;

  const DateBlock({super.key, required this.date, this.muted = false, this.size = 56});

  static final _month = DateFormat('MMM');
  static final _weekday = DateFormat('EEE');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = muted ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final fg = muted ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;
    return Container(
      width: size,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: KRadius.cut),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_weekday.format(date).toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: fg, letterSpacing: 1, fontWeight: FontWeight.w600)),
          Text('${date.day}',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.1)),
          Text(_month.format(date).toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: fg, letterSpacing: 1, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Organiser name with a gold "official" mark for clubs, staff and
/// verified accounts.
class _OrganiserLine extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _OrganiserLine({required this.profile});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final official = isOfficialProfile(profile);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            s.byOrganiser.fill([displayNameFor(s, profile)]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
                color: official ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: official ? FontWeight.w600 : null),
          ),
        ),
        if (official) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: s.officialAccount,
            child: Icon(Icons.verified, size: 14, color: scheme.tertiary),
          ),
        ],
      ],
    );
  }
}

/// Clubs, admins, owners and verified accounts get the official accent.
bool isOfficialProfile(Map<String, dynamic>? p) =>
    p != null &&
    (p['is_verified'] == true || const {'club', 'admin', 'owner'}.contains(p['role']));

/// Upcoming-soon marker on an event cover. Primary container rather than
/// the dark StatusBadge scrim, so "soon" never reads like "ended".
class CountdownChip extends StatelessWidget {
  final String label;
  const CountdownChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters, headers, empty and loading states
// ---------------------------------------------------------------------------

class _TagChipRow extends StatelessWidget {
  final List<String> tags;
  final String selected;
  const _TagChipRow({required this.tags, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: tags.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _tagChip(context, tags[i], selected),
      ),
    );
  }
}

Widget _tagChip(BuildContext context, String tag, String selected) {
  final scheme = Theme.of(context).colorScheme;
  final isSelected = selected == tag;
  return FilterChip(
    label: Text(tag == 'All' ? context.l10n.all : tag),
    selected: isSelected,
    onSelected: (_) => context.read<EventsCubit>().updateTag(tag),
    selectedColor: scheme.secondaryContainer,
    checkmarkColor: scheme.onSecondaryContainer,
    labelStyle: TextStyle(
      color: isSelected ? scheme.onSecondaryContainer : scheme.onSurface,
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
    ),
  );
}

/// Left column on wide layouts: search plus the tag filters.
class _FilterColumn extends StatelessWidget {
  final List<String> tags;
  final String selected;
  final Widget search;
  const _FilterColumn({required this.tags, required this.selected, required this.search});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        search,
        const SizedBox(height: 24),
        Text(s.filters, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tags) _tagChip(context, t, selected)],
        ),
      ],
    );
  }
}

/// Placeholder cards while the first load runs.
class _EventListSkeleton extends StatelessWidget {
  const _EventListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView.separated(
        padding: const EdgeInsets.all(KSpace.l),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: KSpace.l),
        itemBuilder: (_, __) => KCard(
          padding: EdgeInsets.zero,
          borderRadius: KRadius.cut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KSkeleton(height: 140, borderRadius: BorderRadius.zero),
              Padding(
                padding: const EdgeInsets.all(KSpace.m),
                child: Row(
                  children: [
                    const KSkeleton(width: 56, height: 64),
                    const SizedBox(width: KSpace.m),
                    Expanded(child: KSkeleton.lines(2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
