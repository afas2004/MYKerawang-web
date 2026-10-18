import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/error_state.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_overview.dart';
import 'case_detail.dart';
import 'case_workspace.dart';
import 'restrict_dialog.dart';

/// Data + actions for the queue; layout lives in [CaseWorkspace].
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
  List<Map<String, dynamic>> _loaded = const [];
  String? _selectedId;
  final Map<String, Future<Map<String, dynamic>>> _details = {};
  final Set<String> _bulk = {};
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _details.clear();
    _bulk.clear();
    _cases = ModerationService.cases(status: _status, type: _type, category: _category).then((rows) {
      final sorted = _status == 'active' ? (rows..sort(compareCases)) : rows;
      _loaded = sorted;
      if (!sorted.any((c) => '${c['id']}' == _selectedId)) {
        _selectedId = sorted.isEmpty ? null : '${sorted.first['id']}';
      }
      return sorted;
    });
  }

  void _reload() {
    adminSummaryRefresh.value++;
    setState(_load);
  }

  Future<Map<String, dynamic>> _detailFor(String id) =>
      _details.putIfAbsent(id, () => ModerationService.caseDetail(id));

  bool get _bulkMode => _category == 'spam' && _status == 'active';

  Map<String, dynamic>? get _selected =>
      _loaded.where((c) => '${c['id']}' == _selectedId).firstOrNull;

  // ------------------------------------------------------------ actions
  Future<bool> _run(String caseId, Future<void> Function() action) async {
    setState(() => _busy.add(caseId));
    try {
      await action();
      return true;
    } catch (e) {
      if (mounted) showModError(context, e);
      if (parseModError(e)?.code == 'already_resolved') _reload();
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(caseId));
    }
  }

  Future<bool> _dismissOrRestore(Map<String, dynamic> c) async {
    final m = modStrings(context);
    final hidden = c['status'] == 'hidden';
    final type = m.typeLabel(c['target_type'] as String?).toLowerCase();
    final reason = await askReason(
      context,
      title: hidden ? m.restoreTitle.fill([type]) : m.dismissTitle,
      body: hidden ? m.restoreBody : m.dismissBody,
      confirmLabel: hidden ? m.actionRestore : m.actionDismiss,
    );
    if (reason == null || !mounted) return false;
    final id = '${c['id']}';
    return _run(id, () async {
      await ModerationService.resolveCase(id, hidden ? 'restore' : 'dismiss', reason);
      if (!mounted) return;
      showModSnack(context, hidden ? m.doneRestored : m.doneDismissed, onUndo: () async {
        await ModerationService.undoCase(id);
        if (mounted) _reload();
      });
      _reload();
    });
  }

  Future<bool> _uphold(Map<String, dynamic> c, String decision) async {
    final m = modStrings(context);
    final remove = decision == 'remove';
    final type = m.typeLabel(c['target_type'] as String?).toLowerCase();
    final reason = await askReason(
      context,
      title: remove ? m.removeTitle.fill([type]) : m.warnTitle,
      body: remove ? m.removeBody : m.warnBody,
      confirmLabel: remove ? m.actionRemove : m.actionWarn,
      destructive: true,
    );
    if (reason == null || !mounted) return false;
    final id = '${c['id']}';
    return _run(id, () async {
      await ModerationService.resolveCase(id, decision, reason);
      if (!mounted) return;
      showModSnack(context, remove ? m.doneRemoved : m.doneWarned);
      _reload();
    });
  }

  Future<bool> _restrict(Map<String, dynamic> c) async {
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
    if (choice == null || !mounted) return false;
    if (isSevereRestriction(choice.scopes, choice.duration)) {
      final ok = await confirmModAction(context,
          title: m.restrictTitle, body: m.severeWarning, confirmLabel: m.confirm, destructive: true);
      if (!ok || !mounted) return false;
    }
    final id = '${c['id']}';
    return _run(id, () async {
      await ModerationService.restrict(
          caseId: id, scopes: choice.scopes, duration: choice.duration, reason: choice.reason);
      if (!mounted) return;
      showModSnack(context, m.doneRestricted);
      _reload();
    });
  }

  Future<bool> _unmask(Map<String, dynamic> c) async {
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
    if (reason == null || !mounted) return false;
    final id = '${c['id']}';
    return _run(id, () async {
      final who = await ModerationService.unmask('${c['target_type']}', '${c['target_id']}', reason);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(m.unmaskTitle),
          content: SelectableText(who == null || who['author_id'] == null
              ? m.unmaskNone
              : m.unmaskResult.fill([who['display_name'] ?? '?', who['username'] ?? '?'])),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(m.ok))],
        ),
      );
    });
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

  Future<void> _bulkResolve(String decision) async {
    final m = modStrings(context);
    final remove = decision == 'remove';
    final ids = _bulk.toList();
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
      if (mounted) showModSnack(context, m.bulkDone.fill([n]));
    } catch (e) {
      if (mounted) showModError(context, e);
    }
    _reload();
  }

  late final CaseActions _actions = CaseActions(
    dismissOrRestore: _dismissOrRestore,
    remove: (c) => _uphold(c, 'remove'),
    warn: (c) => _uphold(c, 'warn'),
    restrict: _restrict,
    unmask: _unmask,
    open: _open,
  );

  // ------------------------------------------------------------ keyboard
  void _move(int delta) {
    if (_loaded.isEmpty) return;
    final i = _loaded.indexWhere((c) => '${c['id']}' == _selectedId);
    final next = (i + delta).clamp(0, _loaded.length - 1);
    setState(() => _selectedId = '${_loaded[next]['id']}');
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= kCaseMasterDetailWidth;

  void _withSelected(void Function(Map<String, dynamic> c) f) {
    final c = _selected;
    if (c == null) return;
    final active = c['status'] == 'open' || c['status'] == 'hidden';
    if (active && !_busy.contains('${c['id']}')) f(c);
  }

  // ------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    return CaseShortcuts(
      onNext: () => _move(1),
      onPrev: () => _move(-1),
      onOpen: () {
        final c = _selected;
        if (c != null && !_wide) {
          CaseWorkspace.pushDetail(context,
              data: c, detail: _detailFor('${c['id']}'), actions: _actions);
        }
      },
      onDismiss: () => _withSelected(_dismissOrRestore),
      onHide: () => _withSelected((c) {
        if (isHideableType('${c['target_type']}')) _uphold(c, 'remove');
      }),
      onRestore: () => _withSelected((c) {
        if (c['status'] == 'hidden') {
          _dismissOrRestore(c);
        } else {
          showModSnack(context, m.ui.restoreNotHidden);
        }
      }),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _cases,
        builder: (context, snap) {
          final header = _filters(m);
          if (snap.connectionState != ConnectionState.done) {
            return Column(children: [header, const Expanded(child: _ListSkeleton())]);
          }
          if (snap.hasError) {
            return Column(children: [
              header,
              Expanded(
                child: ErrorState(
                  onRetry: _reload,
                  message: modErrorText(context, snap.error!, fallback: context.l10n.connectionError),
                ),
              ),
            ]);
          }
          final cases = snap.data!;
          if (cases.isEmpty) {
            final unfiltered = _status == 'active' && _type == null && _category == null;
            return Column(children: [
              header,
              Expanded(
                child: ModEmptyState(
                  icon: Icons.check_circle_outline,
                  title: unfiltered ? m.noOpenCases : m.noCasesFilter,
                  body: unfiltered ? m.noOpenCasesBody : null,
                ),
              ),
            ]);
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: CaseWorkspace(
              cases: cases,
              selectedId: _selectedId,
              onSelect: (c) => setState(() => _selectedId = '${c['id']}'),
              detailFor: _detailFor,
              actions: _actions,
              busyIds: _busy,
              listHeader: header,
              bulkMode: _bulkMode,
              bulkSelected: _bulk,
              onBulkToggle: (id, v) => setState(() => v ? _bulk.add(id) : _bulk.remove(id)),
              onRetryDetail: (id) => setState(() => _details.remove(id)),
            ),
          );
        },
      ),
    );
  }

  Widget _filters(ModerationStrings m) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              for (final (value, label) in [
                ('active', m.filterActive),
                ('hidden', m.filterHidden),
                ('resolved', m.filterResolved),
                (null, m.filterAll),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _status == value,
                  onSelected: (_) {
                    _status = value;
                    _reload();
                  },
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 6),
              DropdownButton<String?>(
                value: _type,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: null, child: Text(m.allTypes)),
                  for (final t in kTargetTypes) DropdownMenuItem(value: t, child: Text(m.typeLabel(t))),
                ],
                onChanged: (v) {
                  _type = v;
                  _reload();
                },
              ),
              const SizedBox(width: 12),
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
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: ShortcutHint()),
        if (_bulkMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_bulk.isEmpty ? m.bulkHint : m.bulkSelected.fill([_bulk.length]),
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                TextButton(
                    onPressed: _bulk.isEmpty ? null : () => _bulkResolve('dismiss'),
                    child: Text(m.bulkDismiss)),
                FilledButton.tonal(
                    onPressed: _bulk.isEmpty ? null : () => _bulkResolve('remove'),
                    child: Text(m.bulkRemove)),
              ],
            ),
          ),
        Divider(height: 1, color: scheme.outlineVariant),
      ],
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(radius: 20, backgroundColor: scheme.surfaceContainerHighest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: double.infinity, color: scheme.surfaceContainerHighest),
                  const SizedBox(height: 6),
                  Container(height: 10, width: 120, color: scheme.surfaceContainerHigh),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
