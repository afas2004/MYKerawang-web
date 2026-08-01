import 'package:flutter/material.dart';
import '../language_cubit.dart';

/// Shared "couldn't load" state with a retry, so a dropped connection
/// never leaves a blank screen or an endless spinner
/// (UI_UX_AUDIT 2.13 / 15.5).
class ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const ErrorState({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message ?? context.l10n.connectionError,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
