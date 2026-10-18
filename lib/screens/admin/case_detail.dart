import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/formatters.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';
import 'case_list.dart';
import '../../widgets/brand/brand.dart';

/// What the detail pane can do with a case. Each returns true when the
/// action completed (the compact detail page then closes itself).
class CaseActions {
  final Future<bool> Function(Map<String, dynamic> c) dismissOrRestore;
  final Future<bool> Function(Map<String, dynamic> c) remove;
  final Future<bool> Function(Map<String, dynamic> c) warn;
  final Future<bool> Function(Map<String, dynamic> c) restrict;
  final Future<bool> Function(Map<String, dynamic> c) unmask;
  final void Function(Map<String, dynamic> c) open;

  const CaseActions({
    required this.dismissOrRestore,
    required this.remove,
    required this.warn,
    required this.restrict,
    required this.unmask,
    required this.open,
  });
}

/// Right-hand side of the console (or a pushed page on phones): content
/// preview, every report, the author's history, and a sticky action bar.
class CaseDetailPane extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<Map<String, dynamic>>? detail;
  final CaseActions actions;
  final bool busy;
  final VoidCallback? onRetryDetail;

  const CaseDetailPane({
    super.key,
    required this.data,
    required this.detail,
    required this.actions,
    this.busy = false,
    this.onRetryDetail,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final u = m.ui;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = data;
    final status = c['status'] as String?;
    final active = status == 'open' || status == 'hidden';
    final priority = (c['priority'] as num?)?.toInt() ?? 0;
    final anon = c['target_anonymous'] == true;
    final preview = c['preview'] as Map<String, dynamic>?;
    final strikes = (c['owner_strikes'] as num?)?.toInt() ?? 0;
    final categories = ((c['categories'] as List?) ?? const []).cast<String>();
    final first = DateTime.tryParse('${c['first_reported_at']}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only built while busy: an indeterminate indicator keeps
        // animating even when faded out.
        SizedBox(height: 2, child: busy ? const LinearProgressIndicator(minHeight: 2) : null),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.xl),
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (priority >= 2)
                    ModChip(label: m.priorityUrgent, icon: Icons.priority_high,
                        background: scheme.error, foreground: scheme.onError)
                  else if (priority == 1)
                    ModChip(label: m.priorityHigh,
                        background: scheme.errorContainer, foreground: scheme.onErrorContainer),
                  ModChip(label: m.typeLabel(c['target_type'] as String?),
                      icon: caseTypeIcon(c['target_type'] as String?),
                      background: scheme.surfaceContainerHighest, foreground: scheme.onSurface),
                  ModChip(
                      label: active ? m.statusLabel(status) : m.decisionLabel(c['decision'] as String?),
                      background: status == 'hidden' ? scheme.tertiaryContainer : scheme.secondaryContainer,
                      foreground: status == 'hidden' ? scheme.onTertiaryContainer : scheme.onSecondaryContainer),
                  if (c['appeal_status'] != null)
                    ModChip(label: m.appealStatusLabel(c['appeal_status'] as String?), icon: Icons.gavel,
                        background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  reportCountLabel(m, c),
                  if (first != null) m.firstReported.fill([formatRelative(context, first)]),
                  if (c['auto_hidden'] == true) m.autoHidden,
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _Heading(u.contentHeading,
                  trailing: preview == null
                      ? null
                      : TextButton.icon(
                          onPressed: () => actions.open(c),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(u.openInApp),
                        )),
              _ContentPreview(preview: preview),
              const SizedBox(height: 12),
              AdminUserLine(
                profile: c['owner'] as Map<String, dynamic>?,
                anonymous: anon,
                trailing: strikes > 0 ? m.strikesCount.fill([strikes]) : null,
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cat in categories)
                      ModChip(
                          label: m.categoryLabel(cat),
                          background: cat == 'scam' || cat == 'minor_safety'
                              ? scheme.errorContainer : scheme.surfaceContainerHigh,
                          foreground: cat == 'scam' || cat == 'minor_safety'
                              ? scheme.onErrorContainer : scheme.onSurfaceVariant),
                  ],
                ),
              ],
              if (!active && (c['decision_reason'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text('“${c['decision_reason']}”',
                    style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),
              _DetailSections(
                future: detail,
                anonymous: anon,
                reportCount: (c['report_count'] as num?)?.toInt() ?? 0,
                onRetry: onRetryDetail,
              ),
            ],
          ),
        ),
        if (active) _ActionBar(data: c, actions: actions, busy: busy),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _Heading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => SectionHeader(
        title: text,
        trailing: trailing,
        padding: const EdgeInsets.only(bottom: KSpace.s),
      );
}

