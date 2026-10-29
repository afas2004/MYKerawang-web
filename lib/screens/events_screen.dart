import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'events_cubit.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/guest_access.dart';
import '../services/unread_notifications.dart';
import '../widgets/after_fonts_load.dart';
import '../widgets/profile_avatar_action.dart';
import '../widgets/shell_actions.dart';
import '../services/category_service.dart';
import '../utils/categories.dart';
import '../utils/event_live.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/error_state.dart';
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

class _EventsViewState extends State<EventsView>
    with RefreshOnContentChange {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<String> _tags = ['All', ...kCommonEventCategories];

  /// Past (ended / cancelled) events start collapsed at the bottom.
  bool _showPast = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Used by the empty state only; the one general Create entry is the
  /// shell's (centre button / rail / sidebar).
  /// Guests (if they ever reach this tab) are asked to sign in first.
  void _openCreate(BuildContext context) {
    if (requireLogin(context)) context.goCreateEvent();
  }

  // Lists refresh after something is published, edited or deleted.
  @override
  void onContentChanged() => context.read<EventsCubit>().loadData();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EventsCubit, EventsState>(
      builder: (context, state) {
        final s = context.l10n;
        return LayoutBuilder(builder: (context, constraints) {
          final withFilterColumn = constraints.maxWidth >= _kFilterColumnFrom;
          return Scaffold(
            appBar: KBand.appBar(
              context,
              tone: KBand.events,
              title: Text(s.navEvents),
              actions: [
                const ShellSearchButton(),
                const ShellClubsButton(),
                // Notifications only mean something when signed in.
                if (ShellAuth.of(context))
                  IconButton(
                    tooltip: s.notifications,
                    icon: const UnreadBadge(child: Icon(AppIcons.notifications)),
                    onPressed: () => context.goNotifications(),
                  ),
                // Avatar → your profile; guests get "Sign in".
                const ProfileAvatarAction(),
                const SizedBox(width: KSpace.s),
              ],
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
                        Expanded(child: _content(context, state)),
                      ],
                    )
                  : Column(
                      children: [
                        // Sticky: search, then the tag chips.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              KSpace.l, KSpace.s, KSpace.l, KSpace.s),
                          child: _searchField(context),
                        ),
                        _TagChipRow(tags: _tags, selected: state.selectedTag),
                        Expanded(child: _content(context, state)),
                      ],
                    ),
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
        prefixIcon: Icon(AppIcons.search, color: scheme.onSurfaceVariant),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: s.clearSearch,
                icon: const Icon(AppIcons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  context.read<EventsCubit>().updateSearch('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        isDense: true,
        border: const OutlineInputBorder(
            borderRadius: KRadius.pill, borderSide: BorderSide.none),
      ),
    );
  }

  Widget _content(BuildContext context, EventsState state) {
    final s = context.l10n;
    final cubit = context.read<EventsCubit>();

    if (state.isLoading && state.allEvents.isEmpty) {
      return const _EventListSkeleton();
    }
    if (state.errorMessage != null && state.allEvents.isEmpty) {
      return ErrorState(onRetry: cubit.loadData);
    }

    final now = DateTime.now();
    // Already sorted: upcoming soonest first, then past most recent first.
    final upcoming = <Map<String, dynamic>>[];
    final past = <Map<String, dynamic>>[];
    for (final e in state.displayedEvents) {
      (eventSectionOf(e, now: now) == EventSection.ended ? past : upcoming).add(e);
    }
    final filtered = state.searchQuery.isNotEmpty || state.selectedTag != 'All';

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1000 ? 3 : (width >= Responsive.mediumBreakpoint ? 2 : 1);
      final extent = EventCard.heightFor(MediaQuery.textScalerOf(context));

      Widget cards(List<Map<String, dynamic>> events) {
        Widget card(Map<String, dynamic> e) => EventCard(
              event: e,
              goingCount: state.goingCounts[e['id']],
              organiser: state.organisers[e['organizer_id']],
              onTap: () => context.goEvent(e),
            );
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
          sliver: columns == 1
              ? SliverList.separated(
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: KSpace.m),
                  itemBuilder: (_, i) => i < 3 ? KEntrance(index: i, child: card(events[i])) : card(events[i]),
                )
              : SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: KSpace.m,
                    mainAxisSpacing: KSpace.m,
                    mainAxisExtent: extent,
                  ),
                  itemCount: events.length,
                  itemBuilder: (_, i) => card(events[i]),
                ),
        );
      }

      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: KSpace.s)),
          if (upcoming.isEmpty)
            SliverToBoxAdapter(
              child: BrandEmptyState(
                icon: AppIcons.events,
                illo: AppIllo.noEvents,
                compact: past.isNotEmpty,
                title: s.noEventsFound,
                message: filtered ? null : s.noEventsYetHint,
                actionLabel: filtered ? null : s.createEvent,
                onAction: filtered ? null : () => _openCreate(context),
              ),
            )
          else
            cards(upcoming),

          // Past events: collapsed at the bottom, never the first thing.
          if (past.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(KSpace.s, KSpace.xl, KSpace.s, KSpace.s),
                child: ListTile(
                  shape: const RoundedRectangleBorder(borderRadius: KRadius.input),
                  leading: const Icon(AppIcons.history),
                  title: Text(s.pastEvents),
                  subtitle: Text(s.pastEventsCount.fill([past.length])),
                  trailing: AnimatedRotation(
                    turns: _showPast ? 0.25 : 0,
                    duration: KMotion.of(context).fast,
                    child: const Icon(AppIcons.chevronRight),
                  ),
                  onTap: () => setState(() => _showPast = !_showPast),
                ),
              ),
            ),
            if (_showPast) cards(past),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Event card
