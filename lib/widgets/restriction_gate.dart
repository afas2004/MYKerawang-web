import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import 'moderation_ui.dart';

export '../utils/moderation_logic.dart' show ModScope;

/// Call before a create/edit action:
///
///     if (!await ensureCanWrite(context, ModScope.post)) return;
///
/// A restricted user gets an explanation (what, why, until, appeal)
/// instead of a form that fails on submit. If the status can't be
/// loaded the write goes ahead — the database enforces it anyway, and
/// [describeWriteError] explains the refusal.
Future<bool> ensureCanWrite(BuildContext context, ModScope scope) async {
  ModerationStatus status;
  try {
    status = await ModerationService.myStatus();
  } catch (_) {
    return true;
  }
  final blocking = status.blocking(scope);
  if (blocking == null) return true;
  if (context.mounted) await showRestrictionNotice(context, blocking, scope: scope);
  return false;
}

/// Text for a failed write. Moderation refusals (restriction, new-account
/// rate limit) become a sentence; anything else falls back to the usual
/// "Error: …" line.
String describeWriteError(BuildContext context, Object e) {
  final err = parseModError(e);
  if (err?.code == 'restricted') ModerationService.invalidateStatus();
  return modErrorText(context, e,
      fallback: context.l10nRead.errorWithDetail.fill([e]));
}

/// The dialog a restricted user sees: exactly what is restricted, why
/// and until when, with a way to the account-status page to appeal.
Future<void> showRestrictionNotice(BuildContext context, Restriction? r,
    {required ModScope scope}) {
  final m = context.l10nRead.mod;
  final s = r?.scope ?? scope;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.block, color: scheme.error),
        title: Text(m.cantTitle(s.db)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r != null && r.reason.trim().isNotEmpty) ...[
              Text(m.restrictedReason.fill([r.reason])),
              const SizedBox(height: 8),
            ],
            if (r != null)
              Text(r.until == null
                  ? m.restrictedPermanent
                  : m.restrictedUntil.fill([formatUntil(r.until!)])),
            if (r?.automatic == true) ...[
              const SizedBox(height: 8),
              Text(m.restrictedAuto,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/standing');
            },
            child: Text(m.accountStatus),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(m.ok)),
        ],
      );
    },
  );
}
