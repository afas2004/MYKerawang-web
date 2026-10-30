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
import '../../utils/form_csv.dart';
import '../../utils/responsive.dart';
import '../../utils/csv_saver.dart';
import '../../widgets/restriction_gate.dart';
import '../../widgets/app_toast.dart';

/// The three analyses the KI report asks for, plus the answers behind them.
///
/// This is the screen the club actually uses: the numbers get typed into the
/// Word report (so every table has a copy button) and the rows go out as CSV
/// for whoever processes them. Both come from the same server call, so they
/// cannot disagree.
class FormResponsesScreen extends StatefulWidget {
  /// The event whose form this is; null for a standalone form (`/f/:id/responses`).
  final String? eventId;
  final String? formId;

  const FormResponsesScreen({super.key, this.eventId, this.formId})
      : assert(eventId != null || formId != null);

  @override
  State<FormResponsesScreen> createState() => _FormResponsesScreenState();
}

class _FormResponsesScreenState extends State<FormResponsesScreen> {
  FormDoc? _doc;
  FormAnalysis? _analysis;
  List<FormResponse> _responses = const [];

  bool _loading = true;
  bool _noForm = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var id = widget.formId;
      if (id == null && widget.eventId != null) {
        final summary = await FormService.instance.summary(widget.eventId!);
        id = summary?.id;
      }
      if (id == null) {
        if (!mounted) return;
        setState(() {
          _noForm = true;
          _loading = false;
        });
        return;
      }

      final view = await FormService.instance.load(id);
      final analysis = await FormService.instance.analysis(id);
      final responses = await FormService.instance.responses(id);
      if (!mounted) return;
      setState(() {
        _doc = view.doc;
        _analysis = analysis;
        _responses = responses;
        _noForm = false;
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

  Future<void> _exportCsv() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      final csv = responsesCsv(doc.fields, _responses);
      await saveCsv(csv, _fileName(doc));
      if (!mounted) return;
      _toast(context.l10nRead.formCsvSaved);
    } catch (e) {
      if (!mounted) return;
      showErrorWithRetry(context, e, onRetry: _exportCsv);
    }
  }

  String _fileName(FormDoc doc) {
    final slug = doc.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final prefix = doc.standalone ? 'borang' : 'ki';
    return '$prefix-${slug.isEmpty ? 'borang' : slug}-$stamp.csv';
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(context.l10nRead.formCopied);
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(message);
  }

