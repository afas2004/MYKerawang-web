import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/form_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../utils/adaptive.dart';
import '../../utils/app_nav.dart';
import '../../utils/feedback.dart';
import '../../utils/form_rules.dart';
import '../../utils/guest_access.dart';
import '../../widgets/form_style.dart';
import '../../widgets/restriction_gate.dart';

/// Filling in an event's form — the KI report survey, in practice.
///
/// The page is open to guests (they see the questions and a sign-in bar); the
/// server decides whether an answer is accepted. `form_public()` already
/// carries the caller's own answer, so re-opening shows what they said.
///
/// Layout: the form's own sections are the cards, tinted the same way the
/// editor tints them (purple before, gold after, teal feedback), so what the
/// organiser arranged is what the student sees. A rating is five equal
/// segments rather than a row of chips, and the progress and the submit button
/// stay together at the bottom.
class EventFormScreen extends StatefulWidget {
  final String eventId;

  /// Open this form directly; null means "the event's open form, if any".
  final String? formId;

  const EventFormScreen({super.key, required this.eventId, this.formId});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _texts = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, GlobalKey> _keys = {};

  /// Fields the user has left (or completed), and what is wrong with them.
  /// Nothing is reported until a field has been touched — the form guidance is
  /// explicit that errors on a pristine field punish the user for arriving.
  final Set<String> _touched = {};
  final Map<String, String> _errors = {};

  FormView? _view;
  bool _loading = true;
  bool _sending = false;
  bool _justSent = false;
  bool _noForm = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  FormDoc? get _doc => _view?.doc;

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var id = widget.formId;
      id ??= await FormService.instance.openFormId(widget.eventId);
      if (id == null) {
        if (!mounted) return;
        setState(() {
          _noForm = true;
          _loading = false;
        });
        return;
      }

      final view = await FormService.instance.load(id);
      final email = view.answered ? null : await FormService.instance.myEmail();
      if (!mounted) return;

