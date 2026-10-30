import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/club_service.dart';
import '../services/moderation_service.dart';
import '../services/pinned_posts.dart';
import '../services/post_service.dart';
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
/// Global pins are admin-only. Club officers pin one post to their own
/// club's page; [toggleClub] handles that separate scope. Every outcome
/// shows a snackbar (with Undo after a change).
abstract final class PinActions {
  /// Whether someone with [role] may pin [post] globally.
  static bool canPin(Map<String, dynamic> post, String? role) =>
      role == 'admin' || role == 'owner';

  /// After any global pin change: every card showing the post updates at
  /// once, and the pin bar reloads, so nothing needs a manual refresh.
  static Future<void> _pinChanged(String id, bool pinned,
      {bool mandatory = false}) async {
    PostService.notifyPatched(
        id, {'is_pinned': pinned, 'pin_mandatory': pinned && mandatory});
    await PinnedPosts.refresh();
  }

  /// Normal or mandatory? Null when the admin backs out.
  static Future<bool?> _askMandatory(BuildContext context) {
    final s = context.l10nRead;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.pinChoiceTitle),
        children: [
          ListTile(
            title: Text(s.pinNormal),
            subtitle: Text(s.pinNormalHint),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            title: Text(s.pinMandatory),
            subtitle: Text(s.pinMandatoryHint),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  /// Turns a live pin mandatory or back to normal.
  static Future<void> setMandatory(
      BuildContext context, Map<String, dynamic> post, bool mandatory) async {
    try {
      await ModerationService.pin('${post['id']}', mandatory: mandatory);
      await _pinChanged('${post['id']}', true, mandatory: mandatory);
    } catch (e) {
      if (context.mounted) showModError(context, e);
    }
  }

  /// Pins or unpins globally; completes with the new state (unchanged on
  /// failure).
  static Future<bool> toggle(BuildContext context, Map<String, dynamic> post,
      {required bool pinned, void Function(bool pinned)? onChanged}) async {
    final id = '${post['id']}';
    try {
      if (pinned) {
        final mandatory = post['pin_mandatory'] == true;
        await ModerationService.unpin(id);
        onChanged?.call(false);
        await _pinChanged(id, false);
        if (context.mounted) {
          showModSnack(context, modStrings(context).unpinnedDone,
              onUndo: () async {
            await ModerationService.pin(id, replace: true, mandatory: mandatory);
            onChanged?.call(true);
            await _pinChanged(id, true, mandatory: mandatory);
          });
        }
        return false;
      }
      final mandatory = await _askMandatory(context);
      if (mandatory == null || !context.mounted) return pinned;
      return await _pin(context, id,
          replace: false, mandatory: mandatory, onChanged: onChanged);
    } catch (e) {
      if (context.mounted) showModError(context, e);
      return pinned;
    }
  }

  /// Pins or unpins on the club's own page; same contract as [toggle].
  static Future<bool> toggleClub(BuildContext context, Map<String, dynamic> post,
      {required bool pinned, void Function(bool pinned)? onChanged}) async {
    final id = '${post['id']}';
    try {
      if (pinned) {
        await ClubService.clubUnpin(id);
        onChanged?.call(false);
        if (context.mounted) {
          showModSnack(context, modStrings(context).unpinnedDone,
              onUndo: () async {
            await ClubService.clubPin(id, replace: true);
            onChanged?.call(true);
          });
        }
        return false;
      }
      return await _clubPin(context, id, replace: false, onChanged: onChanged);
    } catch (e) {
      if (context.mounted) showModError(context, e);
      return pinned;
    }
  }

  static Future<bool> _pin(BuildContext context, String id,
      {required bool replace,
      bool mandatory = false,
      void Function(bool pinned)? onChanged}) async {
    try {
      final r =
          await ModerationService.pin(id, replace: replace, mandatory: mandatory);
      onChanged?.call(true);
      await _pinChanged(id, true, mandatory: mandatory);
      if (!context.mounted) return true;
      // A mandatory pin has no end date ('infinity' doesn't parse).
      if (mandatory) {
        showModSnack(context, context.l10nRead.pinMandatoryDone, onUndo: () async {
          await ModerationService.unpin(id);
          onChanged?.call(false);
          await _pinChanged(id, false);
        });
        return true;
      }
      final until = DateTime.tryParse('${r['pinned_until']}');
      final days = until == null
          ? 0
          : (until.difference(DateTime.now()).inHours / 24).round();
      showModSnack(context, modStrings(context).pinnedFor.fill([days]),
          onUndo: () async {
        await ModerationService.unpin(id);
        onChanged?.call(false);
        await _pinChanged(id, false);
      });
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
      return _pin(context, id,
          replace: true, mandatory: mandatory, onChanged: onChanged);
    }
  }

  static Future<bool> _clubPin(BuildContext context, String id,
      {required bool replace, void Function(bool pinned)? onChanged}) async {
    try {
      final r = await ClubService.clubPin(id, replace: replace);
      onChanged?.call(true);
      if (!context.mounted) return true;
      final until = DateTime.tryParse('${r['club_pinned_until']}');
      final days = until == null
          ? 0
          : (until.difference(DateTime.now()).inHours / 24).round();
      showModSnack(context, modStrings(context).pinnedFor.fill([days]),
          onUndo: () async {
        await ClubService.clubUnpin(id);
        onChanged?.call(false);
      });
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
      return _clubPin(context, id, replace: true, onChanged: onChanged);
    }
  }
}
