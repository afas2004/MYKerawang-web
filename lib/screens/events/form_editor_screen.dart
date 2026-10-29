import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/form_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../utils/adaptive.dart';
import '../../utils/app_nav.dart';
import '../../utils/feedback.dart';
import '../../utils/form_rules.dart';
import '../../utils/responsive.dart';
import '../../utils/text_rules.dart';
import '../../widgets/form_style.dart';
import '../../widgets/restriction_gate.dart';

/// The form editor: one row per question, and every setting a question has is
/// on that row.
///
/// The previous editor kept the question's settings (type, scale, options,
/// counting tag, KI element, required) behind a dialog, so the only way to
/// answer "what does this form actually measure?" was to open 28 dialogs and
/// remember each one. Here the row carries all of it: the controls line up
/// down the list, and a row that is not counted says so instead of hiding the
/// controls it does not have.
///
/// Reordering has both affordances: drag the handle (a `ReorderableListView`),
/// or use the arrows — same list, two ways in.
///
/// `save_event_form()` still writes the whole list at once, and the server
/// still refuses the changes that would alter what a past answer meant.
///
/// A standalone form (`/f/:id/edit`, [eventId] null) uses the same editor
/// without the event settings, plus a safety card: the no-personal-data note,
/// and the questions the server would refuse or that ask for IC, bank or
/// address details.
class FormEditorScreen extends StatefulWidget {
  /// The event whose form this is; null for a standalone form.
  final String? eventId;

  /// Open this form directly; null means "the event's newest form, or the
  /// start chooser if it has none".
  final String? formId;

  const FormEditorScreen({super.key, this.eventId, this.formId})
      : assert(eventId != null || formId != null);

  @override
  State<FormEditorScreen> createState() => _FormEditorScreenState();
}

