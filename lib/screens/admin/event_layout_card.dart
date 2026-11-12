import 'package:flutter/material.dart';

import '../../l10n/event_timing_strings.dart';
import '../../language_cubit.dart';
import '../../services/feature_flags.dart';
import '../../widgets/brand/brand.dart';
import '../create_event_screen.dart';

/// Admin → Settings: the owner picks how the Create event page is laid out.
/// Each choice has a sketch and a Preview that opens the real form (nothing
/// is published from it); switching asks first.
class EventLayoutCard extends StatelessWidget {
  final EventFormLayout current;
  final bool saving;

  /// Called after the owner confirmed; does the saving.
  final ValueChanged<EventFormLayout> onChoose;

  const EventLayoutCard({
    super.key,
    required this.current,
    required this.saving,
    required this.onChoose,
  });

  static String nameOf(BuildContext context, EventFormLayout l) {
    final s = context.l10nRead;
    return l == EventFormLayout.folded ? s.layoutFolded : s.layoutSteps;
  }

  Future<void> _confirmAndChoose(BuildContext context, EventFormLayout l) async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.layoutConfirmTitle(nameOf(ctx, l))),
        content: Text(s.layoutConfirmBody),
        actions: [
          TextButton(
              key: const ValueKey('layout-cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              key: const ValueKey('layout-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.layoutSwitch)),
        ],
      ),
    );
    if (ok == true) onChoose(l);
  }

  static void openPreview(BuildContext context, EventFormLayout l) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CreateEventScreen(layout: l, preview: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('event-layout-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(AppIcons.events, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(s.layoutTitle, style: theme.textTheme.titleSmall)),
            ]),
            const SizedBox(height: 6),
            Text(s.layoutBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final options = [
                for (final l in EventFormLayout.values)
                  _Option(
                    layout: l,
                    selected: l == current,
                    saving: saving,
                    onUse: () => _confirmAndChoose(context, l),
                    onPreview: () => openPreview(context, l),
                  ),
              ];
              if (c.maxWidth < 520) {
                return Column(children: [
                  options[0],
                  const SizedBox(height: 10),
                  options[1],
                ]);
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: options[0]),
                    const SizedBox(width: 10),
                    Expanded(child: options[1]),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final EventFormLayout layout;
  final bool selected;
  final bool saving;
  final VoidCallback onUse;
  final VoidCallback onPreview;

  const _Option({
    required this.layout,
    required this.selected,
    required this.saving,
    required this.onUse,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folded = layout == EventFormLayout.folded;
    return Container(
      key: ValueKey('layout-option-${layout.db}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: KRadius.input,
        border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sketch(folded: folded),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(folded ? s.layoutFolded : s.layoutSteps,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (selected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: scheme.primaryContainer, borderRadius: BorderRadius.circular(99)),
                child: Text(s.layoutInUse,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(folded ? s.layoutFoldedBody : s.layoutStepsBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: ValueKey('layout-preview-${layout.db}'),
              onPressed: onPreview,
              icon: const Icon(AppIcons.externalLink, size: 16),
              label: Text(s.previewTitle),
            ),
            if (!selected)
              FilledButton(
                key: ValueKey('layout-use-${layout.db}'),
                onPressed: saving ? null : onUse,
                child: Text(s.layoutUse),
              ),
          ]),
        ],
      ),
    );
  }
}

/// A tiny drawing of the layout, from theme colours only.
class _Sketch extends StatelessWidget {
  final bool folded;
  const _Sketch({required this.folded});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget bar(double w, {Color? color, double h = 8}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
              color: color ?? scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(3)),
        );
    Widget fold() => Container(
          height: 16,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: bar(60, h: 5))),
            Icon(Icons.chevron_right, size: 12, color: scheme.onSurfaceVariant),
          ]),
        );
    final children = folded
        ? [
            bar(double.infinity, h: 22),
            bar(110),
            bar(80),
            bar(double.infinity, h: 12, color: scheme.primaryContainer),
            fold(),
            fold(),
            fold(),
          ]
        : [
            Row(children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(child: bar(double.infinity, h: 4, color: i == 0 ? scheme.primary : null)),
              ],
            ]),
            bar(double.infinity, h: 22),
            bar(110),
            bar(80),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerRight,
                child: bar(56, h: 14, color: scheme.primary)),
          ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: KRadius.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            children[i],
          ],
        ],
      ),
    );
  }
}
