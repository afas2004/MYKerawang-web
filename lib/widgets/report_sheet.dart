import 'package:flutter/material.dart';

import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import 'restriction_gate.dart';
import 'moderation_ui.dart';

typedef ReportSubmit = Future<ReportOutcome> Function({
  required String targetId,
  required String targetType,
  required String category,
  required String reason,
  String? note,
});

/// Report flow in one sheet: pick a category (each with a short
/// explanation), optionally add a note, send, and see the outcome in
/// place — received, already reported, your own content, gone, or
/// failed with Retry. A restricted reporter gets the restriction notice.
Future<void> showReportSheet(BuildContext context, String targetId, String type) async {
  final outcome = await showModalBottomSheet<ReportOutcome>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ReportSheet(targetId: targetId, targetType: type),
  );
  if (outcome?.result == ReportResult.restricted && context.mounted) {
    await showRestrictionNotice(context, outcome!.error?.restriction, scope: ModScope.account);
  }
}

class ReportSheet extends StatefulWidget {
  final String targetId;
  final String targetType;
  final ReportSubmit submit;

  const ReportSheet({
    super.key,
    required this.targetId,
    required this.targetType,
    this.submit = ModerationService.report,
  });

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  String? _category;
  final _note = TextEditingController();
  bool _sending = false;
  ReportOutcome? _outcome;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final c = _category;
    if (c == null) return;
    setState(() => _sending = true);
    final outcome = await widget.submit(
      targetId: widget.targetId,
      targetType: widget.targetType,
      category: c,
      reason: ModerationStrings.categoryReason(c),
      note: _note.text,
    );
    if (!mounted) return;
    if (outcome.result == ReportResult.restricted) {
      Navigator.pop(context, outcome);
      return;
    }
    setState(() {
      _sending = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _outcome == null ? _picker(context) : _result(context, _outcome!),
          ),
        ),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final m = context.l10n.mod;
    final u = m.ui;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('picker'),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(m.reportTitle, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(u.reportPickCategory,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          RadioGroup<String>(
            groupValue: _category,
            onChanged: (v) => setState(() => _category = v),
            child: Column(
              children: [
                for (final c in kReportCategories)
                  RadioListTile<String>(
                    value: c,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(m.categoryLabel(c)),
                    subtitle: Text(u.categoryDescription(c)),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _category == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: TextField(
                      controller: _note,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: u.reportNoteLabel,
                        hintText: u.reportNoteHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(
              children: [
                Icon(ModIcons.lock, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(u.reportPrivacy,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: FilledButton(
              onPressed: _category == null || _sending ? null : _send,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(u.reportSubmit),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, ReportOutcome o) {
    final m = context.l10n.mod;
    final u = m.ui;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String title, String body) = switch (o.result) {
      ReportResult.received => (ModIcons.success, scheme.primary, u.reportDoneTitle, m.reportReceived),
      ReportResult.duplicate => (ModIcons.info, scheme.primary, u.reportDupTitle, m.reportDuplicate),
      ReportResult.ownContent => (ModIcons.person, scheme.onSurfaceVariant, u.reportOwnTitle, m.reportOwn),
      ReportResult.missing => (ModIcons.searchOff, scheme.onSurfaceVariant, u.reportMissingTitle, m.reportMissing),
      _ => (ModIcons.offline, scheme.error, u.reportFailedTitle, m.reportFailed),
    };
    final failed = o.result == ReportResult.failed;
    return Padding(
      key: ValueKey(o.result),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            children: [
              if (failed) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _outcome = null),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(m.retry),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, o),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(u.done),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
