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
import '../../utils/responsive.dart';
import '../../widgets/restriction_gate.dart';

/// Filling in an event's form — the KI report survey, in practice.
///
/// The page is open to guests (they see the questions and a sign-in bar); the
/// server decides whether an answer is accepted. `form_public()` already
/// carries the caller's own answer, so re-opening shows what they said.
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

  FormView? _view;
  bool _loading = true;
  bool _sending = false;
  bool _noForm = false;
  Set<String> _missing = const {};
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
        _loading = false;
        _missing = const {};
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

  Future<void> _submit() async {
    final doc = _doc;
    final view = _view;
    if (doc == null || view == null || _sending) return;

    final missing = missingRequired(doc.fields, _answers);
    if (missing.isNotEmpty) {
      setState(() => _missing = missing.toSet());
      _toast(context.l10nRead.formAnswerRequired);
      return;
    }

    setState(() {
      _sending = true;
      _missing = const {};
    });
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
      });
      notifyContentChanged();
      _toast(context.l10nRead.formAnswerThanks);
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
        maxWidth: Responsive.detailMaxWidth,
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
    final s = context.l10n;
    final doc = view.doc;
    final scheme = Theme.of(context).colorScheme;

    if (!view.canAnswer) {
      return _Blocked(reason: view.reason);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
        child: Column(
          children: [
            if (view.answered)
              _Banner(text: s.formAnswerAlready, icon: AppIcons.check),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, KSpace.xxl),
                children: [
                  if ((doc.intro ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: KSpace.m),
                      child: Text(
                        doc.intro!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  for (final f in doc.fields)
                    _FieldInput(
                      field: f,
                      value: f.id == null ? null : _answers[f.id],
                      controller: f.id == null ? null : _textController(f),
                      missing: f.id != null && _missing.contains(f.id),
                      enabled: !_sending,
                      onChanged: (v) {
                        if (f.id != null) _answers[f.id!] = v;
                        if (_missing.contains(f.id)) {
                          setState(() => _missing = {..._missing}..remove(f.id));
                        }
                      },
                      onText: (v) {
                        if (f.id != null) _answers[f.id!] = v;
                      },
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.m),
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(view.answered ? s.formAnswerUpdate : s.formAnswerSend),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- pieces

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

/// One question, rendered by kind. Keeps the state in the parent so a submit
/// can read it all at once.
class _FieldInput extends StatelessWidget {
  final FormFieldSpec field;
  final dynamic value;
  final TextEditingController? controller;
  final bool missing;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;
  final ValueChanged<String> onText;

  const _FieldInput({
    required this.field,
    required this.value,
    required this.controller,
    required this.missing,
    required this.enabled,
    required this.onChanged,
    required this.onText,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final label = field.label + (field.required && field.kind != 'heading' ? ' *' : '');

    if (field.kind == 'heading') {
      return Padding(
        padding: const EdgeInsets.only(top: KSpace.l, bottom: KSpace.s),
        child: Text(
          field.label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }

    final error = missing ? s.formAnswerRequired : null;

    switch (field.kind) {
      case 'long_text':
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: TextField(
            key: ValueKey('input-${field.id}'),
            controller: controller,
            enabled: enabled,
            minLines: 3,
            maxLines: 6,
            onChanged: onText,
            decoration: InputDecoration(labelText: label, helperText: field.help, errorText: error),
          ),
        );

      case 'rating':
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              if ((field.help ?? '').isNotEmpty)
                Text(
                  field.help!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: KSpace.xs),
              Wrap(
                spacing: KSpace.s,
                children: [
                  for (var v = field.min; v <= field.max; v++)
                    ChoiceChip(
                      key: ValueKey('rate-${field.id}-$v'),
                      label: Text('$v'),
                      selected: value == v,
                      onSelected: enabled ? (_) => onChanged(v) : null,
                    ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: KSpace.xs),
                  child: Text(error, style: TextStyle(color: scheme.error, fontSize: 12)),
                ),
            ],
          ),
        );

      case 'single_choice':
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              RadioGroup<String>(
                groupValue: value is String ? value as String : null,
                onChanged: (v) {
                  if (enabled) onChanged(v);
                },
                child: Column(
                  children: [
                    for (final choice in field.choices)
                      RadioListTile<String>(
                        key: ValueKey('choice-${field.id}-$choice'),
                        value: choice,
                        title: Text(choice),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              if (error != null)
                Text(error, style: TextStyle(color: scheme.error, fontSize: 12)),
            ],
          ),
        );

      case 'multi_choice':
        final picked = value is List ? List<String>.from(value as List) : <String>[];
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              for (final choice in field.choices)
                CheckboxListTile(
                  value: picked.contains(choice),
                  onChanged: enabled
                      ? (on) {
                          final next = List<String>.from(picked);
                          if (on == true) {
                            next.add(choice);
                          } else {
                            next.remove(choice);
                          }
                          onChanged(next);
                        }
                      : null,
                  title: Text(choice),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              if (error != null)
                Text(error, style: TextStyle(color: scheme.error, fontSize: 12)),
            ],
          ),
        );

      case 'consent':
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: value == true,
                onChanged: enabled ? (on) => onChanged(on == true) : null,
                title: Text(label),
                subtitle: (field.help ?? '').isEmpty ? null : Text(field.help!),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (error != null)
                Text(error, style: TextStyle(color: scheme.error, fontSize: 12)),
            ],
          ),
        );

      case 'date':
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: InkWell(
            onTap: enabled ? () => _pickDate(context) : null,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                helperText: field.help,
                errorText: error,
                suffixIcon: const Icon(AppIcons.calendar, size: 18),
              ),
              child: Text(
                (value as String?)?.isNotEmpty == true ? value as String : '—',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        );

      default:
        // short_text, number, email, phone, student_id
        final keyboard = switch (field.kind) {
          'number' || 'phone' || 'student_id' => TextInputType.number,
          'email' => TextInputType.emailAddress,
          _ => TextInputType.text,
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: KSpace.m),
          child: TextField(
            key: ValueKey('input-${field.id}'),
            controller: controller,
            enabled: enabled,
            keyboardType: keyboard,
            inputFormatters: field.kind == 'student_id'
                ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)]
                : null,
            onChanged: onText,
            decoration: InputDecoration(labelText: label, helperText: field.help, errorText: error),
          ),
        );
    }
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
    if (picked != null) {
      onChanged(picked.toIso8601String().substring(0, 10));
    }
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
