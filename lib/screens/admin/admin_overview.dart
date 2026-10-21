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
        : compactAge(
            DateTime.now().difference(oldest.toLocal()),
            day: m.ageDay,
            hour: m.ageHour,
            minute: m.ageMinute,
            lessThanMinute: m.ageNow,
          );

    final cards = [
      _Stat(
        icon: ModIcons.inbox,
        label: u.statOpen,
        value: s == null ? null : '${n('open_cases')}',
        onTap: () => onOpenTab?.call(0),
        emphasis: n('open_cases') > 0,
      ),
      _Stat(
        icon: ModIcons.clock,
        label: u.statOldest,
        value: s == null ? null : age,
      ),
      _Stat(
        icon: ModIcons.hidden,
        label: u.statHidden,
        value: s == null ? null : '${n('hidden_cases')}',
        onTap: () => onOpenTab?.call(0),
        emphasis: n('hidden_cases') > 0,
      ),
      _Stat(
        icon: ModIcons.verified,
        label: u.statClubs,
        value: s == null ? null : '${n('club_requests')}',
        onTap: () => onOpenTab?.call(1),
      ),
      _Stat(
        icon: ModIcons.appeal,
        label: u.statAppeals,
        value: s == null ? null : '${n('pending_appeals')}',
        onTap: () => onOpenTab?.call(2),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        // Grid: 2 columns on phones, 3 on tablets, all 5 in one row from
        // the desktop breakpoint. Each row shares its width equally.
        final cols = c.maxWidth >= Responsive.desktopBreakpoint
            ? 5
            : c.maxWidth >= 600
            ? 3
            : 2;
        final rows = <List<Widget>>[
          for (var i = 0; i < cards.length; i += cols)
            cards.sublist(i, (i + cols).clamp(0, cards.length)),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            KSpace.l,
            KSpace.m,
            KSpace.l,
            KSpace.s,
          ),
          child: Column(
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: KSpace.s),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows[r].length; i++) ...[
                        if (i > 0) const SizedBox(width: KSpace.s),
                        Expanded(child: rows[r][i]),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value; // null = loading
  final VoidCallback? onTap;
  final bool emphasis;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tileBg = emphasis
        ? scheme.tertiaryContainer
        : scheme.primaryContainer;
    final tileFg = emphasis
        ? scheme.onTertiaryContainer
        : scheme.onPrimaryContainer;
    return KCard(
      onTap: onTap,
      semanticLabel: '$label: ${value ?? ''}',
      padding: const EdgeInsets.all(KSpace.m),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tileBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tileFg),
          ),
          const SizedBox(width: KSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: KMotion.of(context).medium,
                  child: value == null
                      ? const KSkeleton(
                          key: ValueKey('loading'),
                          width: 36,
                          height: 22,
                        )
                      : Text(
                          value!,
                          key: ValueKey(value),
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
