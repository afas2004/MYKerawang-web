import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/form_service.dart';
import '../../theme/tokens.dart';
import '../../utils/adaptive.dart';
import '../../utils/app_nav.dart';
import '../../utils/feedback.dart';
import '../../utils/form_rules.dart';
import '../../utils/responsive.dart';
import '../../theme/app_icons.dart';
import '../../widgets/restriction_gate.dart';

/// The form editor: pick a starting point, then one plain list of questions.
///
/// Deliberately small — label, kind, required, options, scale, analysis tag,
/// move, delete. No drag-and-drop, no sections, no live preview: the published
/// form is the preview. `save_event_form()` writes the whole list at once, and
/// the server refuses the changes that would change what a past answer meant.
class FormEditorScreen extends StatefulWidget {
  final String eventId;

  /// Open this form directly; null means "the event's newest form, or the
  /// start chooser if it has none".
  final String? formId;

  const FormEditorScreen({super.key, required this.eventId, this.formId});

  @override
  State<FormEditorScreen> createState() => _FormEditorScreenState();
}

class _FormEditorScreenState extends State<FormEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _introCtrl = TextEditingController();

  FormDoc? _doc;
  List<FormFieldSpec> _fields = [];
  bool _requireRsvp = false;
  bool _afterCheckin = false;

  bool _loading = true;
  bool _saving = false;
  bool _choosing = false;
  bool _dirty = false;

  List<FormTemplate> _templates = const [];
  List<FieldProblem> _problems = const [];
  Object? _error;

  bool get _readOnly => _doc != null && _doc!.status == 'closed';

  @override
  void initState() {
    super.initState();
    FormGuard.register(() => _dirty);
    _open();
  }

  @override
  void dispose() {
    FormGuard.clear();
    _titleCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String? id = widget.formId;
      if (id == null) {
        final summary = await FormService.instance.summary(widget.eventId);
        id = summary?.id;
      }
      if (id == null) {
        final templates = await FormService.instance.templates();
        if (!mounted) return;
        setState(() {
          _templates = templates;
          _choosing = true;
          _loading = false;
        });
        return;
      }
      final view = await FormService.instance.load(id);
      if (!mounted) return;
      _apply(view.doc);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _apply(FormDoc doc) {
    _doc = doc;
    _fields = List.of(doc.fields);
    _requireRsvp = doc.requireRsvp;
    _afterCheckin = doc.afterCheckin;
    _titleCtrl.text = doc.title;
    _introCtrl.text = doc.intro ?? '';
    _dirty = false;
    _problems = const [];
  }

  Future<void> _start(Future<String> Function() create) async {
    setState(() => _saving = true);
    try {
      final id = await create();
      final view = await FormService.instance.load(id);
      if (!mounted) return;
      _apply(view.doc);
      setState(() {
        _choosing = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorWithRetry(context, e, onRetry: _open);
    }
  }

  Future<void> _startBlank() => _start(() => FormService.instance.createBlank(widget.eventId));

  Future<void> _startTemplate(String slug) =>
      _start(() => FormService.instance.createFromTemplate(widget.eventId, slug));

  Future<void> _startPaste() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteDialog(),
    );
    if (text == null || text.trim().isEmpty) return;

    final paste = parseFieldPaste(text);
    if (paste.fields.isEmpty) {
      if (mounted) _toast(context.l10nRead.formPasteEmpty);
      return;
    }

    // A form row is created first: every later write targets a form id.
    setState(() => _saving = true);
    try {
      final id = await FormService.instance.createBlank(widget.eventId);
      final view = await FormService.instance.load(id);
      if (!mounted) return;
      _apply(view.doc);
      setState(() {
        _fields = paste.fields;
        _problems = paste.problems;
        _dirty = true;
        _choosing = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorWithRetry(context, e, onRetry: _startPaste);
    }
  }

  // ------------------------------------------------------------------- saving

  Future<bool> _save({bool quiet = false}) async {
    final doc = _doc;
    if (doc == null) return false;

    final problems = checkFields(_fields);
    setState(() => _problems = problems);
    if (problems.isNotEmpty) {
      if (!quiet) _toast(context.l10nRead.formIssueText(problems.first.code));
      return false;
    }

    setState(() => _saving = true);
    try {
      await FormService.instance.save(doc.copyWith(
        title: _titleCtrl.text.trim().isEmpty ? doc.title : _titleCtrl.text.trim(),
        intro: _introCtrl.text.trim(),
        requireRsvp: _requireRsvp,
        afterCheckin: _afterCheckin,
        fields: _fields,
      ));
      // New fields only get their ids when they come back, and the next save
      // matches on those ids — without this reload every save would insert
      // another copy of every question added since the last one.
      final fresh = await FormService.instance.load(doc.id);
      if (!mounted) return false;
      _apply(fresh.doc);
      setState(() => _saving = false);
      notifyContentChanged();
      if (!quiet) _toast(context.l10nRead.formSaved);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      showErrorWithRetry(context, e, onRetry: _save);
      return false;
    }
  }

  Future<void> _publish() async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.formPublishConfirmTitle),
        content: Text(s.formPublishConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.formPublish)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _save(quiet: true)) return;
    try {
      await FormService.instance.publish(_doc!.id);
      if (!mounted) return;
      setState(() => _doc = _doc!.copyWith(status: 'open'));
      notifyContentChanged();
      _toast(context.l10nRead.formPublished);
    } catch (e) {
      if (mounted) showErrorWithRetry(context, e, onRetry: _publish);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ editing

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
      _problems = const [];
    });
  }

  Future<void> _editField(int index) async {
    final s = context.l10nRead;
    final result = await showDialog<FormFieldSpec>(
      context: context,
      builder: (_) => _FieldSheet(field: _fields[index], strings: s),
    );
    if (result == null || !mounted) return;
    _changed(() => _fields[index] = result);
  }

  void _move(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _fields.length) return;
    _changed(() {
      final f = _fields.removeAt(index);
      _fields.insert(to, f);
    });
  }

  List<String> _problemsFor(int index) =>
      [for (final p in _problems) if (p.index == index) p.code];

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final doc = _doc;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: Responsive.detailMaxWidth,
        title: Text(
          s.formEditorTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (doc != null)
            IconButton(
              tooltip: s.formResponsesTitle,
              icon: const Icon(AppIcons.list),
              onPressed: () => context.push('/event/${widget.eventId}/form/responses'),
            ),
          if (doc != null && !_readOnly)
            IconButton(
              tooltip: s.formSave,
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.check),
            ),
          if (doc != null && doc.isDraft)
            Padding(
              padding: const EdgeInsets.only(right: KSpace.s),
              child: TextButton(
                onPressed: _saving ? null : _publish,
                child: Text(s.formPublish),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(error: _error!, onRetry: _open)
              : _choosing
                  ? _chooser(context)
                  : _editor(context, doc!),
    );
  }

  // ------------------------------------------------------------------- chooser

  Widget _chooser(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(KSpace.l),
          children: [
            Text(s.formStartTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: KSpace.m),
            for (final t in _templates)
              Padding(
                padding: const EdgeInsets.only(bottom: KSpace.m),
                child: _StartCard(
                  icon: AppIcons.announcement,
                  title: t.label(identical(s, AppStrings.ms)),
                  subtitle: s.formStartTemplateSub,
                  onTap: _saving ? null : () => _startTemplate(t.slug),
                ),
              ),
            _StartCard(
              icon: AppIcons.compose,
              title: s.formStartBlank,
              subtitle: s.formStartBlankSub,
              onTap: _saving ? null : _startBlank,
            ),
            const SizedBox(height: KSpace.m),
            _StartCard(
              icon: AppIcons.copy,
              title: s.formStartPaste,
              subtitle: s.formStartPasteSub,
              onTap: _saving ? null : _startPaste,
            ),
            const SizedBox(height: KSpace.l),
            Text(
              s.formNoFields,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- editor

  Widget _editor(BuildContext context, FormDoc doc) {
    final s = context.l10n;
    final canAdd = (_fields.length < kMaxFormFields) && !_readOnly;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, KSpace.xxl),
          children: [
            if (!doc.isDraft) _StatusLine(status: doc.status, strings: s),
            TextField(
              controller: _titleCtrl,
              enabled: !_readOnly,
              onChanged: (_) => _changed(() {}),
              decoration: InputDecoration(labelText: s.formTitleLabel),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: KSpace.m),
            TextField(
              controller: _introCtrl,
              enabled: !_readOnly,
              onChanged: (_) => _changed(() {}),
              maxLines: 2,
              decoration: InputDecoration(labelText: s.formIntroLabel),
            ),
            const SizedBox(height: KSpace.s),
            SwitchListTile(
              value: _requireRsvp,
              onChanged: _readOnly ? null : (v) => _changed(() => _requireRsvp = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.formRequireRsvp, style: Theme.of(context).textTheme.bodyMedium),
            ),
            SwitchListTile(
              value: _afterCheckin,
              onChanged: _readOnly ? null : (v) => _changed(() => _afterCheckin = v),
              contentPadding: EdgeInsets.zero,
              title: Text(s.formAfterCheckin, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const Divider(height: KSpace.xl),
            if (_fields.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: KSpace.l),
                child: Text(s.formNoFields, style: Theme.of(context).textTheme.bodyMedium),
              ),
            for (var i = 0; i < _fields.length; i++)
              _FieldTile(
                field: _fields[i],
                index: i,
                problems: _problemsFor(i),
                readOnly: _readOnly,
                isFirst: i == 0,
                isLast: i == _fields.length - 1,
                onEdit: () => _editField(i),
                onUp: () => _move(i, -1),
                onDown: () => _move(i, 1),
                onDelete: () => _changed(() => _fields.removeAt(i)),
              ),
            if (canAdd) ...[
              const SizedBox(height: KSpace.m),
              OutlinedButton.icon(
                onPressed: () => _changed(() => _fields.add(blankField())),
                icon: const Icon(AppIcons.create, size: 18),
                label: Text(s.formAddField),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ],
            if (_problems.any((p) => p.index < 0)) ...[
              const SizedBox(height: KSpace.m),
              for (final p in _problems.where((p) => p.index < 0))
                Padding(
                  padding: const EdgeInsets.only(bottom: KSpace.xs),
                  child: Text(
                    s.formIssueText(p.code),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- pieces

/// Dialog content width: 520 on a wide window, the window less its own insets
/// on a phone (AlertDialog does not shrink a fixed-width child).
double _dialogWidth(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - 96;
  if (available >= 520) return 520;
  return available < 200 ? 200 : available;
}

class _StartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _StartCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(KSpace.l),
          child: Row(
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String status;
  final AppStrings strings;
  const _StatusLine({required this.status, required this.strings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (status) {
      'open' => strings.formOpen,
      'closed' => strings.formClosed,
      _ => strings.formDraft,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: Row(
        children: [
          Icon(AppIcons.info, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: KSpace.xs),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final FormFieldSpec field;
  final int index;
  final List<String> problems;
  final bool readOnly;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;

  const _FieldTile({
    required this.field,
    required this.index,
    required this.problems,
    required this.readOnly,
    required this.isFirst,
    required this.isLast,
    required this.onEdit,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final bad = problems.isNotEmpty;
    final bits = <String>[
      s.formKindLabel(field.kind),
      if (field.required && field.kind != 'heading') s.formFieldRequired,
      if (field.analysis == 'ki_pre') 'KI ${field.kiCode} · ${s.formTagKiPre}',
      if (field.analysis == 'ki_post') 'KI ${field.kiCode} · ${s.formTagKiPost}',
      if (field.analysis == 'feedback') s.formTagFeedback,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: KSpace.s),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bad ? scheme.error : scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: readOnly ? null : onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.xs, KSpace.s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label.trim().isEmpty
                          ? s.formIssueText(FormIssue.labelRequired)
                          : field.label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: field.kind == 'heading' ? FontWeight.w700 : null,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bits.join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: bad ? scheme.error : scheme.onSurfaceVariant),
                    ),
                    if (bad)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.formIssueText(problems.first),
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              if (!readOnly) ...[
                IconButton(
                  tooltip: s.formMoveUp,
                  onPressed: isFirst ? null : onUp,
                  icon: const Icon(AppIcons.up, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: s.formMoveDown,
                  onPressed: isLast ? null : onDown,
                  icon: const Icon(AppIcons.down, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: s.delete,
                  onPressed: onDelete,
                  icon: Icon(AppIcons.delete, size: 18, color: scheme.error),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.warning, size: 32, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: KSpace.m),
            Text(describeWriteError(context, error), textAlign: TextAlign.center),
            const SizedBox(height: KSpace.m),
            FilledButton(onPressed: onRetry, child: Text(s.refresh)),
          ],
        ),
      ),
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return AlertDialog(
      title: Text(s.formPasteTitle),
      content: SizedBox(
        width: _dialogWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.formPasteHelp, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: KSpace.s),
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 6,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(hintText: s.formPasteHint, border: const OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(s.next),
        ),
      ],
    );
  }
}

/// One field, edited in a dialog. Returns the new spec, or null on cancel.
class _FieldSheet extends StatefulWidget {
  final FormFieldSpec field;
  final AppStrings strings;
  const _FieldSheet({required this.field, required this.strings});

  @override
  State<_FieldSheet> createState() => _FieldSheetState();
}

class _FieldSheetState extends State<_FieldSheet> {
  late final TextEditingController _label;
  late final TextEditingController _help;
  late final TextEditingController _choices;
  late String _kind;
  late bool _required;
  late int _min;
  late int _max;
  String? _analysis;
  int? _kiCode;

  @override
  void initState() {
    super.initState();
    final f = widget.field;
    _label = TextEditingController(text: f.label);
    _help = TextEditingController(text: f.help ?? '');
    _choices = TextEditingController(text: f.choices.join('\n'));
    _kind = f.kind;
    _required = f.required;
    _min = f.min;
    _max = f.max;
    _analysis = f.analysis;
    _kiCode = f.kiCode;
  }

  @override
  void dispose() {
    _label.dispose();
    _help.dispose();
    _choices.dispose();
    super.dispose();
  }

  void _setKind(String kind) {
    setState(() {
      _kind = kind;
      if (kind != 'rating') {
        _analysis = null;
        _kiCode = null;
      }
      if (kind == 'heading') _required = false;
    });
  }

  void _setAnalysis(String? analysis) {
    setState(() {
      _analysis = analysis;
      if (analysis == null || analysis == 'feedback') _kiCode = null;
      if (analysis == 'ki_pre' || analysis == 'ki_post') _kiCode ??= 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final isRating = _kind == 'rating';
    final isChoice = kChoiceKinds.contains(_kind);

    return AlertDialog(
      title: Text(s.formFieldLabel),
      content: SizedBox(
        width: _dialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _label,
                autofocus: true,
                decoration: InputDecoration(labelText: s.formFieldLabel),
              ),
              const SizedBox(height: KSpace.m),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _kind,
                decoration: InputDecoration(labelText: s.formFieldKind),
                items: [
                  for (final k in kFormKinds)
                    DropdownMenuItem(value: k, child: Text(s.formKindLabel(k))),
                ],
                onChanged: (k) => k == null ? null : _setKind(k),
              ),
              const SizedBox(height: KSpace.m),
              TextField(
                controller: _help,
                decoration: InputDecoration(labelText: s.formFieldHelp),
              ),
              if (isChoice) ...[
                const SizedBox(height: KSpace.m),
                TextField(
                  controller: _choices,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: s.formFieldChoices,
                    helperText: s.formFieldChoicesHint,
                  ),
                ),
              ],
              if (isRating) ...[
                const SizedBox(height: KSpace.m),
                Row(
                  children: [
                    Text(s.formFieldScale),
                    const SizedBox(width: KSpace.m),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _max,
                        items: [
                          for (var v = 2; v <= 10; v++)
                            DropdownMenuItem(value: v, child: Text('1 – $v')),
                        ],
                        onChanged: (v) => setState(() => _max = v ?? _max),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KSpace.s),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _analysis ?? 'none',
                  decoration: InputDecoration(labelText: s.formFieldAnalysis),
                  items: [
                    DropdownMenuItem(value: 'none', child: Text(s.formTagNone)),
                    DropdownMenuItem(value: 'ki_pre', child: Text(s.formTagKiPre)),
                    DropdownMenuItem(value: 'ki_post', child: Text(s.formTagKiPost)),
                    DropdownMenuItem(value: 'feedback', child: Text(s.formTagFeedback)),
                  ],
                  onChanged: (v) => _setAnalysis(v == 'none' ? null : v),
                ),
                if (_analysis == 'ki_pre' || _analysis == 'ki_post') ...[
                  const SizedBox(height: KSpace.s),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _kiCode ?? 1,
                    decoration: InputDecoration(labelText: s.formFieldKiCode),
                    items: [
                      for (var i = 1; i <= 7; i++)
                        DropdownMenuItem(value: i, child: Text('KI$i')),
                    ],
                    onChanged: (v) => setState(() => _kiCode = v),
                  ),
                ],
              ],
              const SizedBox(height: KSpace.s),
              SwitchListTile(
                value: _required,
                onChanged: _kind == 'heading' ? null : (v) => setState(() => _required = v),
                contentPadding: EdgeInsets.zero,
                title: Text(s.formFieldRequired),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: () {
            final choices = _choices.text
                .split(RegExp(r'\r?\n'))
                .map((c) => c.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            Navigator.pop(
              context,
              widget.field.copyWith(
                kind: _kind,
                label: _label.text.trim(),
                help: _help.text.trim().isEmpty ? null : _help.text.trim(),
                required: _required,
                choices: choices,
                min: _min,
                max: _max,
                analysis: _analysis,
                kiCode: _kiCode,
                clearAnalysis: _analysis == null,
              ),
            );
          },
          child: Text(s.save),
        ),
      ],
    );
  }
}
