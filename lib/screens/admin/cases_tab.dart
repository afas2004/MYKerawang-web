import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../utils/formatters.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';
import 'restrict_dialog.dart';

/// The queue: priority first, then oldest. Header shows how long the
/// oldest open case has waited (no SLA — it depends on who's around).
class CasesTab extends StatefulWidget {
  const CasesTab({super.key});

  @override
  State<CasesTab> createState() => _CasesTabState();
}

class _CasesTabState extends State<CasesTab> with AutomaticKeepAliveClientMixin {
  String? _status = 'active';
  String? _type;
  String? _category;
  late Future<List<Map<String, dynamic>>> _cases;
  late Future<Map<String, dynamic>> _summary;
  final Set<String> _selected = {};
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _cases = ModerationService.cases(status: _status, type: _type, category: _category)
        .then((rows) => _status == 'active' ? (rows..sort(compareCases)) : rows);
    _summary = ModerationService.queueSummary();
    _selected.clear();
  }

  void _reload() => setState(_load);

  bool get _bulkMode => _category == 'spam' && _status == 'active';

  // ------------------------------------------------------------ actions
  Future<void> _run(String caseId, Future<void> Function() action) async {
    setState(() => _busy.add(caseId));
    try {
      await action();
    } catch (e) {
      if (mounted) showModError(context, e);
      if (parseModError(e)?.code == 'already_resolved') _reload();
    } finally {
      if (mounted) setState(() => _busy.remove(caseId));
    }
  }

  Future<void> _dismissOrRestore(Map<String, dynamic> c) async {
    final m = modStrings(context);
    final hidden = c['status'] == 'hidden';
    final type = m.typeLabel(c['target_type']).toLowerCase();
    final reason = await askReason(
      context,
      title: hidden ? m.restoreTitle.fill([type]) : m.dismissTitle,
      body: hidden ? m.restoreBody : m.dismissBody,
      confirmLabel: hidden ? m.actionRestore : m.actionDismiss,
    );
    if (reason == null || !mounted) return;
    final id = '${c['id']}';
    await _run(id, () async {
      await ModerationService.resolveCase(id, hidden ? 'restore' : 'dismiss', reason);
      if (!mounted) return;
      showModSnack(context, hidden ? m.doneRestored : m.doneDismissed, onUndo: () async {
        await ModerationService.undoCase(id);
        if (mounted) _reload();
      });
      _reload();
    });
  }

  Future<void> _uphold(Map<String, dynamic> c, String decision) async {
    final m = modStrings(context);
    final remove = decision == 'remove';
    final type = m.typeLabel(c['target_type']).toLowerCase();
    final reason = await askReason(
      context,
      title: remove ? m.removeTitle.fill([type]) : m.warnTitle,
      body: remove ? m.removeBody : m.warnBody,
      confirmLabel: remove ? m.actionRemove : m.actionWarn,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final id = '${c['id']}';
    await _run(id, () async {
      await ModerationService.resolveCase(id, decision, reason);
      if (!mounted) return;
      showModSnack(context, remove ? m.doneRemoved : m.doneWarned);
      _reload();
    });
  }

  Future<void> _restrict(Map<String, dynamic> c) async {
    final m = modStrings(context);
    final anon = c['target_anonymous'] == true;
    final owner = c['owner'] as Map<String, dynamic>?;
    final scope = ModScope.fromDb(switch (c['target_type']) {
      'post' => 'post',
      'comment' => 'comment',
      'listing' => 'market',
      'event' => 'events',
      _ => null,
    });
    final choice = await showRestrictDialog(
      context,
      who: anon ? m.anonymousAuthor : '${owner?['display_name'] ?? owner?['username'] ?? ''}',
      initialScopes: {?scope},
    );
    if (choice == null || !mounted) return;
    if (isSevereRestriction(choice.scopes, choice.duration)) {
      final ok = await confirmModAction(context,
          title: m.restrictTitle,
          body: m.severeWarning,
          confirmLabel: m.confirm,
          destructive: true);
      if (!ok || !mounted) return;
    }
    final id = '${c['id']}';
    await _run(id, () async {
      await ModerationService.restrict(
          caseId: id, scopes: choice.scopes, duration: choice.duration, reason: choice.reason);
      if (!mounted) return;
      showModSnack(context, m.doneRestricted);
      _reload();
    });
  }

  Future<void> _unmask(Map<String, dynamic> c) async {
    final m = modStrings(context);
    final reason = await askReason(
      context,
      title: m.unmaskTitle,
      body: m.unmaskBody,
      confirmLabel: m.actionUnmask,
      helper: m.unmaskReasonHelp,
      minLength: 10,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final id = '${c['id']}';
    await _run(id, () async {
      final who = await ModerationService.unmask(
          '${c['target_type']}', '${c['target_id']}', reason);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(m.unmaskTitle),
          content: SelectableText(who == null || who['author_id'] == null
              ? m.unmaskNone
              : m.unmaskResult.fill([who['display_name'] ?? '?', who['username'] ?? '?'])),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(m.ok)),
          ],
        ),
      );
    });
  }

  Future<void> _bulk(String decision) async {
    final m = modStrings(context);
    final remove = decision == 'remove';
    final ids = _selected.toList();
    final reason = await askReason(
      context,
      title: remove ? m.bulkRemove : m.bulkDismiss,
      body: '${m.bulkSelected.fill([ids.length])}. ${remove ? m.removeBody : m.dismissBody}',
      confirmLabel: remove ? m.actionRemove : m.actionDismiss,
      destructive: remove,
      initial: 'Spam',
    );
    if (reason == null || !mounted) return;
    try {
      final n = await ModerationService.bulkResolve(ids, decision, reason);
      if (!mounted) return;
      showModSnack(context, m.bulkDone.fill([n]));
    } catch (e) {
      if (mounted) showModError(context, e);
    }
    _reload();
  }

  void _open(Map<String, dynamic> c) {
    final id = '${c['target_id']}';
    final preview = c['preview'] as Map<String, dynamic>?;
    switch (c['target_type']) {
      case 'user':
        context.push('/u/$id');
      case 'event':
        context.push('/event/$id');
      case 'listing':
        context.push('/item/$id');
      case 'comment':
        final post = preview?['post_id'];
        final event = preview?['event_id'];
        if (post != null) context.push('/post/$post');
        if (event != null) context.push('/event/$event');
      case 'post':
        context.push('/post/$id');
    }
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _cases,
      onRetry: _reload,
      header: _header(m),
      empty: ModEmptyState(
        icon: Icons.check_circle_outline,
        title: _status == 'active' && _type == null && _category == null
            ? m.noOpenCases
            : m.noCasesFilter,
        body: _status == 'active' && _type == null && _category == null
            ? m.noOpenCasesBody
            : null,
      ),
      itemBuilder: (context, c) => _CaseCard(
        data: c,
        busy: _busy.contains('${c['id']}'),
        selectable: _bulkMode && isBulkEligible(c),
        selected: _selected.contains('${c['id']}'),
        onSelect: (v) => setState(() =>
            v ? _selected.add('${c['id']}') : _selected.remove('${c['id']}')),
        onDismissOrRestore: () => _dismissOrRestore(c),
        onRemove: () => _uphold(c, 'remove'),
        onWarn: () => _uphold(c, 'warn'),
        onRestrict: () => _restrict(c),
        onUnmask: () => _unmask(c),
        onOpen: () => _open(c),
      ),
    );
  }

  Widget _header(ModerationStrings m) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _summary,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) return const SizedBox(height: 4);
            final open = (s['open_cases'] as num?)?.toInt() ?? 0;
            final oldest = DateTime.tryParse('${s['oldest_open_at']}');
            final text = open == 0 || oldest == null
                ? m.noOpenSummary
                : m.openSummary.fill([
                    open,
                    compactAge(DateTime.now().difference(oldest.toLocal()),
                        day: m.ageDay, hour: m.ageHour, minute: m.ageMinute, lessThanMinute: m.ageNow),
                  ]);
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: open == 0 ? scheme.secondaryContainer : scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(open == 0 ? Icons.check_circle_outline : Icons.schedule,
                      color: open == 0 ? scheme.onSecondaryContainer : scheme.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: open == 0
                                ? scheme.onSecondaryContainer
                                : scheme.onTertiaryContainer)),
                  ),
                  IconButton(
                    tooltip: context.l10n.refresh,
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (value, label) in [
                ('active', m.filterActive),
                ('hidden', m.filterHidden),
                ('resolved', m.filterResolved),
                (null, m.filterAll),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _status == value,
                  onSelected: (_) {
                    _status = value;
                    _reload();
                  },
                ),
              DropdownButton<String?>(
                value: _type,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: null, child: Text(m.allTypes)),
                  for (final t in kTargetTypes)
                    DropdownMenuItem(value: t, child: Text(m.typeLabel(t))),
                ],
                onChanged: (v) {
                  _type = v;
                  _reload();
                },
              ),
              DropdownButton<String?>(
                value: _category,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: null, child: Text(m.allCategories)),
                  for (final c in kReportCategories)
                    DropdownMenuItem(value: c, child: Text(m.categoryLabel(c))),
                ],
                onChanged: (v) {
                  _category = v;
                  _reload();
                },
              ),
            ],
          ),
        ),
        if (_bulkMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selected.isEmpty ? m.bulkHint : m.bulkSelected.fill([_selected.length]),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _selected.isEmpty ? null : () => _bulk('dismiss'),
                  child: Text(m.bulkDismiss),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: _selected.isEmpty ? null : () => _bulk('remove'),
                  child: Text(m.bulkRemove),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _CaseCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool busy;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onDismissOrRestore;
  final VoidCallback onRemove;
  final VoidCallback onWarn;
  final VoidCallback onRestrict;
  final VoidCallback onUnmask;
  final VoidCallback onOpen;

  const _CaseCard({
    required this.data,
    required this.busy,
    required this.selectable,
    required this.selected,
    required this.onSelect,
    required this.onDismissOrRestore,
    required this.onRemove,
    required this.onWarn,
    required this.onRestrict,
    required this.onUnmask,
    required this.onOpen,
  });

  static IconData _typeIcon(String? t) => switch (t) {
        'post' => Icons.article_outlined,
        'comment' => Icons.chat_bubble_outline,
        'event' => Icons.event_outlined,
        'listing' => Icons.storefront_outlined,
        _ => Icons.person_outline,
      };

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = data;
    final type = c['target_type'] as String?;
    final status = c['status'] as String?;
    final active = status == 'open' || status == 'hidden';
    final priority = (c['priority'] as num?)?.toInt() ?? 0;
    final anon = c['target_anonymous'] == true;
    final preview = c['preview'] as Map<String, dynamic>?;
    final first = DateTime.tryParse('${c['first_reported_at']}');
    final strikes = (c['owner_strikes'] as num?)?.toInt() ?? 0;
    final categories = ((c['categories'] as List?) ?? const []).cast<String>();
    final title = preview?['title'] as String?;
    final body = preview?['body'] as String?;
    final image = preview?['image_url'] as String?;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: priority >= 2 ? scheme.error : scheme.outlineVariant,
            width: priority >= 2 ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selectable)
                      Checkbox(value: selected, onChanged: (v) => onSelect(v == true)),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (priority >= 2)
                            ModChip(
                                label: m.priorityUrgent,
                                icon: Icons.priority_high,
                                background: scheme.error,
                                foreground: scheme.onError)
                          else if (priority == 1)
                            ModChip(
                                label: m.priorityHigh,
                                background: scheme.errorContainer,
                                foreground: scheme.onErrorContainer),
                          ModChip(
                              label: m.typeLabel(type),
                              icon: _typeIcon(type),
                              background: scheme.surfaceContainerHighest,
                              foreground: scheme.onSurface),
                          ModChip(
                              label: status == 'actioned' || status == 'dismissed' || status == 'closed'
                                  ? m.decisionLabel(c['decision'] as String?)
                                  : m.statusLabel(status),
                              background: status == 'hidden'
                                  ? scheme.tertiaryContainer
                                  : scheme.secondaryContainer,
                              foreground: status == 'hidden'
                                  ? scheme.onTertiaryContainer
                                  : scheme.onSecondaryContainer),
                          if (c['appeal_status'] != null)
                            ModChip(
                                label: m.appealStatusLabel(c['appeal_status'] as String?),
                                icon: Icons.gavel,
                                background: scheme.primaryContainer,
                                foreground: scheme.onPrimaryContainer),
                        ],
                      ),
                    ),
                    if (preview != null)
                      IconButton(
                        tooltip: context.l10n.viewEvent.split(' ').first,
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (preview == null)
                  Text(m.contentGone,
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant))
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null && title.trim().isNotEmpty)
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            if (body != null && body.trim().isNotEmpty)
                              Text(body, maxLines: 5, overflow: TextOverflow.ellipsis),
                            if (preview['price'] != null)
                              Text(formatPrice(preview['price'] as num?),
                                  style: TextStyle(color: scheme.primary)),
                          ],
                        ),
                      ),
                      if (image != null && image.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: image,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const SizedBox(width: 72, height: 72),
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final cat in categories)
                      ModChip(
                          label: m.categoryLabel(cat),
                          background: cat == 'scam' || cat == 'minor_safety'
                              ? scheme.errorContainer
                              : scheme.surfaceContainerHigh,
                          foreground: cat == 'scam' || cat == 'minor_safety'
                              ? scheme.onErrorContainer
                              : scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    m.reportsCount.fill([c['report_count'] ?? 0, c['trusted_reporters'] ?? 0]),
                    if (first != null) m.firstReported.fill([formatRelative(context, first)]),
                    if (c['auto_hidden'] == true) m.autoHidden,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                AdminUserLine(
                  profile: c['owner'] as Map<String, dynamic>?,
                  anonymous: anon,
                  trailing: strikes > 0 ? m.strikesCount.fill([strikes]) : null,
                ),
                if (!active && (c['decision_reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('“${c['decision_reason']}”',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
                if (active) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy ? null : onDismissOrRestore,
                        icon: Icon(status == 'hidden' ? Icons.restore : Icons.check, size: 18),
                        label: Text(status == 'hidden' ? m.actionRestore : m.actionDismiss),
                      ),
                      if (isHideableType(type ?? 'user'))
                        OutlinedButton.icon(
                          onPressed: busy ? null : onRemove,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(m.actionRemove),
                          style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                        ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onWarn,
                        icon: const Icon(Icons.warning_amber, size: 18),
                        label: Text(m.actionWarn),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : onRestrict,
                        icon: const Icon(Icons.block, size: 18),
                        label: Text(m.actionRestrict),
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                      ),
                      if (anon && (type == 'post' || type == 'comment'))
                        TextButton.icon(
                          onPressed: busy ? null : onUnmask,
                          icon: const Icon(Icons.visibility_outlined, size: 18),
                          label: Text(m.actionUnmask),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
