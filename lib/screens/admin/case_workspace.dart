import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../widgets/moderation_ui.dart';
import 'case_detail.dart';
import 'case_list.dart';

/// Width at which the console shows list and detail side by side.
const kCaseMasterDetailWidth = 900.0;

/// List + detail, responsive. ≥ 900 px: master–detail; narrower: the
/// list alone, and choosing a case pushes its detail page. Purely
/// presentational — data and actions come from the caller, which is
/// what lets widget tests render it without Supabase.
class CaseWorkspace extends StatelessWidget {
  final List<Map<String, dynamic>> cases;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final Future<Map<String, dynamic>>? Function(String caseId) detailFor;
  final CaseActions actions;
  final Set<String> busyIds;
  final Widget? listHeader;
  final bool bulkMode;
  final Set<String> bulkSelected;
  final void Function(String id, bool selected)? onBulkToggle;
  final void Function(String caseId)? onRetryDetail;
  final ScrollController? listController;

  const CaseWorkspace({
    super.key,
    required this.cases,
    required this.selectedId,
    required this.onSelect,
    required this.detailFor,
    required this.actions,
    this.busyIds = const {},
    this.listHeader,
    this.bulkMode = false,
    this.bulkSelected = const {},
    this.onBulkToggle,
    this.onRetryDetail,
    this.listController,
  });

  Map<String, dynamic>? get _selected =>
      cases.where((c) => '${c['id']}' == selectedId).firstOrNull;

  /// Pushes the full-screen detail page (compact layouts).
  static Future<void> pushDetail(
    BuildContext context, {
    required Map<String, dynamic> data,
    required Future<Map<String, dynamic>>? detail,
    required CaseActions actions,
  }) {
    final m = context.l10nRead.mod;
    // Actions that complete close the page and return to the list.
    Future<bool> Function(Map<String, dynamic>) closing(
            BuildContext pageContext, Future<bool> Function(Map<String, dynamic>) f) =>
        (c) async {
          final done = await f(c);
          if (done && pageContext.mounted) Navigator.of(pageContext).maybePop();
          return done;
        };
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (pageContext) => Scaffold(
        appBar: AppBar(
          title: Text(m.typeLabel(data['target_type'] as String?)),
          leading: BackButton(onPressed: () => Navigator.of(pageContext).maybePop()),
        ),
        body: CaseDetailPane(
          data: data,
          detail: detail,
          actions: CaseActions(
            dismissOrRestore: closing(pageContext, actions.dismissOrRestore),
            remove: closing(pageContext, actions.remove),
            warn: closing(pageContext, actions.warn),
            restrict: closing(pageContext, actions.restrict),
            unmask: actions.unmask,
            open: actions.open,
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kCaseMasterDetailWidth;
      final list = CaseListPane(
        cases: cases,
        selectedId: wide ? selectedId : null,
        controller: listController,
        bulkMode: bulkMode,
        bulkSelected: bulkSelected,
        onBulkToggle: onBulkToggle,
        onSelect: (c) {
          onSelect(c);
          if (!wide) {
            pushDetail(context, data: c, detail: detailFor('${c['id']}'), actions: actions);
          }
        },
      );
      final listColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?listHeader, Expanded(child: list)],
      );
      if (!wide) return listColumn;

      final selected = _selected;
      final listWidth = (box.maxWidth * 0.36).clamp(320.0, 440.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: listWidth, child: listColumn),
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected == null
                  ? ModEmptyState(
                      key: const ValueKey('none'),
                      icon: Icons.ads_click,
                      title: m.ui.selectCase,
                      body: m.ui.selectCaseBody,
                    )
                  : CaseDetailPane(
                      key: ValueKey(selectedId),
                      data: selected,
                      detail: detailFor('${selected['id']}'),
                      actions: actions,
                      busy: busyIds.contains('${selected['id']}'),
                      onRetryDetail:
                          onRetryDetail == null ? null : () => onRetryDetail!('${selected['id']}'),
                    ),
            ),
          ),
        ],
      );
    });
  }
}

/// Keyboard map for the queue (web / keyboards): j/k move, Enter opens
/// on compact, d dismiss-or-restore, h hide (remove), r restore, ? help.
class CaseShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onHide;
  final VoidCallback onRestore;

  const CaseShortcuts({
    super.key,
    required this.child,
    required this.onNext,
    required this.onPrev,
    required this.onOpen,
    required this.onDismiss,
    required this.onHide,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ): onNext,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): onNext,
        const SingleActivator(LogicalKeyboardKey.keyK): onPrev,
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): onPrev,
        const SingleActivator(LogicalKeyboardKey.enter): onOpen,
        const SingleActivator(LogicalKeyboardKey.keyD): onDismiss,
        const SingleActivator(LogicalKeyboardKey.keyH): onHide,
        const SingleActivator(LogicalKeyboardKey.keyR): onRestore,
        const CharacterActivator('?'): () => showShortcutHelp(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

Future<void> showShortcutHelp(BuildContext context) {
  final u = context.l10nRead.mod.ui;
  final rows = [
    ('j', u.scNext),
    ('k', u.scPrev),
    ('d', u.scDismiss),
    ('h', u.scHide),
    ('r', u.scRestore),
    ('?', u.scHelp),
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(u.shortcutsTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, label) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    KeyCap(key),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(u.done)),
        ],
      );
    },
  );
}

class KeyCap extends StatelessWidget {
  final String label;
  const KeyCap(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontFamily: 'monospace')),
    );
  }
}

/// Visible hint for keyboard users; shown on web and wide layouts.
class ShortcutHint extends StatelessWidget {
  const ShortcutHint({super.key});

  @override
  Widget build(BuildContext context) {
    final u = context.l10n.mod.ui;
    final theme = Theme.of(context);
    if (!kIsWeb && MediaQuery.sizeOf(context).width < kCaseMasterDetailWidth) {
      return const SizedBox.shrink();
    }
    return InkWell(
      onTap: () => showShortcutHelp(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(u.shortcutsHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}
