import 'package:flutter/material.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';

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
      _Stat(icon: ModIcons.inbox, label: u.statOpen, value: s == null ? null : '${n('open_cases')}',
          onTap: () => onOpenTab?.call(0), emphasis: n('open_cases') > 0),
      _Stat(icon: ModIcons.clock, label: u.statOldest, value: s == null ? null : age),
      _Stat(icon: ModIcons.hidden, label: u.statHidden,
          value: s == null ? null : '${n('hidden_cases')}', onTap: () => onOpenTab?.call(0),
          emphasis: n('hidden_cases') > 0),
      _Stat(icon: ModIcons.verified, label: u.statClubs,
          value: s == null ? null : '${n('club_requests')}', onTap: () => onOpenTab?.call(1)),
      _Stat(icon: ModIcons.appeal, label: u.statAppeals,
          value: s == null ? null : '${n('pending_appeals')}', onTap: () => onOpenTab?.call(2)),
    ];

    return LayoutBuilder(builder: (context, c) {
      // Compact: one scrolling row so the queue keeps the screen.
      if (c.maxWidth < 600) {
        return SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.s),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: KSpace.s),
            itemBuilder: (_, i) => SizedBox(width: 150, child: cards[i]),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.m, KSpace.m, KSpace.xs),
        child: Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: KSpace.s),
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
    final bg = emphasis ? scheme.tertiaryContainer : null;
    final fg = emphasis ? scheme.onTertiaryContainer : scheme.onSurface;
    return KCard(
      onTap: onTap,
      color: bg,
      semanticLabel: '$label: ${value ?? ''}',
      padding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.s),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: KSpace.xs + 2),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: fg)),
                ),
              ],
            ),
            const SizedBox(height: KSpace.xs),
            AnimatedSwitcher(
              duration: KMotion.of(context).medium,
              child: value == null
                  ? const KSkeleton(key: ValueKey('loading'), width: 36, height: 20)
                  : Text(value!,
                      key: ValueKey(value),
                      style: theme.textTheme.titleLarge?.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
