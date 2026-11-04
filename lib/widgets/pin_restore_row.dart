import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import 'brand/brand.dart';

/// "N closed pins · Show", at the top of Home.
///
/// Closing a pin hides it on that device only, and closing the last one
/// takes the whole bar away with it — so the way back has to live outside
/// the bar. This slim row sits where the bar would be and brings every
/// closed pin back in one tap.
class PinRestoreRow extends StatelessWidget {
  /// Live pins this device has closed. Nothing is drawn at 0.
  final int count;
  final VoidCallback onRestore;

  const PinRestoreRow({super.key, required this.count, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.xs, 0),
      child: Row(
        children: [
          Icon(AppIcons.pin, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: Text(
              count == 1 ? s.pinClosedOne : s.pinClosedMany.fill([count]),
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onRestore,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 36),
            ),
            child: Text(s.pinShowClosed),
          ),
        ],
      ),
    );
  }
}
