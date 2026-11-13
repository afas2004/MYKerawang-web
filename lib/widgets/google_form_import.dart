import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/form_strings.dart';
import '../l10n/gform_import_strings.dart';
import '../language_cubit.dart';
import '../services/feature_flags.dart';
import '../services/form_service.dart';
import '../services/google_form_import_service.dart';
import '../services/my_forms_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../utils/adaptive.dart';
import '../utils/feedback.dart';
import '../utils/form_rules.dart';
import '../utils/google_form_import.dart';
import '../utils/text_rules.dart';
import 'app_toast.dart';

/// "Import from Google Form": paste a link, see the questions and what could
/// not come across, name it, create. Returns the reviewed draft (with the
/// title as typed), or null when cancelled. Nothing is saved here; the caller
/// creates the form its own way (standalone, club, or an event's).
///
/// A dialog on wide screens, a tall bottom sheet on phones. [initialUrl]
/// (from a composer's hint) is read straight away.
///
/// [standalone]: the questions a student-made form may not ask are left out.
Future<GoogleFormDraft?> showGoogleFormImport(
  BuildContext context, {
  String? initialUrl,
  bool standalone = true,
}) {
  final body = GoogleFormImportBody(initialUrl: initialUrl, standalone: standalone);
  if (isWide(context)) {
    return showDialog<GoogleFormDraft>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<GoogleFormDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
      child: Padding(
        // Keeps the link field above the phone keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: body,
      ),
    ),
  );
}

/// The import, then a personal draft form made from it. For places that need
/// a form back rather than an editor (the form picker, the composers' hint).
/// Returns the new form, or null when cancelled or when creating failed (the
/// failure is shown).
Future<MyForm?> importGoogleFormAsStandalone(BuildContext context, {String? initialUrl}) async {
  final draft = await showGoogleFormImport(context, initialUrl: initialUrl);
  if (draft == null || !context.mounted) return null;
  final s = context.l10nRead;
  final malay = identical(s, AppStrings.ms);
  try {
    final id = await MyFormsService.instance.create(
      title: draft.title.isEmpty ? null : draft.title,
      lang: malay ? 'ms' : 'en',
    );
    final view = await FormService.instance.load(id);
    await FormService.instance.save(
      view.doc.copyWith(fields: draft.fields, intro: draft.description),
    );
    return MyForm(id: id, title: view.doc.title, status: 'draft');
  } catch (e) {
    if (context.mounted) {
      showErrorWithRetry(context, e, message: s.formServerError(formErrorCode(e)));
    }
    return null;
  }
}

/// Reads the JSON the server returned (it may arrive as a decoded list, or
/// as text) and parses it.
GoogleFormDraft draftFromFetch(Object? data, {required bool standalone}) {
  final decoded = data is String ? jsonDecode(data) : data;
  return parseGoogleForm(
    decoded,
    studentIds: FeatureFlags.studentFeaturesOn,
    standalone: standalone,
  );
}

class GoogleFormImportBody extends StatefulWidget {
  final String? initialUrl;
  final bool standalone;
  const GoogleFormImportBody({super.key, this.initialUrl, this.standalone = true});

  @override
  State<GoogleFormImportBody> createState() => _GoogleFormImportBodyState();
}

class _GoogleFormImportBodyState extends State<GoogleFormImportBody> {
  late final _link = TextEditingController(text: widget.initialUrl ?? '');
  final _title = TextEditingController();
  bool _loading = false;
  String? _error;
  GoogleFormDraft? _draft;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    if (normaliseGoogleFormUrl(_link.text) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final s = context.l10nRead;
    final url = normaliseGoogleFormUrl(_link.text);
    if (url == null) {
      setState(() => _error = s.gfBadLink);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    GoogleFormDraft? draft;
    try {
      final got = await GoogleFormImportService.instance.fetch(url);
      if (!got.ok) {
        error = s.gfFailed(got.reason);
      } else {
        draft = draftFromFetch(got.data, standalone: widget.standalone);
      }
    } on GoogleFormParseException {
      error = s.gfFailed('no_data');
    } on FormatException {
      error = s.gfFailed('no_data');
    } catch (e) {
      debugPrint('Google Form import failed: $e');
      error = s.gfFailed(null);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      _draft = draft;
      if (draft != null) _title.text = draft.title;
    });
  }

  void _reset() => setState(() {
        _draft = null;
        _error = null;
      });

