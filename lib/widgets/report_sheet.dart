import 'package:flutter/material.dart';

import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import 'moderation_ui.dart';
import 'restriction_gate.dart';

/// Report flow: pick a category, get an immediate answer.
///   received   → "Report received…"
///   duplicate  → "You've already reported this…"
///   own        → "You can't report your own content."
///   missing    → "This is no longer available."
///   restricted → the restriction notice (what, why, until)
///   failed     → error with Retry
Future<void> showReportSheet(BuildContext context, String targetId, String type) async {
  final m = context.l10nRead.mod;
  final category = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(m.reportTitle, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(m.reportWhy,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            for (final c in kReportCategories)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(m.categoryLabel(c)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (category == null || !context.mounted) return;
  await _submit(context, targetId, type, category);
}

Future<void> _submit(BuildContext context, String targetId, String type, String category) async {
  final m = context.l10nRead.mod;
  final outcome = await ModerationService.report(
    targetId: targetId,
    targetType: type,
    category: category,
    reason: ModerationStrings.categoryReason(category),
  );
  if (!context.mounted) return;

  switch (outcome.result) {
    case ReportResult.received:
      showModSnack(context, m.reportReceived);
    case ReportResult.duplicate:
      showModSnack(context, m.reportDuplicate);
    case ReportResult.ownContent:
      showModSnack(context, m.reportOwn);
    case ReportResult.missing:
      showModSnack(context, m.reportMissing);
    case ReportResult.restricted:
      await showRestrictionNotice(context, outcome.error?.restriction, scope: ModScope.account);
    case ReportResult.failed:
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(m.reportFailed),
          action: SnackBarAction(
            label: m.retry,
            onPressed: () => _submit(context, targetId, type, category),
          ),
        ));
  }
}