      _answers
        ..clear()
        ..addAll(_initialAnswers(view, email));
      setState(() {
        _view = view;
        _noForm = false;
        _justSent = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// What to start from: an existing answer, or a sensible pre-fill for the
  /// identity questions (the matric can come from a student address).
  Map<String, dynamic> _initialAnswers(FormView view, String? email) {
    final mine = view.mine?['answers'];
    if (mine is Map) {
      return Map<String, dynamic>.from(mine);
    }
    final out = <String, dynamic>{};
    final matric = (email != null && email.toLowerCase().endsWith('@student.uitm.edu.my'))
        ? email.split('@').first
        : null;
    for (final f in view.doc.fields) {
      if (f.id == null) continue;
      if (f.kind == 'student_id' && matric != null) out[f.id!] = matric;
    }
    return out;
  }

  TextEditingController _textController(FormFieldSpec f) =>
      _texts.putIfAbsent(f.id!, () {
        final v = _answers[f.id];
        return TextEditingController(text: v?.toString() ?? '');
      });

  /// One focus node per text field: leaving a field is when it is validated.
  FocusNode _focusFor(FormFieldSpec f) => _focusNodes.putIfAbsent(f.id!, () {
        final node = FocusNode();
        node.addListener(() {
          if (!node.hasFocus) _touch(f);
        });
        return node;
      });

  GlobalKey _keyFor(FormFieldSpec f) =>
      _keys.putIfAbsent(f.id!, () => GlobalKey());

  /// Report this field's problem, if any. Called on blur, on change once the
  /// field already has an error, and on submit.
  void _check(FormFieldSpec f) {
    final id = f.id;
    if (id == null) return;
    _touched.add(id);
    final issue = validateAnswer(f, _answers[id]);
    setState(() {
      if (issue == null) {
        _errors.remove(id);
      } else {
        _errors[id] = issue;
      }
    });
  }

  void _touch(FormFieldSpec f) {
    if (f.id == null) return;
    _touched.add(f.id!);
    _check(f);
  }

  bool _showsError(FormFieldSpec f) =>
      f.id != null && _touched.contains(f.id) && _errors.containsKey(f.id);

  /// True once a required field has been answered acceptably — positive
  /// feedback, not just the absence of red.
  bool _showsDone(FormFieldSpec f) =>
      f.id != null &&
      _touched.contains(f.id) &&
      f.required &&
      !_errors.containsKey(f.id) &&
      !answerIsEmpty(_answers[f.id]);

  Future<void> _submit() async {
    final doc = _doc;
    final view = _view;
    if (doc == null || view == null || _sending) return;

    final invalid = invalidAnswers(doc.fields, _answers);
    if (invalid.isNotEmpty) {
      setState(() {
        // Submitting is a request to see everything that is missing.
        for (final f in doc.fields) {
          if (f.id != null) _touched.add(f.id!);
        }
        for (final id in invalid) {
          final field = doc.fields.firstWhere((f) => f.id == id);
          _errors[id] = validateAnswer(field, _answers[id])!;
        }
      });

      // Take the user to the first one rather than leaving them to hunt.
      final ctx = _keys[invalid.first]?.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
      if (!mounted) return;
      _toast(context.l10nRead.formAnswerMissing(invalid.length));
      return;
    }

    setState(() => _sending = true);
    try {
      await FormService.instance.submit(
        doc.id,
        answers: {
          for (final f in doc.fields)
            if (f.id != null && _answers[f.id] != null) f.id!: _answers[f.id],
        },
        role: roleForAnswers(doc.fields, _answers),
      );
      final fresh = await FormService.instance.load(doc.id);
      if (!mounted) return;
      setState(() {
        _view = fresh;
        _sending = false;
        _justSent = true;
      });
      notifyContentChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showErrorWithRetry(context, e, onRetry: _submit);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final view = _view;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: 760,
        title: Text(
          view?.doc.title ?? s.formAnswerTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (view != null && view.doc.canEdit)
            IconButton(
              tooltip: s.formEditThis,
              icon: const Icon(AppIcons.edit),
              onPressed: () => context.push('/event/${widget.eventId}/form/edit'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(error: _error!, onRetry: _open)
              : _noForm
                  ? _Notice(icon: AppIcons.info, text: s.formNotAvailable)
                  : _form(context, view!),
    );
  }

  Widget _form(BuildContext context, FormView view) {
    final doc = view.doc;
    if (!view.canAnswer) return _Blocked(reason: view.reason);

    final (done, total) = answerProgress(doc.fields, _answers);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            if (view.answered)
              _Banner(text: context.l10n.formAnswerAlready, icon: AppIcons.check),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.xl),
                children: [
                  _head(context, doc, done, total),
                  if (_justSent)
                    _SuccessCard(onEdit: () => setState(() => _justSent = false))
                  else
                    for (final section in _sections(doc.fields)) _sectionCard(context, section),
                ],
              ),
            ),
            if (!_justSent) _bottomBar(context, doc, done, total),
          ],
        ),
      ),
    );
  }

  Widget _head(BuildContext context, FormDoc doc, int done, int total) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final intro = (doc.intro ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.xs, 0, KSpace.xs, KSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doc.title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
          ),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: KSpace.xs),
            Text(
              intro,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: KSpace.l),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: KRadius.pill,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: total == 0 ? 0 : done / total),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KSpace.m),
              Text(
                s.formAnswerProgress(done, total),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, FormDoc doc, int done, int total) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final missing = missingRequired(doc.fields, _answers).length;
    final answered = _view?.answered ?? false;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final info = Text(
              missing == 0 ? s.formAllAnswered : s.formRequiredLeft(missing),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            );
            final button = FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: _sending
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(answered ? s.formAnswerUpdate : s.formAnswerSend),
            );

            // Phones get the button full width under the count, so a long
            // label ("Update answers") cannot squeeze the button.
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  info,
                  const SizedBox(height: KSpace.s),
                  button,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: KSpace.m),
                button,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, _Section section) {
    final scheme = Theme.of(context).colorScheme;
    final style = AnalysisStyle.of(context, _laneAnalysis(section));
    final head = section.head;

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.l),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: KRadius.card,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (head != null)
              Container(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
                decoration: BoxDecoration(
                  color: style.soft,
                  border: Border(left: BorderSide(color: style.accent, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      head.label,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if ((head.help ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(head.help!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            for (var i = 0; i < section.fields.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
              _answerFor(context, section.fields[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// The analysis tag of the section: its first tagged question.
  String? _laneAnalysis(_Section section) {
    for (final f in section.fields) {
      if (f.analysis != null) return f.analysis;
    }
    return null;
  }

  Widget _answerFor(BuildContext context, FormFieldSpec field) {
    final s = context.l10n;
    return Container(
      key: field.id == null ? null : _keyFor(field),
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m + 2, KSpace.l, KSpace.m + 2),
      child: _AnswerField(
        field: field,
        value: field.id == null ? null : _answers[field.id],
        controller: field.id == null ? null : _textController(field),
        focusNode: field.id == null ? null : _focusFor(field),
        errorText: _showsError(field) ? s.formAnswerIssueText(_errors[field.id] ?? '') : null,
        done: _showsDone(field),
        enabled: !_sending,
        onChanged: (v) {
          if (field.id == null) return;
          _answers[field.id!] = v;
          // Discrete answers are complete the moment they are tapped, so they
          // are checked there; a text field is not, and waits for blur.
          if (field.kind != 'short_text' &&
              field.kind != 'long_text' &&
              field.kind != 'number' &&
              field.kind != 'email' &&
              field.kind != 'phone' &&
              field.kind != 'student_id') {
            _check(field);
          } else if (_errors.containsKey(field.id)) {
            _check(field);
          } else {
            setState(() {});
          }
        },
        onText: (v) {
          if (field.id == null) return;
          _answers[field.id!] = v;
          // Hybrid timing: once a field has an error, it clears as soon as the
          // input becomes valid.
          if (_errors.containsKey(field.id)) _check(field);
        },
      ),
    );
  }
}

// --------------------------------------------------------------------- pieces

/// A card's worth of questions: the heading field and the questions under it.
class _Section {
  final FormFieldSpec? head;
  final List<FormFieldSpec> fields;
  const _Section(this.head, this.fields);
}

List<_Section> _sections(List<FormFieldSpec> fields) {
  final out = <_Section>[];
  FormFieldSpec? head;
  var items = <FormFieldSpec>[];
  for (final f in fields) {
    if (f.kind == 'heading') {
      if (head != null || items.isNotEmpty) out.add(_Section(head, items));
      head = f;
      items = [];
    } else {
      items.add(f);
    }
  }
  if (head != null || items.isNotEmpty) out.add(_Section(head, items));
  return out;
}

/// One question, rendered by kind. Keeps the state in the parent so a submit
/// can read it all at once.
class _AnswerField extends StatelessWidget {
  final FormFieldSpec field;
  final dynamic value;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Shown under the field once it has been touched; null while pristine.
  final String? errorText;

  /// A required field that is answered — a tick, not just an absent error.
  final bool done;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;
  final ValueChanged<String> onText;

  const _AnswerField({
    required this.field,
    required this.value,
    required this.controller,
    this.focusNode,
    this.errorText,
    this.done = false,
    required this.enabled,
    required this.onChanged,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final label = field.required && field.kind != 'heading'
        ? '${field.label} *'
        : field.label;
    final error = errorText;

    // The label is a label, not a placeholder: it stays above the control.
    final header = Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (done)
            Icon(AppIcons.check, size: 17, color: scheme.primary),
        ],
      ),
    );

    final help = (field.help ?? '').isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(bottom: KSpace.s),
            child: Text(field.help!, style: Theme.of(context).textTheme.bodySmall),
          )
        : const SizedBox.shrink();

    final problem = error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: KSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, size: 13, color: scheme.error),
                const SizedBox(width: KSpace.xs),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.error),
                  ),
                ),
              ],
            ),
          );

    Widget body;
    switch (field.kind) {
      case 'rating':
        body = _Scale(
          field: field,
          value: value,
          enabled: enabled,
          onChanged: onChanged,
        );

      case 'single_choice':
        body = Wrap(
          spacing: KSpace.s,
          runSpacing: KSpace.s,
          children: [
            for (final choice in field.choices)
              _ChoicePill(
                key: ValueKey('choice-${field.id}-$choice'),
                label: choice,
                selected: value == choice,
                enabled: enabled,
                onTap: () => onChanged(choice),
              ),
          ],
        );

      case 'multi_choice':
        final picked = value is List ? List<String>.from(value as List) : <String>[];
        body = Wrap(
          spacing: KSpace.s,
          runSpacing: KSpace.s,
          children: [
            for (final choice in field.choices)
              _ChoicePill(
                key: ValueKey('choice-${field.id}-$choice'),
                label: choice,
                selected: picked.contains(choice),
                enabled: enabled,
                onTap: () {
                  final next = List<String>.from(picked);
                  if (next.contains(choice)) {
                    next.remove(choice);
                  } else {
                    next.add(choice);
                  }
                  onChanged(next);
                },
              ),
          ],
        );

      case 'consent':
        body = _ChoicePill(
          key: ValueKey('consent-${field.id}'),
          label: s.formAgree,
          selected: value == true,
          enabled: enabled,
          onTap: () => onChanged(value != true),
        );

      case 'long_text':
        body = TextField(
          key: ValueKey('input-${field.id}'),
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          minLines: 4,
          maxLines: 8,
          onChanged: onText,
          decoration: _decoration(context, error, hintText: ''),
        );

      case 'date':
        body = InkWell(
          onTap: enabled ? () => _pickDate(context) : null,
          borderRadius: KRadius.input,
          child: InputDecorator(
            decoration: _decoration(context, error).copyWith(
              suffixIcon: const Icon(AppIcons.calendar, size: 18),
            ),
            child: Text(
              (value as String?)?.isNotEmpty == true ? value as String : '—',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );

      default:
        final keyboard = switch (field.kind) {
          'number' || 'phone' || 'student_id' => TextInputType.number,
          'email' => TextInputType.emailAddress,
          _ => TextInputType.text,
        };
        body = TextField(
          key: ValueKey('input-${field.id}'),
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: keyboard,
          inputFormatters: field.kind == 'student_id'
              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)]
              : null,
          onChanged: onText,
          decoration: _decoration(context, error, hintText: field.kind == 'email' ? 'name@example.com' : ''),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [header, help, body, problem],
    );
  }

  InputDecoration _decoration(BuildContext context, String? error, {String? hintText}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      isDense: true,
      hintText: (hintText ?? '').isEmpty ? null : hintText,
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.m),
      enabledBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: error == null ? scheme.outlineVariant : scheme.error),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final current = DateTime.tryParse((value as String?) ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) onChanged(picked.toIso8601String().substring(0, 10));
  }
}

