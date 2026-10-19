import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../utils/moderation_logic.dart';
import 'brand/brand.dart';

/// Shared moderation feedback: error text, snackbars, confirm and
/// reason dialogs, empty states. Every moderation interaction goes
/// through these so it always acknowledges itself the same way.

/// Moderation icons by meaning. Built on [AppIcons]; the few meanings
/// AppIcons doesn't cover yet use Lucide directly, here and nowhere
/// else, so they can move into AppIcons later in one step.
abstract final class ModIcons {
  // From AppIcons
  static const IconData comment = AppIcons.comment;
  static const IconData event = AppIcons.events;
  static const IconData listing = AppIcons.market;
  static const IconData person = AppIcons.person;
  static const IconData hidden = AppIcons.anonymous;
  static const IconData visible = AppIcons.visible;
  static const IconData verified = AppIcons.verified;
  static const IconData official = AppIcons.official;
  static const IconData moderation = AppIcons.moderation;
  static const IconData check = AppIcons.check;
  static const IconData success = AppIcons.success;
  static const IconData warning = AppIcons.warning;
  static const IconData info = AppIcons.info;
  static const IconData error = AppIcons.error;
  static const IconData urgent = AppIcons.error;
  static const IconData lock = AppIcons.lock;
  static const IconData refresh = AppIcons.refresh;
  static const IconData search = AppIcons.search;
  static const IconData download = AppIcons.download;
  static const IconData more = AppIcons.more;
  static const IconData externalLink = AppIcons.externalLink;
  static const IconData report = AppIcons.report;
  static const IconData clock = AppIcons.clock;
  static const IconData settings = AppIcons.settings;
  static const IconData history = AppIcons.history;
  // Not in AppIcons yet
  static const IconData post = LucideIcons.fileText;
  static const IconData appeal = LucideIcons.gavel;
  static const IconData ban = LucideIcons.ban;
  static const IconData inbox = LucideIcons.inbox;
  static const IconData restore = LucideIcons.rotateCcw;
  static const IconData keyboard = LucideIcons.keyboard;
  static const IconData log = LucideIcons.scrollText;
  static const IconData bot = LucideIcons.bot;
  static const IconData unlock = LucideIcons.lockOpen;
  static const IconData userX = LucideIcons.userX;
  static const IconData pause = LucideIcons.circlePause;
  static const IconData pending = LucideIcons.hourglass;
  static const IconData offline = LucideIcons.wifiOff;
  static const IconData searchOff = LucideIcons.searchX;
  static const IconData pointer = LucideIcons.mousePointerClick;
  static const IconData flagOff = LucideIcons.flagOff;
  static const IconData saveFile = LucideIcons.save;
}

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

/// Empty lists across moderation: the brand medallion empty state.
class ModEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppIllo? illo;

  const ModEmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.body,
      this.actionLabel,
      this.onAction,
      this.illo});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? box.maxHeight : 0),
            child: Center(
              child: BrandEmptyState(
                icon: icon,
                illo: illo,
                title: title,
                message: body,
                actionLabel: actionLabel,
                onAction: onAction,
                compact: box.maxHeight.isFinite && box.maxHeight < 360,
              ),
            ),
          ),
        ),
      );
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
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: KSpace.xs),
          ],
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: foreground)),
        ],
      ),
    );
  }
}
