import 'package:flutter/material.dart';
import '../language_cubit.dart';
import '../l10n/brand_strings.dart';
import 'brand/brand.dart';

/// Shared "couldn't load" state with a retry, so a dropped connection
/// never leaves a blank screen or an endless spinner
/// (UI_UX_AUDIT 2.13 / 15.5).
///
/// With room (≥ 360 px tall) it shows the loose-thread scene; in short
/// panels, and wherever [plain] is set (moderation and admin pages, which
/// stay calm and illustration-free), just an icon.
class ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;
  final bool plain;

  const ErrorState({super.key, required this.onRetry, this.message, this.plain = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final roomy = !plain && (!box.maxHeight.isFinite || box.maxHeight >= 360);
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (roomy) ...[
                  const AppIllustration(AppIllo.error, size: 200),
                  const SizedBox(height: KSpace.l),
                  Text(context.l10n.brand.errorTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 20)),
                  const SizedBox(height: KSpace.s),
                ] else ...[
                  Icon(AppIcons.wifiOff, size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                ],
                Text(
                  message ?? context.l10n.connectionError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(AppIcons.refresh),
                  label: Text(context.l10n.tryAgain),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