// ---------------------------------------------------------------------------

/// Event list card: a date block (month + day number) beside the title,
/// time, place and going count, with the cover as a small thumbnail.
/// Ended / cancelled events are muted and say so.
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

  /// Tile height for multi-column grids, scaled with the text size.
  /// (Two-line title, time, place, status row, organiser.)
  static double heightFor(TextScaler textScaler) => textScaler.scale(158) + KSpace.m * 2 + 4;

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
    final image = event['image_url'] as String?;

    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.all(KSpace.m),
      semanticLabel: title,
      child: Opacity(
        // Ended / cancelled stay visible but recede (spec §6)
        opacity: closed ? 0.65 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DateBlock(date: start, muted: closed),
            const SizedBox(width: KSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: KSpace.xs),
                  _iconLine(AppIcons.clock, timeText, meta, scheme),
                  const SizedBox(height: 2),
                  _iconLine(AppIcons.location,
                      (event['location'] ?? s.locationTba).toString(), meta, scheme),
                  const SizedBox(height: KSpace.s),
                  Wrap(
                    spacing: KSpace.s,
                    runSpacing: KSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (closed)
                        _Pill(cancelled ? s.cancelled : s.ended, muted: true)
                      else if (countdown != null)
                        CountdownChip(countdown),
                      // The door is open: the one thing worth knowing about an
                      // event you are standing next to.
                      if (!closed && checkinOpen(event))
                        _Pill(s.evCheckinOpen),
                      if (goingCount != null && goingCount! > 0)
                        _iconLine(AppIcons.people, s.goingCount.fill([goingCount]), meta, scheme,
                            shrink: true),
                    ],
                  ),
                  if (organiser != null) ...[
                    const SizedBox(height: KSpace.xs),
                    _OrganiserLine(profile: organiser!),
                  ],
                ],
              ),
            ),
            if (image != null && image.isNotEmpty) ...[
              const SizedBox(width: KSpace.m),
              ClipRRect(
                borderRadius: KRadius.small,
                child: CachedNetworkImage(
                  imageUrl: image,
                  width: 72,
                  height: 72,
                  memCacheWidth: 216,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => const SizedBox(width: 72, height: 72),
                ),
              ),
            ],
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
        const SizedBox(width: KSpace.xs),
        shrink ? Flexible(child: label) : Expanded(child: label),
      ],
    );
  }
}

