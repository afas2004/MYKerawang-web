import 'package:flutter/material.dart';

import '../language_cubit.dart';
import '../theme/app_icons.dart';

/// Asks before deleting. Completes with true when confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final s = context.l10nRead;
  final error = Theme.of(context).colorScheme.error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.delete, style: TextStyle(color: error)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The "⋮ → Edit / Delete" menu the author sees on their own post or
/// comment, in place of [ReportMenuButton].
class OwnerMenuButton extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double? iconSize;

  /// Names the button for screen readers; defaults to "More".
  final String? tooltip;

  const OwnerMenuButton({
    super.key,
    required this.onEdit,
    required this.onDelete,
    this.iconSize,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    return PopupMenuButton<String>(
      tooltip: tooltip ?? s.more,
      icon: Icon(AppIcons.more,
          size: iconSize, color: scheme.onSurfaceVariant),
      onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(AppIcons.edit, color: scheme.onSurface, size: 20),
              const SizedBox(width: 8),
              Text(s.edit),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(AppIcons.delete, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Text(s.delete, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}
