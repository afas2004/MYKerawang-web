import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../language_cubit.dart';

/// One look for action results: a plain confirmation on success, and on
/// failure a readable message with a Retry button (the raw error goes to
/// the debug log, not the user).

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showErrorWithRetry(BuildContext context, Object error,
    {VoidCallback? onRetry, String? message}) {
  debugPrint('Action failed: $error');
  if (!context.mounted) return;
  final s = context.l10nRead;
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message ?? s.somethingWentWrong,
          style: TextStyle(color: scheme.onErrorContainer)),
      backgroundColor: scheme.errorContainer,
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: s.retry,
              textColor: scheme.onErrorContainer,
              onPressed: onRetry,
            ),
    ));
}
