import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../utils/formatters.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';
import 'restrict_dialog.dart';

/// Active (or all) restrictions; lift early with Undo; restrict a user
/// by username.
class RestrictionsTab extends StatefulWidget {
  const RestrictionsTab({super.key});

  @override
  State<RestrictionsTab> createState() => _RestrictionsTabState();
}

class _RestrictionsTabState extends State<RestrictionsTab>
    with AutomaticKeepAliveClientMixin {
  bool _activeOnly = true;
  late Future<List<Map<String, dynamic>>> _future = ModerationService.restrictions();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(
      () => _future = ModerationService.restrictions(activeOnly: _activeOnly));

  Future<void> _lift(Map<String, dynamic> r) async {
    final m = modStrings(context);
    final reason = await askReason(context, title: m.liftTitle, confirmLabel: m.lift);
    if (reason == null || !mounted) return;
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await ModerationService.liftRestriction(id, reason);
      if (!mounted) return;
      showModSnack(context, m.lifted, onUndo: () async {
        await ModerationService.reinstateRestriction(id);
        if (mounted) _reload();
      });
      _reload();
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _restrictSomeone() async {
    final m = modStrings(context);
    final ctrl = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.restrictSomeone),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              labelText: m.usernameLabel, prefixText: '@', border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(m.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(m.confirm)),
        ],
      ),
    );
    ctrl.dispose();
    if (username == null || username.trim().isEmpty || !mounted) return;

    Map<String, dynamic>? user;
    try {
      user = await ModerationService.findUser(username);
    } catch (e) {
      if (mounted) showModError(context, e);
      return;
    }
    if (!mounted) return;
    if (user == null) {
      showModSnack(context, m.userNotFound, error: true);
      return;
    }

    final choice = await showRestrictDialog(context,
        who: '${user['display_name'] ?? user['username']}');
    if (choice == null || !mounted) return;
    if (isSevereRestriction(choice.scopes, choice.duration)) {
      final ok = await confirmModAction(context,
          title: m.restrictTitle, body: m.severeWarning, confirmLabel: m.confirm, destructive: true);
      if (!ok || !mounted) return;
    }
    try {
      await ModerationService.restrict(
          userId: '${user['id']}',
          scopes: choice.scopes,
          duration: choice.duration,
          reason: choice.reason);
      if (!mounted) return;
      showModSnack(context, m.doneRestricted);
      _reload();
    } catch (e) {
      if (mounted) showModError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            FilterChip(
              label: Text(m.activeOnly),
              selected: _activeOnly,
              onSelected: (v) {
                _activeOnly = v;
                _reload();
              },
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _restrictSomeone,
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: Text(m.restrictSomeone),
            ),
          ],
        ),
      ),
      empty: ModEmptyState(icon: Icons.verified_user_outlined, title: m.noRestrictions),
      itemBuilder: (context, r) {
        final busy = _busy.contains('${r['id']}');
        final active = r['active'] == true;
        final until = DateTime.tryParse('${r['until']}');
        final lifted = DateTime.tryParse('${r['lifted_at']}');
        final created = DateTime.tryParse('${r['created_at']}');
        final scope = r['scope'] as String?;
        final by = r['automatic'] == true
            ? m.bySystem
            : m.byName.fill([r['created_by_name'] ?? '?']);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: scope == 'account' && active ? scheme.error : scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy) const LinearProgressIndicator(minHeight: 2),
                AdminUserLine(
                  profile: r['profile'] as Map<String, dynamic>?,
                  anonymous: r['anonymous_source'] == true,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ModChip(
                      label: m.scopeLabel(scope),
                      icon: Icons.block,
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                    ),
                    ModChip(
                      label: !active
                          ? (lifted != null ? m.lift : m.ended)
                          : until == null
                              ? m.permanent
                              : m.untilDate.fill([formatUntil(until)]),
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurface,
                    ),
                    if (r['automatic'] == true)
                      ModChip(
                        label: m.automatic,
                        icon: Icons.smart_toy_outlined,
                        background: scheme.secondaryContainer,
                        foreground: scheme.onSecondaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(m.restrictedReason.fill([r['reason'] ?? ''])),
                Text(
                  [by, if (created != null) formatDate(created)].join(' · '),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (lifted != null && (r['lift_reason'] as String?)?.isNotEmpty == true)
                  Text('${r['lifted_by_name'] ?? ''}: ${r['lift_reason']}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (active)
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _lift(r),
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: Text(m.lift),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