/// Five equal segments instead of five chips: one tap, no ambiguity about
/// which number was chosen, and the same size on every row.
class _Scale extends StatelessWidget {
  final FormFieldSpec field;
  final dynamic value;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;

  const _Scale({
    required this.field,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numbers = [for (var n = field.min; n <= field.max; n++) n];

    return Row(
      children: [
        for (var i = 0; i < numbers.length; i++) ...[
          if (i > 0) const SizedBox(width: KSpace.xs + 2),
          Expanded(
            child: _ScaleButton(
              key: ValueKey('rate-${field.id}-${numbers[i]}'),
              value: numbers[i],
              selected: value == numbers[i],
              enabled: enabled,
              primary: scheme.primary,
              onPrimary: scheme.onPrimary,
              outline: scheme.outlineVariant,
              surface: scheme.surfaceContainerLowest,
              muted: scheme.onSurfaceVariant,
              onTap: () => onChanged(numbers[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScaleButton extends StatelessWidget {
  final int value;
  final bool selected;
  final bool enabled;
  final Color primary;
  final Color onPrimary;
  final Color outline;
  final Color surface;
  final Color muted;
  final VoidCallback onTap;

  const _ScaleButton({
    super.key,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.primary,
    required this.onPrimary,
    required this.outline,
    required this.surface,
    required this.muted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$value',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: KRadius.small,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? primary : surface,
            borderRadius: KRadius.small,
            border: Border.all(color: selected ? primary : outline),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: selected ? onPrimary : muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice as a pill, with a radio dot that reads at a glance.
class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Colors.transparent : scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.m + 3, vertical: KSpace.s + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 4.5 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: KSpace.s),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The end state: what happened, in one sentence, and a way back in.
class _SuccessCard extends StatelessWidget {
  final VoidCallback onEdit;
  const _SuccessCard({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.symmetric(vertical: KSpace.xl),
        padding: const EdgeInsets.all(KSpace.xl),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: KRadius.card,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(AppIcons.check, size: 26, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: KSpace.m),
            Text(
              s.formAnswerSentTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: KSpace.xs),
            Text(
              s.formAnswerSentBody,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: KSpace.l),
            OutlinedButton(onPressed: onEdit, child: Text(s.formEditAnswers)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Banner({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: KSpace.l, vertical: KSpace.s),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the form cannot be answered right now.
class _Blocked extends StatelessWidget {
  final String? reason;
  const _Blocked({required this.reason});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    switch (reason) {
      case 'signed_out':
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(KSpace.xl),
            child: GuestActionBar(label: s.formAnswerSignIn),
          ),
        );
      case 'not_joined':
        return _Notice(icon: AppIcons.people, text: s.formAnswerJoinFirst);
      case 'full':
        return _Notice(icon: AppIcons.warning, text: s.formAnswerFull);
      default:
        return _Notice(icon: AppIcons.lock, text: s.formAnswerClosed);
    }
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: scheme.onSurfaceVariant),
            const SizedBox(height: KSpace.m),
            Text(text, textAlign: TextAlign.center),
          ],
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
