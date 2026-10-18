import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import 'moderation_ui.dart';

/// "📌 Pinned" label for posts_public rows with is_pinned = true.
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
        icon: Icons.push_pin,
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
    );
  }
}

/// Pin / unpin toggle. Shown to admins on any post, and to clubs on
/// their own non-anonymous posts; renders nothing for everyone else.
/// At the club cap it explains and offers to replace the current pin.
class PinMenuButton extends StatefulWidget {
  final Map<String, dynamic> post;
  const PinMenuButton({super.key, required this.post});

  @override
  State<PinMenuButton> createState() => _PinMenuButtonState();
}

class _PinMenuButtonState extends State<PinMenuButton> {
  late bool _pinned = widget.post['is_pinned'] == true;
  bool _busy = false;
  late final Future<String?> _role = ModerationService.myRole();

  bool _canPin(String? role) {
    if (role == 'admin' || role == 'owner') return true;
    final me = ModerationService.currentUserId;
    return role == 'club' &&
        me != null &&
        widget.post['user_id'] == me &&
        widget.post['is_anonymous'] != true;
  }

  Future<void> _toggle() async {
    final id = '${widget.post['id']}';
    setState(() => _busy = true);
    try {
      if (_pinned) {
        await ModerationService.unpin(id);
        _set(false);
        if (mounted) {
          showModSnack(context, modStrings(context).unpinnedDone, onUndo: () async {
            await ModerationService.pin(id, replace: true);
            _set(true);
          });
        }
      } else {
        await _pin(id, replace: false);
      }
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pin(String id, {required bool replace}) async {
    try {
      final r = await ModerationService.pin(id, replace: replace);
      _set(true);
      if (!mounted) return;
      final until = DateTime.tryParse('${r['pinned_until']}');
      final days = until == null
          ? 0
          : (until.difference(DateTime.now()).inHours / 24).round();
      showModSnack(context, modStrings(context).pinnedFor.fill([days]),
          onUndo: () async {
        await ModerationService.unpin(id);
        _set(false);
      });
    } catch (e) {
      final err = parseModError(e);
      if (err?.code != 'pin_cap' || !mounted) rethrow;
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
      if (ok) await _pin(id, replace: true);
    }
  }

  void _set(bool v) {
    if (mounted) setState(() => _pinned = v);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _role,
      builder: (context, snap) {
        if (!_canPin(snap.data)) return const SizedBox.shrink();
        final m = context.l10n.mod;
        final scheme = Theme.of(context).colorScheme;
        return IconButton(
          tooltip: _pinned ? m.unpin : m.pin,
          onPressed: _busy ? null : _toggle,
          icon: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 20,
                  color: _pinned ? scheme.primary : scheme.onSurfaceVariant),
        );
      },
    );
  }
}
