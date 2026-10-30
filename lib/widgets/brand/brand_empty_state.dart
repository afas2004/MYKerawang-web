import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'app_illustration.dart';

/// Empty / nothing-here-yet state: an illustration (or an icon in a soft
/// tinted circle), a title, an optional message and an optional action.
///
///   BrandEmptyState(
///     illo: AppIllo.noEvents,
///     title: s.noEventsYet,
///     message: s.noEventsHint,
///     actionLabel: s.createEvent,
///     onAction: () => context.push('/events/new'),
///   )
///
/// Pass [illo] for full-page states; [icon] alone is fine for small
/// panels (or set [compact]).
class BrandEmptyState extends StatelessWidget {
  /// Shown when [illo] is null.
  final IconData icon;

  /// Spot illustration; takes precedence over [icon] (unless [compact]).
  final AppIllo? illo;

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller art and spacing for panels / rails; always uses the icon.
  final bool compact;

  const BrandEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    this.illo,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Widget art = (illo != null && !compact)
        ? AppIllustration(illo!, size: 200)
        : Container(
            width: compact ? 56 : 72,
            height: compact ? 56 : 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: compact ? 26 : 32, color: scheme.onPrimaryContainer),
          );

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? KSpace.l : KSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              art,
              SizedBox(height: compact ? KSpace.m : KSpace.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge?.copyWith(fontSize: 20),
              ),
              if (message != null) ...[
                const SizedBox(height: KSpace.s),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? KSpace.l : KSpace.xl),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
