import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';
import '../../widgets/brand/brand.dart';

/// club_pending accounts: approve (→ club + verified) or reject with a
/// reason (→ student). Both notify the account.
class ClubApprovalsTab extends StatefulWidget {
  const ClubApprovalsTab({super.key});

  @override
  State<ClubApprovalsTab> createState() => _ClubApprovalsTabState();
}

class _ClubApprovalsTabState extends State<ClubApprovalsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future =
      ModerationService.clubRequests();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  void _reload() => setState(() => _future = ModerationService.clubRequests());

  Future<void> _decide(Map<String, dynamic> p, bool approve) async {
    final m = modStrings(context);
    final name = '${p['display_name'] ?? p['username'] ?? ''}';
    String? reason;
    if (approve) {
      final ok = await confirmModAction(
        context,
        title: m.approveTitle.fill([name]),
        body: m.approveBody,
        confirmLabel: m.approve,
      );
      if (!ok) return;
    } else {
      reason = await askReason(
        context,
        title: m.rejectClubTitle,
        confirmLabel: m.reject,
        destructive: true,
      );
      if (reason == null) return;
    }
    final id = '${p['id']}';
    setState(() => _busy.add(id));
    try {
      await ModerationService.decideClub(id, approve, reason);
      if (!mounted) return;
      showModSnack(context, approve ? m.clubApproved : m.clubRejected);
      _reload();
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      empty: ModEmptyState(
        icon: ModIcons.verified,
        title: m.noClubRequests,
      ),
      itemBuilder: (context, p) {
        final busy = _busy.contains('${p['id']}');
        final bio = p['bio'] as String?;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
          child: KCard(
            padding: const EdgeInsets.all(KSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy) const LinearProgressIndicator(minHeight: 2),
                AdminUserLine(profile: p),
                if (bio != null && bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(bio, maxLines: 4, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => _decide(p, false),
                      child: Text(m.reject),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: busy ? null : () => _decide(p, true),
                      icon: const Icon(ModIcons.verified, size: 18),
                      label: Text(m.approve),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
