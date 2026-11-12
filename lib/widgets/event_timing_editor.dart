import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_strings.dart';
import '../l10n/event_timing_strings.dart';
import '../language_cubit.dart';
import '../utils/event_series.dart';
import '../utils/formatters.dart';
import 'brand/brand.dart';

/// Everything the Create event form knows about *when*: the timing mode,
/// the dates it makes, and when registration closes. The form reads
/// [sessions] and [deadlineAt] when publishing, so what the organiser sees
/// in the list is exactly what gets published.
class EventTimingController extends ChangeNotifier {
  EventTimingController({
    required DateTime start,
    required DateTime end,
    this.locked = false,
    this.close = CloseRule.atStart,
    this.closeAt,
  })  : _start = start,
        _end = end,
        firstDate = dateOnly(start),
        untilDate = dateOnly(start).add(const Duration(days: 56)),
        weekdays = {start.weekday},
        from = TimeOfDay.fromDateTime(start),
        to = TimeOfDay.fromDateTime(end),
        picked = [SessionSlot(start, end)];

  /// Editing one date of a published series: only that date's own start and
  /// end can change here.
  final bool locked;

  TimingMode _mode = TimingMode.once;
  TimingMode get mode => _mode;
  set mode(TimingMode m) {
    if (locked || m == _mode) return;
    _mode = m;
    notifyListeners();
  }

  bool get isSeries => _mode != TimingMode.once;

  // ---- once
  DateTime _start;
  DateTime _end;
  DateTime get start => _start;
  DateTime get end => _end;
  void setStart(DateTime v) {
    final length = _end.difference(_start);
    _start = v;
    if (!_end.isAfter(v)) {
      _end = v.add(length.isNegative || length == Duration.zero ? const Duration(hours: 2) : length);
    }
    notifyListeners();
  }

  void setEnd(DateTime v) {
    _end = v;
    notifyListeners();
  }

  // ---- repeats
  Set<int> weekdays;
  int everyWeeks = 1;
  DateTime firstDate;
  DateTime untilDate;
  TimeOfDay from;
  TimeOfDay to;
  final Set<DateTime> skipped = {};
  final List<SessionSlot> extras = [];

  void toggleWeekday(int d) {
    weekdays.contains(d) ? weekdays.remove(d) : weekdays.add(d);
    notifyListeners();
  }

  void setEvery(int n) {
    everyWeeks = n.clamp(1, 4);
    notifyListeners();
  }

  void setFirstDate(DateTime d) {
    firstDate = dateOnly(d);
    if (untilDate.isBefore(firstDate)) untilDate = firstDate;
    notifyListeners();
  }

  void setUntilDate(DateTime d) {
    untilDate = dateOnly(d);
    notifyListeners();
  }

  void setTimes({TimeOfDay? from, TimeOfDay? to}) {
    if (from != null) this.from = from;
    if (to != null) this.to = to;
    notifyListeners();
  }

  void toggleSkip(DateTime day) {
    final d = dateOnly(day);
    skipped.contains(d) ? skipped.remove(d) : skipped.add(d);
    notifyListeners();
  }

  void addExtra(SessionSlot s) {
    extras.add(SessionSlot(s.start, s.end, extra: true));
    notifyListeners();
  }

  void removeExtra(SessionSlot s) {
    extras.remove(s);
    notifyListeners();
  }

  List<DateTime> get patternDays => weeklyDates(
      first: firstDate, until: untilDate, weekdays: weekdays, everyWeeks: everyWeeks);

  // ---- pick dates
  final List<SessionSlot> picked;

