import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import '../clubs/club_strings.dart';
import '../clubs/club_widgets.dart';
import 'admin_overview.dart';
import 'admin_screen.dart';

/// Pending club pages (20261022002200): approve → active + verified, or
/// reject with a reason. Both notify the club's president.
class ClubApprovalsTab extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String clubId, bool approve, String? reason)? decide;

  const ClubApprovalsTab({super.key, this.load, this.decide});

  @override
  State<ClubApprovalsTab> createState() => _ClubApprovalsTabState();
}

class _ClubApprovalsTabState extends State<ClubApprovalsTab> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future = _fetch();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  Future<List<Map<String, dynamic>>> _fetch() => (widget.load ?? ClubService.pendingRequests)();

  void _reload() => setState(() => _future = _fetch());

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final c = context.l10nRead.club;
    final name = '${r['name']}';
    String? reason;
    if (approve) {
      final ok = await confirmModAction(context,
          title: c.approveTitle.fill([name]), body: c.approveBody, confirmLabel: c.approve);
      if (!ok) return;
    } else {
      reason = await askReason(context,
          title: c.rejectTitle.fill([name]), confirmLabel: c.reject, destructive: true);
      if (reason == null) return;
    }
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await (widget.decide ?? ClubService.decideRequest)(id, approve, reason);
      if (!mounted) return;
      showModSnack(context, approve ? c.approved : c.rejected);
      adminSummaryRefresh.value++;
      _reload();
    } catch (e) {
      if (mounted) showModSnack(context, clubErrorText(c, e, fallback: modErrorText(context, e)), error: true);
      if (clubErrorCode(e) == 'not_pending') _reload();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.l10n.club;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      empty: ModEmptyState(icon: AppIcons.verified, title: c.noClubRequests),
      itemBuilder: (context, r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
        child: ClubRequestCard(
          request: r,
          busy: _busy.contains('${r['id']}'),
          onApprove: () => _decide(r, true),
          onReject: () => _decide(r, false),
        ),
      ),
    );
  }
}

class ClubRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const ClubRequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = request;
    final president = r['president'] as Map<String, dynamic>?;
    final created = DateTime.tryParse('${r['created_at']}');
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final presidentName = president == null
        ? '—'
        : '${president['display_name'] ?? president['username']} @${president['username']}';

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Row(
            children: [
              ClubLogo(url: r['logo_url'] as String?, name: '${r['name']}', size: 48),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['name']}', style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        '@${r['handle']}',
                        if ((r['category'] as String?)?.isNotEmpty == true) c.categoryLabel(r['category'] as String?),
                        if (created != null) formatUntil(created),
                      ].join(' · '),
                      style: muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((r['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: KSpace.m),
            Text('${r['description']}', maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: KSpace.m),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(KSpace.m),
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(AppIcons.lock, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: KSpace.xs),
                  Text(c.proofLabel, style: theme.textTheme.labelMedium),
                ]),
                const SizedBox(height: KSpace.xs),
                SelectableText('${r['proof_note'] ?? '—'}'),
              ],
            ),
          ),
          const SizedBox(height: KSpace.s),
          InkWell(
            onTap: president == null ? null : () => context.push('/u/${president['id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KSpace.xs),
              child: Text(c.requestedBy.fill([presidentName]), style: muted),
            ),
          ),
          const SizedBox(height: KSpace.s),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: busy ? null : onReject, child: Text(c.reject)),
              const SizedBox(width: KSpace.s),
              FilledButton.icon(
                onPressed: busy ? null : onApprove,
                icon: const Icon(AppIcons.verified, size: 18),
                label: Text(c.approve),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