/// Date block: short month over the day number, as a ticket stub — solid
/// plum with a perforated right edge. Shared by the list card and the event
/// page.
class DateBlock extends StatelessWidget {
  final DateTime date;
  final bool muted;
  final double size;

  const DateBlock({super.key, required this.date, this.muted = false, this.size = 56});

  static final _month = DateFormat('MMM');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = muted ? scheme.surfaceContainerHighest : scheme.primary;
    final fg = muted ? scheme.onSurfaceVariant : scheme.onPrimary;
    return ClipPath(
      clipper: const TicketStubClipper(),
      child: Container(
        width: size,
        padding: const EdgeInsets.symmetric(vertical: KSpace.s),
        decoration: BoxDecoration(color: bg, borderRadius: KRadius.input),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_month.format(date).toUpperCase(),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: fg, letterSpacing: 0.4, fontWeight: FontWeight.w600)),
            Text('${date.day}',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700, height: 1.15)),
          ],
        ),
      ),
    );
  }
}

/// A ticket's torn edge: small half-circle bites down the right side.
class TicketStubClipper extends CustomClipper<Path> {
  const TicketStubClipper();

  @override
  Path getClip(Size size) {
    const r = 2.5, step = 9.0;
    final holes = Path();
    for (double y = step / 2 + 2; y < size.height - 2; y += step) {
      holes.addOval(Rect.fromCircle(center: Offset(size.width, y), radius: r));
    }
    return Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), holes);
  }

  @override
  bool shouldReclip(TicketStubClipper oldClipper) => false;
}

/// Organiser name; clubs, staff and verified accounts get the verified
/// mark in the accent colour.
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
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (official) ...[
          const SizedBox(width: KSpace.xs),
          Tooltip(
            message: s.officialAccount,
            child: Icon(AppIcons.verified, size: 14, color: scheme.tertiary),
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

/// Small tonal pill for "Today" / "In 3 days" / "Happening now".
class CountdownChip extends StatelessWidget {
  final String label;
  const CountdownChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => _Pill(label, icon: AppIcons.clock);
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool muted;
  const _Pill(this.label, {this.icon, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = muted ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    final fg = muted ? scheme.onSurfaceVariant : scheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: KRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: KSpace.xs),
          ],
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters and loading
// ---------------------------------------------------------------------------

class _TagChipRow extends StatelessWidget {
  final List<String> tags;
  final String selected;
  const _TagChipRow({required this.tags, required this.selected});

  @override
  Widget build(BuildContext context) {
    // A selected category outside the common set keeps its chip.
    final shown = tags.contains(selected) ? tags : [...tags, selected];
    // Rebuilt once the web fonts load, or the labels keep their fallback
    // width and the last letter fades out.
    return AfterFontsLoad(child: SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KSpace.l, vertical: KSpace.xs),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: KSpace.s),
        itemBuilder: (context, i) => _tagChip(context, shown[i], selected),
      ),
    ));
  }
}

Widget _tagChip(BuildContext context, String tag, String selected) {
  final s = context.l10n;
  return FilterChip(
    label: Text(tag == 'All' ? s.all : CategoryService.labelOf('event', tag, s)),
    selected: selected == tag,
    showCheckmark: false,
    onSelected: (_) => context.read<EventsCubit>().updateTag(tag),
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
      padding: const EdgeInsets.all(KSpace.l),
      children: [
        search,
        const SizedBox(height: KSpace.xl),
        Text(s.filters, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: KSpace.m),
        Wrap(
          spacing: KSpace.s,
          runSpacing: KSpace.s,
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
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: KSpace.m),
        itemBuilder: (_, __) => KCard(
          padding: const EdgeInsets.all(KSpace.m),
          child: Row(
            children: [
              const KSkeleton(width: 56, height: 60, borderRadius: KRadius.input),
              const SizedBox(width: KSpace.m),
              Expanded(child: KSkeleton.lines(3)),
            ],
          ),
        ),
      ),
    );
  }
}
