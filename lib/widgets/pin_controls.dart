import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../theme/app_icons.dart';
import '../utils/moderation_logic.dart';
import 'moderation_ui.dart';

/// "Pinned" label for posts_public rows with is_pinned = true, for places
/// that don't use `KCard(official: true, officialLabel: …)`.
class PinBadge extends StatelessWidget {
  final Map<String, dynamic> post;
  const PinBadge({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    if (post['is_pinned'] != true) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ModChip(
        label: context.l10n.mod.pinned,
        icon: AppIcons.pin,
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
    );
  }
}

/// Pin / unpin as an action (it lives in a post's "more" menu).
///
/// Admins can pin any post; clubs their own non-anonymous posts. At the
/// club cap it explains and offers to replace the current pin. Every
/// outcome shows a snackbar (with Undo after a change).
abstract final class PinActions {
  /// Whether someone with [role] may pin [post].
  static bool canPin(Map<String, dynamic> post, String? role) {
    if (role == 'admin' || role == 'owner') return true;
    final me = ModerationService.currentUserId;
    return role == 'club' &&
        me != null &&
        post['user_id'] == me &&
        post['is_anonymous'] != true;
  }

  /// Pins or unpins; completes with the new pinned state (unchanged on
  /// failure or when the user backs out of replacing a pin).
  static Future<bool> toggle(BuildContext context, Map<String, dynamic> post,
      {required bool pinned}) async {
    final id = '${post['id']}';
    try {
      if (pinned) {
        await ModerationService.unpin(id);
        if (context.mounted) {
          showModSnack(context, modStrings(context).unpinnedDone,
              onUndo: () => ModerationService.pin(id, replace: true));
        }
        return false;
      }
      return await _pin(context, id, replace: false);
    } catch (e) {
      if (context.mounted) showModError(context, e);
      return pinned;
    }
  }

  static Future<bool> _pin(BuildContext context, String id,
      {required bool replace}) async {
    try {
      final r = await ModerationService.pin(id, replace: replace);
      if (!context.mounted) return true;
      final until = DateTime.tryParse('${r['pinned_until']}');
      final days = until == null
          ? 0
          : (until.difference(DateTime.now()).inHours / 24).round();
      showModSnack(context, modStrings(context).pinnedFor.fill([days]),
          onUndo: () => ModerationService.unpin(id));
      return true;
    } catch (e) {
      final err = parseModError(e);
      if (err?.code != 'pin_cap' || !context.mounted) rethrow;
      final m = modStrings(context);
      final pins = (err!.detail['pins'] as List?) ?? const [];
      final current = pins.isEmpty
          ? ''
          : '${(pins.first as Map)['title'] ?? context.l10nRead.untitled}';
      final ok = await confirmModAction(
        context,
        title: m.pinCapTitle,
        body: m.pinCapBody.fill([err.detail['max'] ?? 1, current]),
        confirmLabel: m.replace,
      );
      if (!ok || !context.mounted) return false;
      return _pin(context, id, replace: true);
    }
  }
}
