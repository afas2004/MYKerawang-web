import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../utils/moderation_logic.dart';

/// Shared moderation feedback: error text, snackbars, confirm and
/// reason dialogs, empty states. Every moderation interaction goes
/// through these so it always acknowledges itself the same way.

ModerationStrings modStrings(BuildContext context) => context.l10nRead.mod;

final _untilFormat = DateFormat('d MMM yyyy, h:mm a');
String formatUntil(DateTime d) => _untilFormat.format(d.toLocal());

/// Human text for any error a moderation call can throw. Falls back to
/// [fallback] (or a generic line) when it isn't a moderation error.
String modErrorText(BuildContext context, Object e, {String? fallback}) {
  final m = modStrings(context);
  final err = parseModError(e);
  if (err == null) return fallback ?? m.errGeneric;
  return switch (err.code) {
    'restricted' => restrictionSentence(m, err.restriction, err.sub),
    'rate_limited' => m.rateLimited.fill([
        m.rateKind(err.sub),
        err.detail['limit'] ?? '?',
        err.detail['hours'] ?? '?',
      ]),
    'duplicate_report' => m.reportDuplicate,
    'self_report' => m.reportOwn,
    'target_missing' => m.reportMissing,
    'not_admin' => m.errNotAdmin,
    'already_resolved' => m.errAlreadyResolved,
    'cannot_undo' => m.errCannotUndo,
    'protected_user' => m.errProtectedUser,
    'self' => m.errSelf,
    'not_found' => m.errNotFound,
    'no_user' => m.errNoUser,
    'not_pending' => m.errNotPending,
    'bulk_spam_only' => m.errBulkSpamOnly,
    'reason_required' => m.reasonTooShort,
    'no_scope' => m.pickScope,
    'pin_anonymous' => m.pinAnonymous,
    'pin_not_allowed' => m.pinNotAllowed,
    'already_appealed' => m.appealDuplicate,
    'not_appealable' => m.appealNotAllowed,
    'message_length' => m.appealLength,
    _ => fallback ?? m.errGeneric,
  };
}

/// "You can't post right now. Reason: … This ends on …"
String restrictionSentence(ModerationStrings m, Restriction? r, [String? scope]) {
  final parts = <String>['${m.cantTitle(r?.scope.db ?? scope)}.'];
  if (r != null && r.reason.trim().isNotEmpty) {
    parts.add(m.restrictedReason.fill([r.reason]));
  }
  if (r != null) {
    parts.add(r.until == null
        ? m.restrictedPermanent
        : m.restrictedUntil.fill([formatUntil(r.until!)]));
  }
  return parts.join(' ');
}

/// Snackbar with an optional Undo. Undo failures surface their own
/// error instead of disappearing.
void showModSnack(BuildContext context, String text,
    {Future<void> Function()? onUndo, bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final m = modStrings(context);
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? scheme.errorContainer : null,
      showCloseIcon: error,
      closeIconColor: error ? scheme.onErrorContainer : null,
      duration: Duration(seconds: onUndo != null ? 8 : 4),
      action: onUndo == null
          ? null
          : SnackBarAction(
              label: m.undo,
              onPressed: () async {
                try {
                  await onUndo();
                  messenger.showSnackBar(SnackBar(content: Text(m.undone)));
                } catch (e) {
                  if (context.mounted) {
                    messenger.showSnackBar(
                        SnackBar(content: Text(modErrorText(context, e))));
                  }
                }
              },
            ),
    ));
}

void showModError(BuildContext context, Object e) =>
    showModSnack(context, modErrorText(context, e), error: true);

/// Yes/no confirmation for actions that can't be undone.
Future<bool> confirmModAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final m = modStrings(context);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(m.cancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Confirmation that also collects a required reason. Returns the
/// trimmed reason, or null when cancelled.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  String? label,
  String? helper,
  int minLength = 3,
  bool destructive = false,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      label: label,
      helper: helper,
      minLength: minLength,
      destructive: destructive,
      initial: initial,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String? body;
  final String confirmLabel;
  final String? label;
  final String? helper;
  final int minLength;
  final bool destructive;
  final String initial;

  const _ReasonDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.label,
    required this.helper,
    required this.minLength,
    required this.destructive,
    required this.initial,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _tried = false;

  bool get _valid => _ctrl.text.trim().length >= widget.minLength;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.body != null) ...[
              Text(widget.body!),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              onChanged: (_) {
                if (_tried) setState(() {});
              },
              decoration: InputDecoration(
                labelText: widget.label ?? m.reasonLabel,
                helperText: widget.helper ?? m.reasonHelp,
                helperMaxLines: 3,
                errorText: _tried && !_valid ? m.reasonTooShort : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(m.cancel)),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Centered icon + title + optional line, for empty lists.
class ModEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;

  const ModEmptyState({super.key, required this.icon, required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small rounded label (status, category, priority).
class ModChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const ModChip(
      {super.key,
      required this.label,
      required this.background,
      required this.foreground,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: foreground)),
        ],
      ),
    );
  }
}
