import 'package:flutter/material.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/moderation_logic.dart';

/// Bumped by any tab after an action so the overview re-fetches.
final adminSummaryRefresh = ValueNotifier<int>(0);

/// Small stat cards over the console: open cases, oldest waiting,
/// auto-hidden awaiting review, club requests, appeals. Cards that map
/// to a tab are tappable.
class AdminOverview extends StatelessWidget {
  final Map<String, dynamic>? summary;
  final void Function(int tabIndex)? onOpenTab;

  const AdminOverview({super.key, required this.summary, this.onOpenTab});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final u = m.ui;
    final s = summary;
    int n(String k) => (s?[k] as num?)?.toInt() ?? 0;
    final oldest = DateTime.tryParse('${s?['oldest_open_at']}');
    final age = oldest == null
        ? u.statNone
        : compactAge(DateTime.now().difference(oldest.toLocal()),
            day: m.ageDay, hour: m.ageHour, minute: m.ageMinute, lessThanMinute: m.ageNow);

    final cards = [
      _Stat(icon: Icons.inbox_outlined, label: u.statOpen, value: s == null ? null : '${n('open_cases')}',
          onTap: () => onOpenTab?.call(0), emphasis: n('open_cases') > 0),
      _Stat(icon: Icons.schedule, label: u.statOldest, value: s == null ? null : age),
      _Stat(icon: Icons.visibility_off_outlined, label: u.statHidden,
          value: s == null ? null : '${n('hidden_cases')}', onTap: () => onOpenTab?.call(0),
          emphasis: n('hidden_cases') > 0),
      _Stat(icon: Icons.verified_outlined, label: u.statClubs,
          value: s == null ? null : '${n('club_requests')}', onTap: () => onOpenTab?.call(1)),
      _Stat(icon: Icons.gavel_outlined, label: u.statAppeals,
          value: s == null ? null : '${n('pending_appeals')}', onTap: () => onOpenTab?.call(2)),
    ];

    return LayoutBuilder(builder: (context, c) {
      // Compact: one scrolling row so the queue keeps the screen.
      if (c.maxWidth < 600) {
        return SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(width: 150, child: cards[i]),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        ),
      );
    });
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value; // null = loading
  final VoidCallback? onTap;
  final bool emphasis;

  const _Stat({required this.icon, required this.label, required this.value, this.onTap, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = emphasis ? scheme.tertiaryContainer : scheme.surfaceContainerLow;
    final fg = emphasis ? scheme.onTertiaryContainer : scheme.onSurface;
    return Semantics(
      button: onTap != null,
      label: '$label: ${value ?? ''}',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: fg.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: fg)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: value == null
                      ? Container(
                          key: const ValueKey('loading'),
                          width: 36,
                          height: 20,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Text(value!,
                          key: ValueKey(value),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
