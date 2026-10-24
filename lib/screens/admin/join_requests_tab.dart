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

/// Pending club join requests across every club. Admins and the owner can
/// approve or decline; officers handle their own club from its manage page.
class JoinRequestsTab extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String requestId, bool approve)? decide;

  const JoinRequestsTab({super.key, this.load, this.decide});

  @override
  State<JoinRequestsTab> createState() => _JoinRequestsTabState();
}

class _JoinRequestsTabState extends State<JoinRequestsTab> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future = _fetch();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  Future<List<Map<String, dynamic>>> _fetch() =>
      (widget.load ?? ClubService.adminJoinRequests)();

  void _reload() => setState(() {
        _future = _fetch();
      });

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final c = context.l10nRead.club;
    final user = (r['user'] as Map?) ?? const {};
    final name = '${user['display_name'] ?? user['username'] ?? ''}';
    final ok = await confirmModAction(
      context,
      title: (approve ? c.approveJoinTitle : c.rejectJoinTitle).fill([name]),
      body: approve ? c.approveJoinBody : c.rejectJoinBody,
      confirmLabel: approve ? c.approveJoin : c.rejectJoin,
      destructive: !approve,
    );
    if (!ok) return;
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await (widget.decide ?? ClubService.decideJoin)(id, approve);
      if (!mounted) return;
      showModSnack(context, approve ? c.joinedClub.fill([name]) : c.requestRejected);
      adminSummaryRefresh.value++;
      _reload();
    } catch (e) {
      if (mounted) showModSnack(context, clubErrorText(c, e, fallback: modErrorText(context, e)), error: true);
      if (clubErrorCode(e) == 'not_pending' || clubErrorCode(e) == 'request_not_found') _reload();
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
      empty: ModEmptyState(icon: ModIcons.person, title: c.noJoinRequests),
      itemBuilder: (context, r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
        child: _JoinRequestCard(
          request: r,
          busy: _busy.contains('${r['id']}'),
          onApprove: () => _decide(r, true),
          onReject: () => _decide(r, false),
        ),
      ),
    );
  }
}

class _JoinRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _JoinRequestCard({
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
    final user = (request['user'] as Map?) ?? const {};
    final name = '${user['display_name'] ?? user['username'] ?? ''}';
    final username = user['username'] as String?;
    final avatar = user['avatar_url'] as String?;
    final message = (request['message'] as String?)?.trim();
    final clubName = '${request['club_name'] ?? ''}';
    final clubHandle = request['club_handle'] as String?;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.surfaceContainerHighest,
                backgroundImage: avatar == null ? null : NetworkImage(avatar),
                child: avatar == null ? Icon(ModIcons.person, size: 20, color: scheme.onSurfaceVariant) : null,
              ),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    if (username != null) Text('@$username', style: muted),
                  ],
                ),
              ),
              if (clubHandle != null)
                TextButton(
                  onPressed: () => context.push('/c/$clubHandle'),
                  child: Text('@$clubHandle'),
                ),
            ],
          ),
          const SizedBox(height: KSpace.s),
          Text('${c.joinClub} · $clubName', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: KSpace.s),
            Text(message),
          ],
          const SizedBox(height: KSpace.s),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: KSpace.s,
            runSpacing: KSpace.xs,
            children: [
              TextButton(onPressed: busy ? null : onReject, child: Text(c.rejectJoin)),
              FilledButton.tonal(
                onPressed: busy ? null : onApprove,
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(c.approveJoin),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