  /// Free-text answers, newest first — what goes in "Cadangan penambah baikan".
  List<(String, String)> _suggestions() {
    final doc = _doc;
    if (doc == null) return const [];
    final texts = doc.fields.where((f) => f.kind == 'long_text' && f.id != null).toList();
    final out = <(String, String)>[];
    for (final r in _responses) {
      for (final f in texts) {
        final v = r.answers[f.id];
        final text = (v ?? '').toString().trim();
        if (text.isNotEmpty && text != '-') out.add((r.displayName, text));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final doc = _doc;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: Responsive.detailMaxWidth,
        leading: const AppBackButton(),
        title: Text(s.formResponsesTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (doc != null)
            IconButton(
              tooltip: s.formExportCsv,
              icon: const Icon(AppIcons.download),
              onPressed: _responses.isEmpty ? null : _exportCsv,
            ),
          if (doc != null && doc.canEdit)
            IconButton(
              tooltip: s.formEditThis,
              icon: const Icon(AppIcons.edit),
              onPressed: () {
                // Opened from the editor? Return to it rather than pushing a
                // second editor on top — that stack grew one page per round
                // trip, and every page in it was a form with a guard.
                final from = GoRouterState.of(context).uri.queryParameters['from'];
                if (from == 'edit' && context.canPop()) {
                  context.pop();
                  return;
                }
                context.push(widget.eventId != null
                    ? '/event/${widget.eventId}/form/edit?f=${doc.id}'
                    : doc.editPath);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(error: _error!, onRetry: _open)
              : _noForm
                  ? _Notice(icon: AppIcons.info, text: s.formNotAvailable)
                  : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.l10n;
    final a = _analysis;
    final doc = _doc!;

    if (a == null || a.isEmpty) {
      return _Notice(icon: AppIcons.people, text: s.formNoResponses);
    }

    final suggestions = _suggestions();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.detailMaxWidth),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, KSpace.xxl),
          children: [
            Text(doc.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: KSpace.xs),
            Text(
              // "Peserta 2 · Penganjur 1" — the nouns are the domain words, so
              // there is no plural to get wrong. A standalone form has no
              // roles: just the count.
              doc.standalone
                  ? s.formsResponses(_responses.length)
                  : '${s.formPeserta} ${a.peserta} · ${s.formPenganjur} ${a.penganjur}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: KSpace.l),
            if (a.s1.isNotEmpty)
              _AnalysisCard(
                title: s.formS1Title,
                onCopy: () => _copy(s1Tsv(a.s1)),
                child: _S1Table(rows: a.s1),
              ),
            if (a.s2.isNotEmpty)
              _AnalysisCard(
                title: s.formS2Title,
                onCopy: () => _copy(s2Tsv(a.s2)),
                child: _S2Table(rows: a.s2),
              ),
            if (a.s3.isNotEmpty)
              _AnalysisCard(
                title: s.formS3Title,
                onCopy: () => _copy(s3Tsv(a.s3)),
                child: _S3Table(rows: a.s3),
              ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: KSpace.l),
              Text(s.formSuggestions, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: KSpace.s),
              for (final (who, text) in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: KSpace.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text),
                      Text(
                        who,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: KSpace.l),
            Text(s.formRespondents, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: KSpace.s),
            for (final r in _responses) _RespondentRow(response: r),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- pieces

/// `+0.25` / `-0.10`, or a dash when one side has no answers.
String _deltaText(double? d) =>
    d == null ? '—' : '${d > 0 ? '+' : ''}${d.toStringAsFixed(2)}';

class _AnalysisCard extends StatelessWidget {
  final String title;
  final VoidCallback onCopy;
  final Widget child;

  const _AnalysisCard({required this.title, required this.onCopy, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: KSpace.m),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.m, KSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: context.l10n.formCopyTable,
                  onPressed: onCopy,
                  icon: const Icon(AppIcons.copy, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// S1: one line per KI element, before and after, with the change.
class _S1Table extends StatelessWidget {
  final List<KiMean> rows;
  const _S1Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final meta = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 2),
          child: Row(
            children: [
              const Spacer(),
              SizedBox(width: 116, child: Text(s.formBefore, style: meta)),
              SizedBox(width: 116, child: Text(s.formAfter, style: meta)),
              SizedBox(width: 54, child: Text(s.formDelta, style: meta, textAlign: TextAlign.right)),
            ],
          ),
        ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'KI${r.kiCode} · ${_shortKi(r.label)}',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 116, child: _Bar(value: r.meanBefore, n: r.nBefore)),
                SizedBox(width: 116, child: _Bar(value: r.meanAfter, n: r.nAfter)),
                SizedBox(
                  width: 54,
                  child: Text(
                    _deltaText(r.delta),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: (r.delta ?? 0) > 0 ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// "Ki1 Kemahiran Berkomunikasi" → "Kemahiran Berkomunikasi".
  String _shortKi(String label) {
    final m = RegExp(r'^KI\s*\d+\s*[·:.\-–]?\s*', caseSensitive: false).firstMatch(label);
    return m == null ? label : label.substring(m.end);
  }
}

class _S2Table extends StatelessWidget {
  final List<KiMean> rows;
  const _S2Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'KI${r.kiCode} · ${_shortKi(r.label)}',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 130, child: _Bar(value: r.meanAfter, n: r.nAfter)),
              ],
            ),
          ),
      ],
    );
  }

  String _shortKi(String label) {
    final m = RegExp(r'^KI\s*\d+\s*[·:.\-–]?\s*', caseSensitive: false).firstMatch(label);
    return m == null ? label : label.substring(m.end);
  }
}

class _S3Table extends StatelessWidget {
  final List<FeedbackMean> rows;
  const _S3Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(r.label, style: const TextStyle(fontSize: 13)),
                ),
                SizedBox(width: 130, child: _Bar(value: r.mean, n: r.n)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A mean with its n, and a bar whose length is the mean over 5.
///
/// The n is not decoration: an average of two answers is not an average of
/// thirteen, and the report has to say which it is.
class _Bar extends StatelessWidget {
  final double? value;
  final int n;

  const _Bar({required this.value, required this.n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = ((value ?? 0) / 5).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value == null ? '—' : '${value!.toStringAsFixed(2)} ($n)',
            style: TextStyle(
              fontSize: 12,
              color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RespondentRow extends StatelessWidget {
  final FormResponse response;
  const _RespondentRow({required this.response});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = response.submittedAt?.toLocal();
    final stamp = when == null
        ? ''
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  response.displayName,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(stamp, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          Text(
            [
              if ((response.studentId ?? '').isNotEmpty) response.studentId!,
              response.role,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
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