class _ContentPreview extends StatelessWidget {
  final Map<String, dynamic>? preview;
  const _ContentPreview({required this.preview});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = preview;
    if (p == null) {
      return Text(m.contentGone,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant));
    }
    final title = '${p['title'] ?? ''}'.trim();
    final body = '${p['body'] ?? ''}'.trim();
    final image = p['image_url'] as String?;
    return KCard(
      padding: const EdgeInsets.all(KSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (body.isNotEmpty) ...[
            if (title.isNotEmpty) const SizedBox(height: 4),
            SelectableText(body, style: theme.textTheme.bodyMedium),
          ],
          if (p['price'] != null) ...[
            const SizedBox(height: 4),
            Text(formatPrice(p['price'] as num?),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary)),
          ],
          if (image != null && image.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _untilLabel(ModerationStrings m, Object? until) {
  final d = until == null ? null : DateTime.tryParse('$until');
  return d == null ? m.permanent : m.untilDate.fill([formatUntil(d)]);
}

class _DetailSections extends StatelessWidget {
  final Future<Map<String, dynamic>>? future;
  final bool anonymous;
  final int reportCount;
  final VoidCallback? onRetry;

  const _DetailSections({required this.future, required this.anonymous, required this.reportCount, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final u = m.ui;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (future == null) return const SizedBox.shrink();
        if (snap.connectionState != ConnectionState.done) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KSkeleton(width: 140, height: 16),
              const SizedBox(height: KSpace.m),
              KSkeleton.lines(4),
            ],
          );
        }
        if (snap.hasError) {
          return Row(
            children: [
              Icon(Icons.error_outline, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(u.detailError)),
              if (onRetry != null) TextButton(onPressed: onRetry, child: Text(m.retry)),
            ],
          );
        }
        final d = snap.data!;
        final reports = ((d['reports'] as List?) ?? const []).cast<Map>();
        final history = ((d['history'] as List?) ?? const []).cast<Map>();
        final restrictions = ((d['restrictions'] as List?) ?? const []).cast<Map>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(u.reportsHeading.fill([reports.length])),
            for (final r in reports)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(r['counted'] == false ? Icons.flag_outlined : Icons.flag,
                        size: 18,
                        color: r['counted'] == false ? scheme.outline : scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              m.categoryLabel(r['category'] as String?),
                              if (DateTime.tryParse('${r['created_at']}') case final t?)
                                formatRelative(context, t),
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if ((r['note'] as String?)?.isNotEmpty == true)
                            Text('“${r['note']}”', style: theme.textTheme.bodyMedium),
                          if (r['counted'] == false)
                            Text(u.notCounted,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (restrictions.isNotEmpty) ...[
              _Heading(u.activeRestrictions),
              for (final r in restrictions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    [
                      m.scopeLabel(r['scope'] as String?),
                      _untilLabel(m, r['until']),
                      if (r['automatic'] == true) m.automatic,
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            _Heading(u.historyHeading),
            if (anonymous)
              Text(u.historyAnon,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
            else if (history.isEmpty)
              Text(u.noHistory,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
            else
              for (final h in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(caseTypeIcon(h['target_type'] as String?), size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            h['decision'] == null
                                ? m.statusLabel(h['status'] as String?)
                                : m.decisionLabel(h['decision'] as String?),
                            if (DateTime.tryParse('${h['first_reported_at']}') case final t?) formatDate(t),
                            if ((h['decision_reason'] as String?)?.isNotEmpty == true) '“${h['decision_reason']}”',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (h['strike'] == true)
                        Icon(Icons.warning_amber, size: 16, color: scheme.error),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// Sticky bar of case actions. On narrow widths the secondary actions
/// fold into an overflow menu so every target stays ≥ 48 px.
class _ActionBar extends StatelessWidget {
  final Map<String, dynamic> data;
  final CaseActions actions;
  final bool busy;
  const _ActionBar({required this.data, required this.actions, required this.busy});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    final c = data;
    final hidden = c['status'] == 'hidden';
    final type = c['target_type'] as String? ?? 'user';
    final anon = c['target_anonymous'] == true;
    final canUnmask = anon && (type == 'post' || type == 'comment');

    final primary = FilledButton.tonalIcon(
      onPressed: busy ? null : () => actions.dismissOrRestore(c),
      icon: Icon(hidden ? Icons.restore : Icons.check, size: 18),
      label: Text(hidden ? m.actionRestore : m.actionDismiss),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
    );
    final remove = isHideableType(type)
        ? OutlinedButton.icon(
            onPressed: busy ? null : () => actions.remove(c),
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: Text(m.actionRemove),
            style: OutlinedButton.styleFrom(foregroundColor: scheme.error, minimumSize: const Size(0, 48)),
          )
        : null;

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 560;
            final secondary = <(String, IconData, Future<bool> Function(Map<String, dynamic>))>[
              (m.actionWarn, Icons.warning_amber, actions.warn),
              (m.actionRestrict, Icons.block, actions.restrict),
              if (canUnmask) (m.actionUnmask, Icons.visibility_outlined, actions.unmask),
            ];
            if (wide) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  for (final a in secondary)
                    TextButton.icon(
                      onPressed: busy ? null : () => a.$3(c),
                      icon: Icon(a.$2, size: 18),
                      label: Text(a.$1),
                      style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                  ?remove,
                  primary,
                ],
              );
            }
            return Row(
              children: [
                PopupMenuButton<int>(
                  enabled: !busy,
                  tooltip: m.moderation,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (i) => secondary[i].$3(c),
                  itemBuilder: (_) => [
                    for (var i = 0; i < secondary.length; i++)
                      PopupMenuItem(
                        value: i,
                        child: ListTile(
                          leading: Icon(secondary[i].$2),
                          title: Text(secondary[i].$1),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (remove != null) ...[remove, const SizedBox(width: 8)],
                Flexible(child: primary),
              ],
            );
          }),
        ),
      ),
    );
  }
}
