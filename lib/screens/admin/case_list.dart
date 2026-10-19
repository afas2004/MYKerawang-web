import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';

IconData caseTypeIcon(String? t) => switch (t) {
      'post' => ModIcons.post,
      'comment' => ModIcons.comment,
      'event' => ModIcons.event,
      'listing' => ModIcons.listing,
      _ => ModIcons.person,
    };

/// One-line summary of a case's content for list rows.
String caseSnippet(ModerationStrings m, Map<String, dynamic> c) {
  final p = c['preview'] as Map<String, dynamic>?;
  if (p == null) return m.contentGone;
  final t = '${p['title'] ?? ''}'.trim();
  if (t.isNotEmpty) return t;
  final b = '${p['body'] ?? ''}'.trim().replaceAll('\n', ' ');
  return b.isEmpty ? m.typeLabel(c['target_type'] as String?) : b;
}

/// Queue rows: type icon (tinted by priority), snippet, report count,
/// age, status. Selection is highlighted; rows are ≥ 64 px tall.
class CaseListPane extends StatelessWidget {
  final List<Map<String, dynamic>> cases;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final bool bulkMode;
  final Set<String> bulkSelected;
  final void Function(String id, bool selected)? onBulkToggle;
  final ScrollController? controller;

  const CaseListPane({
    super.key,
    required this.cases,
    required this.selectedId,
    required this.onSelect,
    this.bulkMode = false,
    this.bulkSelected = const {},
    this.onBulkToggle,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: cases.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final c = cases[i];
        final id = '${c['id']}';
        return CaseListTile(
          data: c,
          selected: id == selectedId,
          onTap: () => onSelect(c),
          bulk: bulkMode && isBulkEligible(c),
          bulkSelected: bulkSelected.contains(id),
          onBulkToggle: (v) => onBulkToggle?.call(id, v),
        );
      },
    );
  }
}

class CaseListTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onTap;
  final bool bulk;
  final bool bulkSelected;
  final ValueChanged<bool>? onBulkToggle;

  const CaseListTile({
    super.key,
    required this.data,
    required this.selected,
    required this.onTap,
    this.bulk = false,
    this.bulkSelected = false,
    this.onBulkToggle,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = data;
    final priority = (c['priority'] as num?)?.toInt() ?? 0;
    final status = c['status'] as String?;
    final first = DateTime.tryParse('${c['first_reported_at']}');
    final count = (c['report_count'] as num?)?.toInt() ?? 0;

    final (Color iconBg, Color iconFg) = switch (priority) {
      >= 2 => (scheme.error, scheme.onError),
      1 => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    final age = first == null
        ? ''
        : compactAge(DateTime.now().difference(first.toLocal()),
            day: m.ageDay, hour: m.ageHour, minute: m.ageMinute, lessThanMinute: m.ageNow);

    final meta = <String>[
      m.typeLabel(c['target_type'] as String?),
      count == 1 ? m.ui.reportsShortOne : m.ui.reportsShort.fill([count]),
      if (age.isNotEmpty) age,
    ];

    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (bulk)
                  Checkbox(value: bulkSelected, onChanged: (v) => onBulkToggle?.call(v == true)),
                Tooltip(
                  message: priority >= 2
                      ? m.priorityUrgent
                      : priority == 1
                          ? m.priorityHigh
                          : m.typeLabel(c['target_type'] as String?),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: iconBg,
                    child: Icon(caseTypeIcon(c['target_type'] as String?), size: 20, color: iconFg),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caseSnippet(m, c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (status == 'hidden')
                  Tooltip(
                    message: m.statusHidden,
                    child: Icon(ModIcons.hidden, size: 18, color: scheme.tertiary),
                  )
                else if (status != 'open')
                  Text(m.decisionLabel(c['decision'] as String?),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "{0} reports" without a plural table: the count string is built from
/// [ModerationStrings.reportsCount] when the trusted count is known.
String reportCountLabel(ModerationStrings m, Map<String, dynamic> c) =>
    m.reportsCount.fill([c['report_count'] ?? 0, c['trusted_reporters'] ?? 0]);