  void addPicked(SessionSlot s) {
    picked.add(s);
    picked.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  void replacePicked(int i, SessionSlot s) {
    picked[i] = s;
    picked.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  void removePicked(int i) {
    picked.removeAt(i);
    notifyListeners();
  }

  // ---- the result

  /// Exactly the dates that will be published, soonest first.
  List<SessionSlot> get sessions => switch (_mode) {
        TimingMode.once => [SessionSlot(_start, _end)],
        TimingMode.repeats => weeklySessions(
            days: patternDays,
            fromHour: from.hour,
            fromMinute: from.minute,
            toHour: to.hour,
            toMinute: to.minute,
            skipped: skipped,
            extras: extras,
          ),
        TimingMode.dates => List.of(picked),
      };

  SessionsIssue get issue {
    if (_mode == TimingMode.repeats && weekdays.isEmpty && extras.isEmpty) {
      return SessionsIssue.empty;
    }
    return checkSessions(sessions);
  }

  // ---- registration closes
  CloseRule close;

  /// The exact time for a one-off event.
  DateTime? closeAt;

  /// The gap before each date of a series.
  Duration closeBefore = const Duration(days: 1);

  void setClose(CloseRule r) {
    close = r;
    if (r == CloseRule.setTime && closeAt == null) {
      closeAt = _start.subtract(const Duration(hours: 1));
    }
    notifyListeners();
  }

  void setCloseAt(DateTime d) {
    closeAt = d;
    notifyListeners();
  }

  void setCloseBefore(Duration d) {
    closeBefore = d;
    notifyListeners();
  }

  /// The `join_deadline` for a date starting at [s]: an exact time for a
  /// one-off event, a gap before each date for a series.
  DateTime? deadlineAt(DateTime s) => isSeries
      ? deadlineFor(close, s, before: closeBefore)
      : deadlineFor(close, s, setTime: closeAt);

  /// A set time after the start makes no sense for a one-off event.
  bool get closeAfterStart =>
      !isSeries && close == CloseRule.setTime && closeAt != null && closeAt!.isAfter(_start);

  /// Everything that can change, for the form's "unsaved changes" guard.
  String snapshot() => [
        _mode.name,
        for (final s in sessions) '${s.start.toIso8601String()}-${s.end.toIso8601String()}',
        close.name,
        closeAt?.toIso8601String(),
        closeBefore.inMinutes,
      ].join(',');
}

/// The "When" part of the Create event form.
class EventTimingEditor extends StatelessWidget {
  final EventTimingController controller;

  /// Shown under the list once the organiser has tried to publish.
  final bool showErrors;

  const EventTimingEditor({super.key, required this.controller, this.showErrors = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = context.l10n;
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!c.locked) ...[
              SegmentedButton<TimingMode>(
                key: const ValueKey('timing-mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: TimingMode.once, label: Text(s.tmOnce)),
                  ButtonSegment(value: TimingMode.repeats, label: Text(s.tmRepeats)),
                  ButtonSegment(value: TimingMode.dates, label: Text(s.tmDates)),
                ],
                selected: {c.mode},
                onSelectionChanged: (v) => c.mode = v.first,
              ),
              const SizedBox(height: KSpace.m),
            ],
            switch (c.mode) {
              TimingMode.once => _Once(c),
              TimingMode.repeats => _Repeats(c),
              TimingMode.dates => _PickDates(c),
            },
            if (c.isSeries) ...[
              const SizedBox(height: KSpace.s),
              _hint(context, s.tmSeriesNote),
            ],
            if (showErrors && c.issue != SessionsIssue.none) ...[
              const SizedBox(height: KSpace.s),
              Text(issueText(s, c.issue),
                  key: const ValueKey('timing-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        );
      },
    );
  }
}

String issueText(AppStrings s, SessionsIssue issue) => switch (issue) {
      SessionsIssue.empty => s.tmNeedDate,
      SessionsIssue.tooMany => s.tmTooMany(kMaxSeriesDates),
      SessionsIssue.endBeforeStart => s.tmEndBeforeStart,
      SessionsIssue.duplicate => s.tmDuplicate,
      SessionsIssue.none => '',
    };

Widget _hint(BuildContext context, String text) => Text(text,
    style: Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: KSpace.xs),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    );

final _dayFmt = DateFormat('EEE, d MMM yyyy');
final _timeFmt = DateFormat('h:mm a');

String _time(TimeOfDay t) => _timeFmt.format(DateTime(2000, 1, 1, t.hour, t.minute));

/// A filled, tappable field like the form's text inputs.
class PickerField extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final String? error;
  final Key? fieldKey;

  const PickerField(
      {super.key, required this.text, required this.icon, required this.onTap, this.error, this.fieldKey});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: scheme.surfaceContainer,
          borderRadius: KRadius.input,
          child: InkWell(
            key: fieldKey,
            borderRadius: KRadius.input,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(error!, style: TextStyle(color: scheme.error, fontSize: 12)),
          ),
      ],
    );
  }
}

