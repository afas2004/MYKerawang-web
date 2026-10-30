import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../language_cubit.dart';
import '../widgets/app_toast.dart';

/// One look for action results: a plain confirmation on success, and on
/// failure a readable message with a Retry button (the raw error goes to
/// the debug log, not the user).

void showSuccess(BuildContext context, String message) {
  showToast(message);
}

void showErrorWithRetry(BuildContext context, Object error,
    {VoidCallback? onRetry, String? message}) {
  debugPrint('Action failed: $error');
  if (!context.mounted) return;
  final s = context.l10nRead;
  showToast(
    message ?? s.somethingWentWrong,
    error: true,
    actionLabel: onRetry == null ? null : s.retry,
    onAction: onRetry,
  );
}