  void _create() {
    final d = _draft!;
    Navigator.pop(
      context,
      GoogleFormDraft(
        title: cleanLine(_title.text),
        description: d.description,
        untitled: d.untitled,
        fields: d.fields,
        notes: d.notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final draft = _draft;
    final canCreate = draft != null &&
        draft.questionCount > 0 &&
        _title.text.trim().isNotEmpty &&
        !_loading;

    return Column(
      key: const ValueKey('gf-import'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.gfImport, style: theme.textTheme.titleLarge),
                const SizedBox(height: KSpace.xs),
                Text(s.gfImportSub,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: KSpace.m),
                if (draft == null) ...[
                  TextField(
                    key: const ValueKey('gf-link'),
                    controller: _link,
                    enabled: !_loading,
                    autofocus: widget.initialUrl == null,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _fetch(),
                    decoration: InputDecoration(
                      labelText: s.gfLinkLabel,
                      hintText: s.gfLinkHint,
                      prefixIcon: const Icon(AppIcons.link, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: KSpace.m),
                    Row(
                      children: [
                        const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: KSpace.s),
                        Text(s.gfFetching, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ] else ...[
                  TextField(
                    key: const ValueKey('gf-title'),
                    controller: _title,
                    maxLength: kFormTitleMax,
                    autofocus: draft.untitled,
                    decoration: InputDecoration(
                      labelText: s.formsTitleLabel,
                      helperText: draft.untitled ? s.gfTitleHint : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (draft.description != null) ...[
                    const SizedBox(height: KSpace.xs),
                    Text(s.gfIntro, style: theme.textTheme.labelMedium),
                    Text(
                      draft.description!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: KSpace.m),
                  GoogleFormPreview(draft: draft),
                ],
                if (_error != null) ...[
                  const SizedBox(height: KSpace.m),
                  _Message(key: const ValueKey('gf-error'), text: _error!, error: true),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.l),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: KSpace.s,
            overflowSpacing: KSpace.s,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
              if (draft != null)
                TextButton(
                  key: const ValueKey('gf-again'),
                  onPressed: _reset,
                  child: Text(s.gfTryAnother),
                ),
              if (draft == null)
                FilledButton(
                  key: const ValueKey('gf-fetch'),
                  onPressed: _loading ? null : _fetch,
                  child: Text(s.gfFetch),
                )
              else
                FilledButton(
                  key: const ValueKey('gf-create'),
                  onPressed: canCreate ? _create : null,
                  child: Text(s.gfCreate),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The questions a draft will create, then what was left out or changed.
class GoogleFormPreview extends StatelessWidget {
  final GoogleFormDraft draft;
  const GoogleFormPreview({super.key, required this.draft});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final skipped = draft.skipped;
    final changed = draft.changed;
    var n = 0;
    return Column(
      key: const ValueKey('gf-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.gfQuestions(draft.questionCount), style: theme.textTheme.titleSmall),
        const SizedBox(height: KSpace.s),
        if (draft.questionCount == 0) _Message(text: s.gfEmpty, error: true),
        for (final f in draft.fields)
          if (f.kind == 'heading')
            Padding(
              padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.label,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (f.help != null)
                    Text(f.help!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            )
          else
            _QuestionLine(number: ++n, field: f),
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: KSpace.m),
          _NoteBox(
            key: const ValueKey('gf-skipped'),
            title: s.gfSkippedTitle,
            icon: AppIcons.warning,
            color: scheme.error,
            notes: skipped,
          ),
        ],
        if (changed.isNotEmpty) ...[
          const SizedBox(height: KSpace.m),
          _NoteBox(
            key: const ValueKey('gf-changed'),
            title: s.gfChangedTitle,
            icon: AppIcons.info,
            color: scheme.primary,
            notes: changed,
          ),
        ],
        const SizedBox(height: KSpace.m),
        Text(s.gfDraftNote,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _QuestionLine extends StatelessWidget {
  final int number;
  final FormFieldSpec field;
  const _QuestionLine({required this.number, required this.field});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = field.isRating
        ? '${s.formKindLabel('rating').split(' ').first} ${field.min}–${field.max}'
        : s.formKindLabel(field.kind);
    final choices = field.choices;
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text('$number.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label + (field.required ? ' *' : ''),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [
                    kind,
                    if (field.isChoice)
                      choices.take(4).join(' · ') + (choices.length > 4 ? ' …' : ''),
                  ].join(' — '),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<GoogleFormNote> notes;
  const _NoteBox({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(KSpace.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: KSpace.s),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: KSpace.xs),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: KSpace.xs),
              child: Text.rich(
                TextSpan(children: [
                  if (n.label.isNotEmpty)
                    TextSpan(
                        text: '${n.label}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: s.gfNote(n.code)),
                ]),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final bool error;
  const _Message({super.key, required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(error ? AppIcons.warning : AppIcons.info,
            size: 18, color: error ? scheme.error : scheme.primary),
        const SizedBox(width: KSpace.s),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

// ------------------------------------------------------------ composer hint

/// A small card under a composer's text when it holds a Google Form link:
/// "Turn this Google Form into a MYKerawang form?". Import opens the import
/// with that link filled in; [onImported] gets the new draft form so the
/// composer can attach it. Hidden after "Not now" (for that link).
///
/// [sources] are the fields to watch (the body, the button URLs).
class GoogleFormSuggestion extends StatefulWidget {
  final List<TextEditingController> sources;
  final void Function(MyForm form) onImported;
  const GoogleFormSuggestion({super.key, required this.sources, required this.onImported});

  @override
  State<GoogleFormSuggestion> createState() => _GoogleFormSuggestionState();
}

class _GoogleFormSuggestionState extends State<GoogleFormSuggestion> {
  final Set<String> _dismissed = {};
  bool _busy = false;

  String? _url() {
    for (final c in widget.sources) {
      final u = findGoogleFormUrl(c.text);
      if (u != null && !_dismissed.contains(u)) return u;
    }
    return null;
  }

  Future<void> _import(String url) async {
    setState(() => _busy = true);
    final form = await importGoogleFormAsStandalone(context, initialUrl: url);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (form != null) _dismissed.add(url);
    });
    if (form != null) {
      widget.onImported(form);
      showToast(context.l10nRead.gfCreatedDraft);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(widget.sources),
      builder: (context, _) {
        final url = _url();
        if (url == null) return const SizedBox.shrink();
        final s = context.l10n;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Container(
          key: const ValueKey('gf-suggest'),
          margin: const EdgeInsets.symmetric(vertical: KSpace.s),
          padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.s, KSpace.s),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(AppIcons.sparkle, size: 18, color: scheme.primary),
              const SizedBox(width: KSpace.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.gfSuggest,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(s.gfSuggestSub,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('gf-suggest-import'),
                onPressed: _busy ? null : () => _import(url),
                child: Text(s.gfSuggestAction),
              ),
              IconButton(
                tooltip: s.gfSuggestDismiss,
                icon: const Icon(AppIcons.close, size: 18),
                onPressed: () => setState(() => _dismissed.add(url)),
              ),
            ],
          ),
        );
      },
    );
  }
}