Future<DateTime?> _pickDay(BuildContext context, DateTime initial) {
  final now = DateTime.now();
  final first = now.subtract(const Duration(days: 365));
  final last = now.add(const Duration(days: 730));
  final init = initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial);
  return showDatePicker(context: context, firstDate: first, lastDate: last, initialDate: init);
}

Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(context: context, initialTime: initial);

/// Date, then start time; the end keeps [length] after the start.
Future<SessionSlot?> _pickSlot(BuildContext context, DateTime day, TimeOfDay time, Duration length) async {
  final d = await _pickDay(context, day);
  if (d == null || !context.mounted) return null;
  final t = await _pickTime(context, time);
  if (t == null) return null;
  final start = atTime(d, t.hour, t.minute);
  return SessionSlot(start, start.add(length));
}

// ------------------------------------------------------------------ once

class _Once extends StatelessWidget {
  final EventTimingController c;
  const _Once(this.c);

  Future<DateTime?> _pick(BuildContext context, DateTime initial) async {
    final d = await _pickDay(context, initial);
    if (d == null || !context.mounted) return null;
    final t = await _pickTime(context, TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return atTime(d, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final badEnd = !c.end.isAfter(c.start);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start and end side by side at every width: two date fields fit
        // even on a small phone.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, s.starts),
                PickerField(
                  fieldKey: const ValueKey('once-start'),
                  text: formatEventDate(c.start),
                  icon: AppIcons.calendar,
                  onTap: () async {
                    final v = await _pick(context, c.start);
                    if (v != null) c.setStart(v);
                  },
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, s.ends),
                PickerField(
                  fieldKey: const ValueKey('once-end'),
                  text: formatEventDate(c.end),
                  icon: AppIcons.calendar,
                  error: badEnd ? s.mustBeAfterStart : null,
                  onTap: () async {
                    final v = await _pick(context, c.end);
                    if (v != null) c.setEnd(v);
                  },
                ),
              ]),
            ),
          ],
        ),
        if (!c.locked) ...[
          const SizedBox(height: KSpace.xs),
          _hint(context, s.tmOnceHint),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- repeats

class _Repeats extends StatelessWidget {
  final EventTimingController c;
  const _Repeats(this.c);

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final names = s.weekdaysShort;
    final sessions = c.sessions;
    final pattern = c.patternDays;
    // Skipped pattern days stay in the list, struck through, so they can
    // be brought back.
    final rows = <(DateTime, SessionSlot?, bool)>[
      for (final d in pattern)
        if (c.skipped.contains(dateOnly(d)))
          (d, null, true),
      for (final slot in sessions) (slot.start, slot, false),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var n = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, s.tmOn),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var d = DateTime.monday; d <= DateTime.sunday; d++)
              FilterChip(
                key: ValueKey('weekday-$d'),
                label: Text(names[d - 1]),
                selected: c.weekdays.contains(d),
                showCheckmark: false,
                onSelected: (_) => c.toggleWeekday(d),
              ),
          ],
        ),
        if (c.weekdays.isEmpty) ...[
          const SizedBox(height: 4),
          Text(s.tmNeedWeekday,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ],
        const SizedBox(height: KSpace.m),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context, s.tmFrom),
              PickerField(
                fieldKey: const ValueKey('repeat-from'),
                text: _time(c.from),
                icon: AppIcons.clock,
                onTap: () async {
                  final t = await _pickTime(context, c.from);
                  if (t != null) c.setTimes(from: t);
                },
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context, s.tmTo),
              PickerField(
                fieldKey: const ValueKey('repeat-to'),
                text: _time(c.to),
                icon: AppIcons.clock,
                onTap: () async {
                  final t = await _pickTime(context, c.to);
                  if (t != null) c.setTimes(to: t);
                },
              ),
            ]),
          ),
        ]),
        const SizedBox(height: KSpace.m),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context, s.tmEvery),
              Row(children: [
                IconButton.outlined(
                  tooltip: s.tmFewerWeeks,
                  onPressed: c.everyWeeks > 1 ? () => c.setEvery(c.everyWeeks - 1) : null,
                  icon: const Icon(Icons.remove, size: 18),
                ),
                Expanded(
                  child: Text(s.tmWeeks(c.everyWeeks),
                      key: const ValueKey('repeat-every'), textAlign: TextAlign.center),
                ),
                IconButton.outlined(
                  tooltip: s.tmMoreWeeks,
                  onPressed: c.everyWeeks < 4 ? () => c.setEvery(c.everyWeeks + 1) : null,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _label(context, s.tmFirstDate),
              PickerField(
                fieldKey: const ValueKey('repeat-first'),
                text: _dayFmt.format(c.firstDate),
                icon: AppIcons.calendar,
                onTap: () async {
                  final d = await _pickDay(context, c.firstDate);
                  if (d != null) c.setFirstDate(d);
                },
              ),
            ]),
          ),
        ]),
        const SizedBox(height: KSpace.m),
        _label(context, s.tmUntil),
        PickerField(
          fieldKey: const ValueKey('repeat-until'),
          text: _dayFmt.format(c.untilDate),
          icon: AppIcons.calendar,
          onTap: () async {
            final d = await _pickDay(context, c.untilDate);
            if (d != null) c.setUntilDate(d);
          },
        ),
        const SizedBox(height: KSpace.m),
        Row(children: [
          Expanded(child: _label(context, s.tmDatesLabel)),
          Text(s.tmSessions(sessions.length),
              key: const ValueKey('repeat-count'),
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        for (final (day, slot, off) in rows)
          _SessionRow(
            // Stable whether skipped or not, so the row keeps its place.
            key: ValueKey(slot != null && slot.extra
                ? 'repeat-extra-${slot.start.toIso8601String()}'
                : 'repeat-row-${dateOnly(day).toIso8601String()}'),
            number: off ? null : ++n,
            start: slot?.start ?? day,
            end: slot?.end,
            extra: slot?.extra ?? false,
            off: off,
            actionLabel: off ? s.tmUndoSkip : (slot!.extra ? s.tmRemoveDate : s.tmSkip),
            onAction: () =>
                slot != null && slot.extra ? c.removeExtra(slot) : c.toggleSkip(day),
          ),
        const SizedBox(height: KSpace.xs),
        _AddButton(
          key: const ValueKey('repeat-add'),
          label: s.tmAddExtra,
          onPressed: () async {
            final last = sessions.isEmpty ? c.firstDate : sessions.last.start;
            final length = Duration(
                minutes: (c.to.hour * 60 + c.to.minute) - (c.from.hour * 60 + c.from.minute));
            final slot = await _pickSlot(context, last.add(const Duration(days: 1)), c.from,
                length.inMinutes > 0 ? length : const Duration(hours: 2));
            if (slot != null) c.addExtra(slot);
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ pick dates

class _PickDates extends StatelessWidget {
  final EventTimingController c;
  const _PickDates(this.c);

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(context, s.tmDatesHint),
        const SizedBox(height: KSpace.s),
        for (var i = 0; i < c.picked.length; i++)
          _SessionRow(
            key: ValueKey('picked-row-$i'),
            number: i + 1,
            start: c.picked[i].start,
            end: c.picked[i].end,
            actionLabel: s.tmRemoveDate,
            onAction: c.picked.length > 1 ? () => c.removePicked(i) : null,
            onTapDate: () async {
              final d = await _pickDay(context, c.picked[i].start);
              if (d == null) return;
              final old = c.picked[i];
              final start = atTime(d, old.start.hour, old.start.minute);
              c.replacePicked(i, SessionSlot(start, start.add(old.end.difference(old.start))));
            },
            onTapTime: () async {
              final old = c.picked[i];
              final from = await _pickTime(context, TimeOfDay.fromDateTime(old.start));
              if (from == null || !context.mounted) return;
              final to = await _pickTime(context, TimeOfDay.fromDateTime(old.end));
              if (to == null) return;
              c.replacePicked(
                  i,
                  SessionSlot(atTime(old.start, from.hour, from.minute),
                      atTime(old.start, to.hour, to.minute)));
            },
          ),
        const SizedBox(height: KSpace.xs),
        if (c.picked.length < kMaxSeriesDates)
          _AddButton(
            key: const ValueKey('picked-add'),
            label: s.tmAddDate,
            onPressed: () async {
              final last = c.picked.isEmpty ? null : c.picked.last;
              final slot = await _pickSlot(
                context,
                (last?.start ?? DateTime.now()).add(const Duration(days: 1)),
                last == null ? const TimeOfDay(hour: 20, minute: 0) : TimeOfDay.fromDateTime(last.start),
                last?.end.difference(last.start) ?? const Duration(hours: 2),
              );
              if (slot != null) c.addPicked(slot);
            },
          ),
        const SizedBox(height: KSpace.xs),
        Text(s.tmDatesOf(c.picked.length, kMaxSeriesDates),
            key: const ValueKey('picked-count'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------- pieces

class _SessionRow extends StatelessWidget {
  final int? number;
  final DateTime start;
  final DateTime? end;
  final bool extra;
  final bool off;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTapDate;
  final VoidCallback? onTapTime;

  const _SessionRow({
    super.key,
    required this.number,
    required this.start,
    required this.end,
    required this.actionLabel,
    required this.onAction,
    this.extra = false,
    this.off = false,
    this.onTapDate,
    this.onTapTime,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strike = off ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final timeText = end == null
        ? ''
        : '${_timeFmt.format(start)} – ${_timeFmt.format(end!)}';
    Widget tappable(Widget child, VoidCallback? onTap) => onTap == null
        ? child
        : InkWell(onTap: onTap, borderRadius: KRadius.small, child: child);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: off ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: KRadius.input),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(number?.toString() ?? '–',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: KSpace.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tappable(
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                        Text(_dayFmt.format(start), style: strike),
                        if (extra)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(99)),
                            child: Text(s.tmExtra,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSecondaryContainer)),
                          ),
                      ]),
                      onTapDate,
                    ),
                    if (timeText.isNotEmpty)
                      tappable(
                        Text(timeText,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)
                                .merge(strike)),
                        onTapTime,
                      ),
                  ],
                ),
              ),
              off
                  ? TextButton(onPressed: onAction, child: Text(actionLabel))
                  : IconButton(
                      tooltip: actionLabel,
                      onPressed: onAction,
                      icon: Icon(AppIcons.close, size: 18, color: onAction == null ? null : scheme.error),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _AddButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(AppIcons.create, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: KRadius.input),
        ),
      );
}

