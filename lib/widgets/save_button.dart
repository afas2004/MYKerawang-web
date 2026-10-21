import 'package:flutter/material.dart';

import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../theme/app_icons.dart';
import '../services/saved_items.dart';

export '../services/saved_items.dart' show SavedType;

/// Bookmark toggle for a post, listing or event.
///
/// ```dart
/// SaveButton(type: SavedType.post, id: post['id'])
/// SaveButton(type: SavedType.listing, id: item['id'], color: kOnPhoto)
/// ```
///
/// State is shared through [SavedItems], so every button for the same
/// item stays in sync. Shows a snackbar on success and on failure.
/// Hidden when nobody is signed in.
class SaveButton extends StatefulWidget {
  final SavedType type;
  final Object id;

  /// Icon colour; defaults to the theme's icon colour (primary when saved).
  final Color? color;
  final double? iconSize;

  /// Called after a successful toggle with the new state.
  final ValueChanged<bool>? onChanged;

  const SaveButton({
    super.key,
    required this.type,
    required this.id,
    this.color,
    this.iconSize,
    this.onChanged,
  });

  @override
  State<SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<SaveButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final s = context.l10nRead.social;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final saved = await SavedItems.instance.toggle(widget.type, widget.id);
      widget.onChanged?.call(saved);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(saved ? s.savedToast : s.unsavedToast),
          duration: const Duration(seconds: 2),
        ));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(
        content: Text(s.saveFailed),
        action: SnackBarAction(label: s.retry, onPressed: _toggle),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n.social;
    final scheme = Theme.of(context).colorScheme;
    if (!SavedItems.instance.signedIn) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<Set<String>>(
      valueListenable: SavedItems.instance.keys,
      builder: (context, _, __) {
        final saved = SavedItems.instance.isSaved(widget.type, widget.id);
        return IconButton(
          tooltip: saved ? s.unsave : s.save,
          iconSize: widget.iconSize,
          onPressed: _busy ? null : _toggle,
          icon: Icon(
            saved ? AppIcons.saved : AppIcons.save,
            color: widget.color ?? (saved ? scheme.primary : null),
          ),
        );
      },
    );
  }
}