class _FormEditorScreenState extends State<FormEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _introCtrl = TextEditingController();

  FormDoc? _doc;
  List<_Row> _rows = [];
  List<FieldProblem> _problems = const [];

  bool _requireRsvp = false;
  bool _afterCheckin = false;

  bool _loading = true;
  bool _saving = false;
  bool _choosing = false;
  bool _dirty = false;

  List<FormTemplate> _templates = const [];
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
    for (final r in _rows) {
      r.dispose();
    }
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
      if (id == null && widget.eventId != null) {
        final summary = await FormService.instance.summary(widget.eventId!);
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
    for (final r in _rows) {
      r.dispose();
    }
    _doc = doc;
    _rows = [for (final f in doc.fields) _Row(f)];
    _requireRsvp = doc.requireRsvp;
    _afterCheckin = doc.afterCheckin;
    _titleCtrl.text = doc.title;
    _introCtrl.text = doc.intro ?? '';
    _dirty = false;
    _problems = const [];
  }

  List<FormFieldSpec> get _specs => [for (final r in _rows) r.value];

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

  Future<void> _startBlank() =>
      _start(() => FormService.instance.createBlank(widget.eventId!));

  Future<void> _startTemplate(String slug) =>
      _start(() => FormService.instance.createFromTemplate(widget.eventId!, slug));

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
      final id = await FormService.instance.createBlank(widget.eventId!);
      final view = await FormService.instance.load(id);
      if (!mounted) return;
      _apply(view.doc);
      setState(() {
        for (final r in _rows) {
          r.dispose();
        }
        _rows = [for (final f in paste.fields) _Row(f)];
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

    final problems = checkFields(_specs);
    setState(() => _problems = problems);
    if (problems.isNotEmpty) {
      if (!quiet) _toast(context.l10nRead.formIssueText(problems.first.code));
      return false;
    }
    // The server refuses these on a standalone form; say so before the trip.
    if (doc.standalone && blockedFieldIndexes(_specs).isNotEmpty) {
      _toast(context.l10nRead.formBlockedLabel);
      return false;
    }

    setState(() => _saving = true);
    try {
      await FormService.instance.save(doc.copyWith(
        title: cleanLine(_titleCtrl.text).isEmpty
            ? doc.title
            : cleanLine(_titleCtrl.text),
        intro: cleanBlock(_introCtrl.text),
        requireRsvp: _requireRsvp,
        afterCheckin: _afterCheckin,
        fields: _specs,
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
      showErrorWithRetry(context, e,
          onRetry: _save, message: context.l10nRead.formServerError(formErrorCode(e)));
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
      if (mounted) {
        showErrorWithRetry(context, e,
            onRetry: _publish, message: context.l10nRead.formServerError(formErrorCode(e)));
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ editing

  /// A text change: one rebuild to show the dirty state, no re-layout per key.
  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  void _edit(int index, FormFieldSpec next) {
    setState(() {
      _rows[index].spec = next;
      _dirty = true;
      _problems = const [];
    });
  }

  void _setKind(int index, String kind) {
    final base = _rows[index].value;
    final keepAnalysis = kind == 'rating';
    _edit(
      index,
      _with(
        base,
        kind: kind,
        required: kind == 'heading' ? false : base.required,
        clearAnalysis: !keepAnalysis,
        choices: kChoiceKinds.contains(kind)
            // Seeded blank, not "Option 1": the placeholder shows the shape,
            // and the check below asks for real options before publishing.
            ? (base.choices.length < 2 ? const ['', ''] : base.choices)
            : const [],
      ),
    );
  }

  void _setAnalysis(int index, String? analysis) {
    final base = _rows[index].value;
    final needsCode = analysis == 'ki_pre' || analysis == 'ki_post';
    _edit(
      index,
      _with(
        base,
        analysis: analysis,
        clearAnalysis: analysis == null,
        kiCode: needsCode ? (base.kiCode ?? _firstFreeKi(analysis!)) : null,
        clearKi: !needsCode,
      ),
    );
  }

  /// The first KI element not already used in this phase, so tagging a row
  /// usually needs no second tap.
  int _firstFreeKi(String analysis) {
    final taken = {
      for (final r in _rows)
        if (r.spec.analysis == analysis && r.spec.kiCode != null) r.spec.kiCode!,
    };
    for (var i = 1; i <= 7; i++) {
      if (!taken.contains(i)) return i;
    }
    return 1;
  }

  void _move(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _rows.length) return;
    setState(() {
      final row = _rows.removeAt(index);
      _rows.insert(to, row);
      _dirty = true;
      _problems = const [];
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final row = _rows.removeAt(oldIndex);
      _rows.insert(newIndex, row);
      _dirty = true;
      _problems = const [];
    });
  }

  void _duplicate(int index) {
    final src = _rows[index].value;
    final copy = FormFieldSpec(
      kind: src.kind,
      label: '${src.label} (copy)',
      help: src.help,
      required: src.required,
      choices: [...src.choices],
      min: src.min,
      max: src.max,
      analysis: src.analysis,
      kiCode: src.kiCode,
    );
    setState(() {
      _rows.insert(index + 1, _Row(copy));
      _dirty = true;
      _problems = const [];
    });
  }

  void _delete(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _dirty = true;
      _problems = const [];
    });
  }

  void _add({String kind = 'short_text', String label = ''}) {
    setState(() {
      _rows.add(_Row(FormFieldSpec(kind: kind, label: label)));
      _dirty = true;
      _problems = const [];
    });
  }

  /// The analysis tag of the section a row belongs to: the first tagged
  /// question at or after it, stopping at the next heading.
  String? _laneAnalysis(int index) {
    for (var i = index; i < _rows.length; i++) {
      if (i > index && _rows[i].isHeading) break;
      final a = _rows[i].spec.analysis;
      if (a != null) return a;
    }
    return null;
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final doc = _doc;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: 1180,
        // Explicit, so a cold-opened link still has a way up (to the event).
        leading: const AppBackButton(),
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
              // The analyses of *this* form, not of whatever is newest.
              // `from=edit` lets the responses page come back here instead of
              // pushing a second editor on top (that stack grew every round).
              onPressed: () => context.push(
                widget.eventId != null
                    ? '/event/${widget.eventId}/form/responses?f=${doc.id}&from=edit'
                    : '${doc.responsesPath}?from=edit',
              ),
            ),
          if (doc != null && !_readOnly)
            IconButton(
              tooltip: s.formSave,
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final numbers = <int, int>{};
    var n = 0;
    for (var i = 0; i < _rows.length; i++) {
      if (!_rows[i].isHeading) numbers[i] = ++n;
    }

    final list = ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorder: _onReorder,
      itemCount: _rows.length,
      header: _aboveList(context, doc, wide),
      footer: _belowList(context),
      padding: EdgeInsets.fromLTRB(wide ? KSpace.xl : KSpace.l, KSpace.l, wide ? KSpace.xl : KSpace.l, KSpace.xxl),
      itemBuilder: (ctx, i) => _rowTile(ctx, i, numbers: numbers, wide: wide),
    );

    if (!wide) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
          child: list,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: list),
            SizedBox(
              width: 328,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: KSpace.l, right: KSpace.xl, bottom: KSpace.xxl),
                child: _rail(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboveList(BuildContext context, FormDoc doc, bool wide) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: KRadius.card,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StatusChip(status: doc.status),
                ],
              ),
              const SizedBox(height: KSpace.s),
              TextField(
                controller: _titleCtrl,
                enabled: !_readOnly,
                onChanged: (_) => _markDirty(),
                maxLength: kFormTitleMax,
                buildCounter: quietCounter,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  hintText: s.formTitleLabel,
                  contentPadding: const EdgeInsets.symmetric(vertical: KSpace.xs),
                ),
              ),
              TextField(
                controller: _introCtrl,
                enabled: !_readOnly,
                onChanged: (_) => _markDirty(),
                maxLength: kFormIntroMax,
                buildCounter: quietCounter,
                maxLines: 3,
                minLines: 1,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  hintText: s.formIntroLabel,
                  contentPadding: const EdgeInsets.symmetric(vertical: KSpace.xs),
                ),
              ),
              const SizedBox(height: KSpace.m),
              _SummaryChips(specs: _specs),
              // RSVP and check-in belong to an event; a standalone form has none.
              if (!doc.standalone) ...[
              const SizedBox(height: KSpace.m),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: KSpace.m),
              Wrap(
                spacing: KSpace.s,
                runSpacing: KSpace.s,
                children: [
                  _SettingChip(
                    label: s.formRequireRsvp,
                    value: _requireRsvp,
                    onChanged: _readOnly ? null : (v) => _editSetting(() => _requireRsvp = v),
                  ),
                  _SettingChip(
                    label: s.formAfterCheckin,
                    value: _afterCheckin,
                    onChanged: _readOnly ? null : (v) => _editSetting(() => _afterCheckin = v),
                  ),
                ],
              ),
              ],
            ],
          ),
        ),
        if (doc.standalone) ...[
          const SizedBox(height: KSpace.m),
          _SafetyCard(specs: _specs),
        ],
        if (!wide) ...[
          const SizedBox(height: KSpace.m),
          _CompactChecks(specs: _specs),
        ],
        const SizedBox(height: KSpace.m),
      ],
    );
  }

  void _editSetting(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  Widget _rail(BuildContext context) {
    final s = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailCard(
          title: s.formMeasuresTitle,
          sub: s.formMeasuresSub,
          child: _CoverageCard(specs: _specs),
        ),
        const SizedBox(height: KSpace.m),
        _RailCard(
          title: s.formChecksTitle,
          sub: s.formChecksSub,
          child: _ChecksCard(specs: _specs),
        ),
      ],
    );
  }

  Widget _belowList(BuildContext context) {
    final s = context.l10n;
    final canAdd = _rows.length < kMaxFormFields && !_readOnly;
    final global = [for (final p in _problems) if (p.index < 0) p];

    return Padding(
      padding: const EdgeInsets.only(top: KSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canAdd)
            Wrap(
              spacing: KSpace.s,
              runSpacing: KSpace.s,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _add(),
                  icon: const Icon(AppIcons.create, size: 18),
                  label: Text(s.formAddField),
                ),
                OutlinedButton.icon(
                  onPressed: () => _add(kind: 'heading', label: ''),
                  icon: const Icon(AppIcons.list, size: 18),
                  label: Text(s.formSection),
                ),
              ],
            ),
          for (final p in global)
            Padding(
              padding: const EdgeInsets.only(top: KSpace.s),
              child: Text(
                s.formIssueText(p.code),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- one question

  Widget _rowTile(
    BuildContext context,
    int index, {
    required Map<int, int> numbers,
    required bool wide,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final row = _rows[index];
    final style = AnalysisStyle.of(context, _laneAnalysis(index));
    final problems = [
      for (final p in _problems)
        if (p.index == index) p.code,
    ];

    return Container(
      key: ValueKey(row.key),
      decoration: BoxDecoration(
        color: row.isHeading ? style.soft : null,
        border: Border(
          left: BorderSide(color: style.accent, width: 3),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                row.isHeading ? '' : '${numbers[index] ?? ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.xs, KSpace.s, KSpace.s, KSpace.m),
              child: _rowContent(context, index, row, style, problems, wide),
            ),
          ),
          _RowStrip(
            index: index,
            count: _rows.length,
            readOnly: _readOnly,
            onMove: _move,
            onDuplicate: _duplicate,
            onDelete: _delete,
          ),
        ],
      ),
    );
  }

  Widget _rowContent(
    BuildContext context,
    int index,
    _Row row,
    AnalysisStyle style,    List<String> problems,
    bool wide,
  ) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final f = row.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.isHeading)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: style.accent.withValues(alpha: 0.14),
                    borderRadius: KRadius.small,
                  ),
                  child: Text(
                    s.formSection.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: style.ink,
                    ),
                  ),
                ),
              ),
              Expanded(child: _labelField(context, row)),
            ],
          )
        else
          _labelField(context, row),
        if (row.helpOpen || row.help.text.isNotEmpty) _helpField(context, row),
        const SizedBox(height: KSpace.s),
        if (!row.isHeading)
          Wrap(
            spacing: KSpace.s,
            runSpacing: KSpace.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _menu(
                context,
                width: 126,
                value: f.kind,
                options: [for (final k in kFormKinds) (k, s.formKindLabel(k))],
                onChanged: _readOnly ? null : (k) => _setKind(index, k),
              ),
              if (f.isRating) ...[
                _menu(
                  context,
                  width: 118,
                  value: f.analysis ?? '',
                  options: [
                    ('', s.formTagNone),
                    ('ki_pre', s.formTagKiPreShort),
                    ('ki_post', s.formTagKiPostShort),
                    ('feedback', s.formTagFeedbackShort),
                  ],
                  onChanged: _readOnly
                      ? null
                      : (v) => _setAnalysis(index, v.isEmpty ? null : v),
                  background: style.soft,
                  foreground: style.ink,
                  border: f.analysis == null ? scheme.outlineVariant : Colors.transparent,
                ),
                if (f.analysis == 'ki_pre' || f.analysis == 'ki_post')
                  _menu(
                    context,
                    width: 74,
                    value: '${f.kiCode ?? 1}',
                    options: [for (var i = 1; i <= 7; i++) ('$i', 'KI$i')],
                    onChanged: _readOnly
                        ? null
                        : (v) => _edit(index, f.copyWith(kiCode: int.parse(v))),
                  ),
                _menu(
                  context,
                  width: 74,
                  value: '${f.max}',
                  options: [for (var v = 2; v <= 10; v++) ('$v', '1–$v')],
                  onChanged: _readOnly
                      ? null
                      : (v) => _edit(index, f.copyWith(max: int.parse(v))),
                ),
              ] else
                _notCounted(context),
              _RequiredChip(
                value: f.required,
                onChanged: _readOnly ? null : (v) => _edit(index, f.copyWith(required: v)),
              ),
              if (!row.helpOpen && row.help.text.isEmpty && !_readOnly)
                TextButton(
                  onPressed: () => setState(() => row.helpOpen = true),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: KSpace.s),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(s.formAddHelp, style: const TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        if (f.isChoice)
          Padding(
            padding: const EdgeInsets.only(top: KSpace.s),
            child: _ChoiceEditor(
              choices: f.choices,
              readOnly: _readOnly,
              onChanged: (choices) => _edit(index, f.copyWith(choices: choices)),
            ),
          ),
        if (problems.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: KSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, size: 13, color: scheme.error),
                const SizedBox(width: KSpace.xs),
                Expanded(
                  child: Text(
                    s.formIssueText(problems.first),
                    style: TextStyle(fontSize: 11.5, color: scheme.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _labelField(BuildContext context, _Row row) {
    final scheme = Theme.of(context).colorScheme;
    final heading = row.isHeading;
    return TextField(
      controller: row.label,
      enabled: !_readOnly,
      onChanged: (_) => _markDirty(),
      maxLength: kFormLabelMax,
      buildCounter: quietCounter,
      style: heading
          ? Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
          : Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        hintText: heading ? context.l10nRead.formSection : context.l10nRead.formFieldLabel,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: KSpace.xs, vertical: KSpace.s),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _helpField(BuildContext context, _Row row) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: row.help,
      enabled: !_readOnly,
      onChanged: (_) {
        _markDirty();
        setState(() {});
      },
      maxLength: kFormHelpMax,
      buildCounter: quietCounter,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        hintText: context.l10nRead.formFieldHelp,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: KSpace.xs, vertical: 2),
      ),
    );
  }

  Widget _notCounted(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10nRead.formOnlyRatingsCounted,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: KSpace.m),
        decoration: BoxDecoration(
          borderRadius: KRadius.small,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10nRead.formTagNone,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// A compact select: same shape and size as the mockup's pill, but a
  /// `MenuAnchor` so a long option list does not stretch the row.
  Widget _menu(
    BuildContext context, {
    required double width,
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String>? onChanged,
    Color? background,
    Color? foreground,
    Color? border,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onSurface;
    final label = options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 34),
      menuChildren: [
        for (final o in options)
          MenuItemButton(
            onPressed: onChanged == null ? null : () => onChanged(o.$1),
            leadingIcon: o.$1 == value
                ? Icon(AppIcons.check, size: 15, color: scheme.primary)
                : const SizedBox(width: 15, height: 15),
            child: Text(o.$2),
          ),
      ],
      builder: (context, controller, _) => SizedBox(
        width: width,
        height: 32,
        child: Material(
          clipBehavior: Clip.antiAlias,
          color: background ?? scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: KRadius.small,
            side: BorderSide(color: border ?? scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onChanged == null
                ? null
                : () => controller.isOpen ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.only(left: KSpace.s + 1, right: KSpace.xs + 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ),
                  Icon(AppIcons.down, size: 13, color: fg.withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- pieces

/// A copy of [f] with the named parts replaced. [FormFieldSpec.copyWith] keeps
/// a value when the argument is null, which cannot express "clear the KI code",
/// so the editor uses this instead.
FormFieldSpec _with(
  FormFieldSpec f, {
  String? kind,
  String? label,
  String? help,
  bool? required,
  List<String>? choices,
  int? min,
  int? max,
  String? analysis,
  int? kiCode,
  bool clearAnalysis = false,
  bool clearKi = false,
}) =>
    FormFieldSpec(
      id: f.id,
      kind: kind ?? f.kind,
      label: label ?? f.label,
      help: help ?? f.help,
      required: required ?? f.required,
      choices: choices ?? f.choices,
      min: min ?? f.min,
      max: max ?? f.max,
      analysis: clearAnalysis ? null : (analysis ?? f.analysis),
      kiCode: (clearAnalysis || clearKi) ? null : (kiCode ?? f.kiCode),
    );

/// One question in the editor, with its own text controllers.
///
/// Rows outlive a [FormFieldSpec] (immutable, replaced on every change) and
/// own a stable key, which the reorderable list needs to follow a row as it
/// moves.
class _Row {
  _Row(this.spec) : key = ++_seq {
    label = TextEditingController(text: spec.label);
    help = TextEditingController(text: spec.help ?? '');
  }

  static int _seq = 0;

  final int key;
  late FormFieldSpec spec;
  late final TextEditingController label;
  late final TextEditingController help;
  bool helpOpen = false;

  bool get isHeading => spec.kind == 'heading';

  /// What a save sends: the controllers are the truth for the text, cleaned
  /// the same way every time ([cleanLine], [cleanChoices]).
  FormFieldSpec get value => FormFieldSpec(
        id: spec.id,
        kind: spec.kind,
        label: cleanLine(label.text),
        help: help.text.trim().isEmpty ? null : cleanLine(help.text),
        required: spec.required,
        choices: cleanChoices(spec.choices),
        min: spec.min,
        max: spec.max,
        analysis: spec.analysis,
        kiCode: spec.kiCode,
      );

  void dispose() {
    label.dispose();
    help.dispose();
  }
}

/// The control strip at the card's edge: drag handle, arrows, duplicate and
/// delete, in one group that sits in the same place on every row.
class _RowStrip extends StatelessWidget {
  final int index;
  final int count;
  final bool readOnly;
  final void Function(int index, int delta) onMove;
  final void Function(int index) onDuplicate;
  final void Function(int index) onDelete;

  const _RowStrip({
    required this.index,
    required this.count,
    required this.readOnly,
    required this.onMove,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 62,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!readOnly)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: s.formDragHint,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      AppIcons.drag,
                      size: 15,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stripButton(
                context,
                AppIcons.up,
                s.formMoveUp,
                !readOnly && index > 0 ? () => onMove(index, -1) : null,
              ),
              _stripButton(
                context,
                AppIcons.down,
                s.formMoveDown,
                !readOnly && index < count - 1 ? () => onMove(index, 1) : null,
              ),
            ],
          ),
          if (!readOnly)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stripButton(context, AppIcons.copy, s.formDuplicate, () => onDuplicate(index)),
                _stripButton(context, AppIcons.delete, s.delete, () => onDelete(index), danger: true),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stripButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool danger = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 15),
      color: danger ? scheme.error : scheme.onSurfaceVariant,
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 28),
        maximumSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }
}

/// The choices of a choice field: each one is a field you can type in, with
/// its own remove button. (The first version of this rewrite could only add
/// and delete options, never name them — that was a regression.)
///
/// The controllers live here, not in the parent: a keystroke updates the row,
/// which rebuilds, and rebuilding must not reset what is being typed.
class _ChoiceEditor extends StatefulWidget {
  final List<String> choices;
  final bool readOnly;
  final ValueChanged<List<String>> onChanged;

  const _ChoiceEditor({
    required this.choices,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<_ChoiceEditor> createState() => _ChoiceEditorState();
}

class _ChoiceEditorState extends State<_ChoiceEditor> {
  late List<TextEditingController> _ctrls = _controllersFor(widget.choices);

  List<TextEditingController> _controllersFor(List<String> choices) =>
      [for (final c in choices) TextEditingController(text: c)];

  @override
  void didUpdateWidget(covariant _ChoiceEditor old) {
    super.didUpdateWidget(old);
    // Only when the number of options changes from outside (add / remove /
    // a reload). Typing leaves the length alone, so the text is untouched.
    if (old.choices.length != widget.choices.length) {
      for (final c in _ctrls) {
        c.dispose();
      }
      _ctrls = _controllersFor(widget.choices);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(int i, String value) {
    final next = [...widget.choices];
    while (next.length <= i) {
      next.add('');
    }
    next[i] = value;
    widget.onChanged(next);
  }

  void _remove(int i) {
    widget.onChanged([...widget.choices]..removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Wrap(
      spacing: KSpace.s,
      runSpacing: KSpace.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < _ctrls.length; i++) _option(context, i),
        if (!widget.readOnly)
          ActionChip(
            avatar: const Icon(AppIcons.create, size: 14),
            label: Text(s.formAddOption),
            visualDensity: VisualDensity.compact,
            onPressed: widget.choices.length >= kChoiceCountMax
                ? null
                : () => widget.onChanged([...widget.choices, '']),
          ),
      ],
    );
  }

  Widget _option(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 168,
      height: 34,
      padding: const EdgeInsets.only(left: KSpace.s + 2, right: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: KRadius.small,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: ValueKey('option-$i'),
              controller: _ctrls[i],
              enabled: !widget.readOnly,
              maxLength: kChoiceMax,
              maxLines: 1,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                counterText: '',
                hintText: '${context.l10nRead.formFieldChoices} ${i + 1}',
                hintStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(vertical: KSpace.s),
              ),
              onChanged: (v) => _set(i, v),
            ),
          ),
          if (!widget.readOnly)
            IconButton(
              onPressed: () => _remove(i),
              tooltip: context.l10nRead.delete,
              icon: const Icon(AppIcons.close, size: 13),
              color: scheme.onSurfaceVariant,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              style: IconButton.styleFrom(
                minimumSize: const Size(26, 26),
                maximumSize: const Size(26, 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Required" as a pill: the switch and the word are one tap target, and the
/// state reads without the colour.
class _RequiredChip extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _RequiredChip({required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: value ? scheme.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.pill,
        side: BorderSide(color: value ? Colors.transparent : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: KRadius.pill,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: KSpace.xs + 1, right: KSpace.m),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 30,
                height: 18,
                padding: const EdgeInsets.all(2),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: value ? scheme.primary : scheme.outlineVariant,
                  borderRadius: KRadius.pill,
                ),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: KSpace.s),
              Text(
                value ? s.formFieldRequired : s.formOptional,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: value ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The header switches (RSVP / after check-in), same pill language.
class _SettingChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingChip({required this.label, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: value ? scheme.primaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.pill,
        side: BorderSide(color: value ? Colors.transparent : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: KRadius.pill,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.s),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? AppIcons.check : AppIcons.create,
                size: 14,
                color: value ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: KSpace.s),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: value ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The counts across the top: what this form collects, at a glance.
class _SummaryChips extends StatelessWidget {
  final List<FormFieldSpec> specs;
  const _SummaryChips({required this.specs});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final tokens = KTokens.of(context);

    int count(String? analysis) =>
        specs.where((f) => f.analysis == analysis).length;

    final questions = specs.where((f) => f.isAnswerable).length;
    final required = specs.where((f) => f.required && f.isAnswerable).length;

    Widget chip(String label, {Color? dot}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.m - 2, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: KRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

    return Wrap(
      spacing: KSpace.xs + 2,
      runSpacing: KSpace.xs + 2,
      children: [
        chip('$questions ${s.formQuestionsShort}'),
        chip('${count('ki_pre')} ${s.formCountedBeforeShort}', dot: scheme.primary),
        chip('${count('ki_post')} ${s.formCountedAfterShort}', dot: scheme.tertiary),
        chip('${count('feedback')} ${s.formCountedFeedbackShort}', dot: tokens.feedback),
        chip('$required ${s.formFieldRequired.toLowerCase()}'),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (label, colour) = switch (status) {
      'open' => (s.formOpen, scheme.primary),
      'closed' => (s.formClosed, scheme.error),
      _ => (s.formDraft, scheme.tertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: KRadius.pill,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: colour,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ the rail

class _CoverageCard extends StatelessWidget {
  final List<FormFieldSpec> specs;
  const _CoverageCard({required this.specs});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final tokens = KTokens.of(context);

    final before = {
      for (final f in specs)
        if (f.analysis == 'ki_pre' && f.kiCode != null) f.kiCode!,
    };
    final after = {
      for (final f in specs)
        if (f.analysis == 'ki_post' && f.kiCode != null) f.kiCode!,
    };
    final pairs = [for (var i = 1; i <= 7; i++) if (before.contains(i) && after.contains(i)) i].length;

    Widget dot(bool on, Color colour) => Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: on ? colour : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: on ? colour : scheme.outlineVariant, width: 1.5),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                s.formElementLabel.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: scheme.onSurfaceVariant),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(s.formBefore.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: scheme.onSurfaceVariant)),
            ),
            SizedBox(
              width: 46,
              child: Text(s.formAfter.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        for (var i = 1; i <= 7; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('KI$i',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                ),
                SizedBox(width: 46, child: Center(child: dot(before.contains(i), scheme.primary))),
                SizedBox(width: 46, child: Center(child: dot(after.contains(i), scheme.tertiary))),
              ],
            ),
          ),
        const SizedBox(height: KSpace.s),
        Row(
          children: [
            Expanded(
              child: Text('S3 · ${s.formTagFeedback}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            Text('${specs.where((f) => f.analysis == 'feedback').length}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.feedback)),
          ],
        ),
        const SizedBox(height: KSpace.xs),
        Row(
          children: [
            Expanded(
              child: Text(s.formPairsLabel,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            Text('$pairs / 7',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pairs == 7 ? tokens.feedback : scheme.tertiary,
                )),
          ],
        ),
      ],
    );
  }
}

/// Every publish-time check, in one place: the rail, the narrow strip and the
/// publish dialog all read this.
List<(bool, String)> _formChecks(BuildContext context, List<FormFieldSpec> specs) {
  final s = context.l10n;

  final questions = specs.where((f) => f.isAnswerable).length;
  final missingLabels = specs.where((f) => f.label.trim().isEmpty).length;
  final dupes = specs.where((f) {
    if (f.analysis != 'ki_pre' && f.analysis != 'ki_post') return false;
    return specs
        .where((o) => o != f && o.analysis == f.analysis && o.kiCode == f.kiCode)
        .isNotEmpty;
  }).length;
  final before = {
    for (final f in specs)
      if (f.analysis == 'ki_pre') f.kiCode,
  };
  final orphan = [
    for (final f in specs)
      if (f.analysis == 'ki_post' && !before.contains(f.kiCode)) f.kiCode,
  ].whereType<int>().toSet().toList()
    ..sort();

  return [
    (
      missingLabels == 0,
      missingLabels == 0 ? s.formCheckLabels : s.formCheckMissingLabels(missingLabels),
    ),
    (dupes == 0, dupes == 0 ? s.formCheckDupes : s.formCheckDupesCount(dupes)),
    (orphan.isEmpty, orphan.isEmpty ? s.formCheckPairs : s.formCheckOrphan(orphan.join(', '))),
    (questions <= kMaxFormFields, s.formCheckBudget(questions)),
  ];
}

class _ChecksCard extends StatelessWidget {
  final List<FormFieldSpec> specs;
  final bool onlyFailing;

  const _ChecksCard({required this.specs, this.onlyFailing = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = KTokens.of(context);
    final checks = [
      for (final c in _formChecks(context, specs))
        if (!onlyFailing || !c.$1) c,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in checks)
          Padding(
            padding: const EdgeInsets.only(bottom: KSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: (c.$1 ? tokens.feedback : scheme.tertiary).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    c.$1 ? AppIcons.check : AppIcons.warning,
                    size: 10,
                    color: c.$1 ? tokens.feedback : scheme.tertiary,
                  ),
                ),
                const SizedBox(width: KSpace.s),
                Expanded(
                  child: Text(
                    c.$2,
                    style: TextStyle(fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// -------------------------------------------------------------------- pieces

/// The checks on a narrow window: one line when there is nothing to fix, the
/// failing checks only when there is. A full list above the questions on a
/// phone would push the form itself below the fold.
class _CompactChecks extends StatelessWidget {
  final List<FormFieldSpec> specs;
  const _CompactChecks({required this.specs});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final tokens = KTokens.of(context);
    final failing = _formChecks(context, specs).where((c) => !c.$1).toList();

    if (failing.isEmpty) {
      return Row(
        children: [
          Icon(AppIcons.check, size: 15, color: tokens.feedback),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: Text(s.formReadyToPublish,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      );
    }

    return _RailCard(
      title: s.formChecksTitle,
      child: _ChecksCard(specs: specs, onlyFailing: true),
    );
  }
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
      borderRadius: KRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: KRadius.card,
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

/// Dialog content width: 520 on a wide window, the window less its own insets
/// on a phone (AlertDialog does not shrink a fixed-width child).
double _dialogWidth(BuildContext context) {
  final available = MediaQuery.sizeOf(context).width - 96;
  if (available >= 520) return 520;
  return available < 200 ? 200 : available;
}

/// The rail's two cards, styled the same way.
class _RailCard extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget child;

  const _RailCard({required this.title, this.sub, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(KSpace.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: KRadius.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: KSpace.xs),
            Text(sub!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: KSpace.m),
          child,
        ],
      ),
    );
  }
}

/// A standalone form's safety card: the no-personal-data note, then every
/// question the server will refuse (password, OTP, PIN, card) and every one
/// asking for IC, bank or address details.
class _SafetyCard extends StatelessWidget {
  final List<FormFieldSpec> specs;
  const _SafetyCard({required this.specs});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final blocked = blockedFieldIndexes(specs);
    final sensitive = [
      for (final i in sensitiveFieldIndexes(specs))
        if (!blocked.contains(i)) i,
    ];

    Widget line(IconData icon, Color color, String text, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: KSpace.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: KSpace.s),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        );

    String label(int i) {
      final l = specs[i].label.trim();
      return '${i + 1}. ${l.isEmpty ? '…' : l}';
    }

    return Container(
      key: const ValueKey('form-safety'),
      padding: const EdgeInsets.all(KSpace.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: KRadius.card,
        border: Border.all(color: blocked.isEmpty ? scheme.outlineVariant : scheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.lock, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: KSpace.s),
              Expanded(child: Text(s.formPrivacyNote, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
          for (final i in blocked)
            line(AppIcons.error, scheme.error, '${label(i)} — ${s.formBlockedLabel}',
                key: ValueKey('blocked-$i')),
          for (final i in sensitive)
            line(AppIcons.warning, scheme.tertiary, '${label(i)} — ${s.formSensitiveLabel}',
                key: ValueKey('sensitive-$i')),
        ],
      ),
    );
  }
}