/// "Registration closes": when it starts / at a set time / never.
class RegistrationCloseField extends StatelessWidget {
  final EventTimingController controller;
  const RegistrationCloseField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = context.l10n;
        final c = controller;
        final hint = switch (c.close) {
          CloseRule.atStart => c.isSeries ? s.rcHintSeriesStart : s.rcHintStart,
          CloseRule.setTime => c.isSeries ? s.rcHintSeriesSet : s.rcHintSet,
          CloseRule.never => s.rcHintNever,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(context, s.rcLabel),
            SegmentedButton<CloseRule>(
              key: const ValueKey('close-rule'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: CloseRule.atStart, label: Text(s.rcAtStart)),
                ButtonSegment(value: CloseRule.setTime, label: Text(s.rcSetTime)),
                ButtonSegment(value: CloseRule.never, label: Text(s.rcNever)),
              ],
              selected: {c.close},
              onSelectionChanged: (v) => c.setClose(v.first),
            ),
            if (c.close == CloseRule.setTime) ...[
              const SizedBox(height: KSpace.s),
              if (c.isSeries)
                DropdownButtonFormField<Duration>(
                  key: const ValueKey('close-before'),
                  initialValue: c.closeBefore,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainer,
                    border: OutlineInputBorder(borderRadius: KRadius.input, borderSide: BorderSide.none),
                  ),
                  items: [
                    for (final d in kCloseBeforeChoices)
                      DropdownMenuItem(
                          value: d,
                          child: Text(s.rcBefore(d), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (d) {
                    if (d != null) c.setCloseBefore(d);
                  },
                )
              else
                PickerField(
                  fieldKey: const ValueKey('close-at'),
                  text: formatEventDate(c.closeAt ?? c.start),
                  icon: AppIcons.calendar,
                  error: c.closeAfterStart ? s.rcAfterStart : null,
                  onTap: () async {
                    final init = c.closeAt ?? c.start;
                    final d = await _pickDay(context, init);
                    if (d == null || !context.mounted) return;
                    final t = await _pickTime(context, TimeOfDay.fromDateTime(init));
                    if (t != null) c.setCloseAt(atTime(d, t.hour, t.minute));
                  },
                ),
            ],
            const SizedBox(height: KSpace.xs),
            _hint(context, hint),
          ],
        );
      },
    );
  }
}
