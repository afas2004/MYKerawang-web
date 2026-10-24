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

/// Clubs in the admin console: pending requests (approve → active +
/// verified, or reject with a reason) plus every active / suspended page
/// (suspend ↔ reactivate). Every action needs a reason; the RPC logs it and
/// notifies the club's president.
class ClubApprovalsTab extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String clubId, bool approve, String? reason)? decide;

  /// Loads clubs in a status (active / suspended); injected for tests.
  final Future<List<Map<String, dynamic>>> Function(String status)? loadClubs;

  /// Suspends / reactivates a club; injected for tests.
  final Future<void> Function(String clubId, String status, String reason)? setStatus;

  const ClubApprovalsTab({
    super.key,
    this.load,
    this.decide,
    this.loadClubs,
    this.setStatus,
  });

  @override
  State<ClubApprovalsTab> createState() => _ClubApprovalsTabState();
}

class _ClubApprovalsTabState extends State<ClubApprovalsTab> with AutomaticKeepAliveClientMixin {
  static const _pending = 'pending';
  String _status = _pending;
  late Future<List<Map<String, dynamic>>> _future = _fetch();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  Future<List<Map<String, dynamic>>> _fetch() => _status == _pending
      ? (widget.load ?? ClubService.pendingRequests)()
      : (widget.loadClubs ?? ClubService.adminClubs)(_status);

  void _reload() => setState(() {
        _future = _fetch();
      });

  void _setFilter(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _future = _fetch();
    });
  }

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

  Future<void> _changeStatus(Map<String, dynamic> r, String next) async {
    final c = context.l10nRead.club;
    final name = '${r['name']}';
    final suspend = next == 'suspended';
    final reason = await askReason(
      context,
      title: (suspend ? c.suspendTitle : c.reactivateTitle).fill([name]),
      body: suspend ? c.suspendBody : c.reactivateBody,
      confirmLabel: suspend ? c.suspend : c.reactivate,
      destructive: suspend,
    );
    if (reason == null) return;
    final id = '${r['id']}';
    setState(() => _busy.add(id));
    try {
      await (widget.setStatus ?? ClubService.setStatus)(id, next, reason);
      if (!mounted) return;
      showModSnack(context, suspend ? c.suspendedDone : c.reactivatedDone);
      adminSummaryRefresh.value++;
      _reload();
    } catch (e) {
      if (mounted) showModSnack(context, clubErrorText(c, e, fallback: modErrorText(context, e)), error: true);
      if (clubErrorCode(e) == 'not_found') _reload();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.l10n.club;
    final empty = switch (_status) {
      'suspended' => ModEmptyState(icon: AppIcons.warning, title: c.noSuspendedClubs),
      'active' => ModEmptyState(icon: AppIcons.people, title: c.noActiveClubs),
      _ => ModEmptyState(icon: AppIcons.verified, title: c.noClubRequests),
    };
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      header: _StatusFilter(
        value: _status,
        onChanged: _setFilter,
        onRegistry: () => context.push('/admin/clubs/registry'),
      ),
      empty: empty,
      itemBuilder: (context, r) {
        final id = '${r['id']}';
        final busy = _busy.contains(id);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
          child: _status == _pending
              ? ClubRequestCard(
                  request: r,
                  busy: busy,
                  onApprove: () => _decide(r, true),
                  onReject: () => _decide(r, false),
                )
              : AdminClubCard(
                  club: r,
                  busy: busy,
                  onOpen: () => context.push('/c/${r['handle']}'),
                  onToggle: () =>
                      _changeStatus(r, r['status'] == 'suspended' ? 'active' : 'suspended'),
                ),
        );
      },
    );
  }
}

/// Pending / active / suspended filter for the tab.
class _StatusFilter extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onRegistry;

  const _StatusFilter({
    required this.value,
    required this.onChanged,
    required this.onRegistry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final items = [
      ('pending', c.statusPending),
      ('active', c.statusActive),
      ('suspended', c.statusSuspended),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.xs),
      child: Row(
        children: [
          for (final (key, label) in items) ...[
            ChoiceChip(
              label: Text(label),
              selected: value == key,
              showCheckmark: false,
              onSelected: (_) => onChanged(key),
            ),
            const SizedBox(width: KSpace.s),
          ],
          const SizedBox(width: KSpace.s),
          TextButton.icon(
            onPressed: onRegistry,
            icon: const Icon(AppIcons.settings, size: 18),
            label: Text(c.registryManage),
          ),
        ],
      ),
    );
  }
}

/// One active or suspended club: tap to open the page, or change its status.
class AdminClubCard extends StatelessWidget {
  final Map<String, dynamic> club;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  const AdminClubCard({
    super.key,
    required this.club,
    required this.busy,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final suspended = club['status'] == 'suspended';
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return KCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Row(
            children: [
              ClubLogo(url: club['logo_url'] as String?, name: '${club['name']}', size: 48),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClubNameLine(
                      name: '${club['name']}',
                      verified: club['is_verified'] == true,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text('@${club['handle']}',
                        style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              ClubPill(
                c.statusLabel(club['status'] as String?),
                background: suspended ? scheme.errorContainer : scheme.primaryContainer,
                foreground: suspended ? scheme.onErrorContainer : scheme.onPrimaryContainer,
              ),
            ],
          ),
          const SizedBox(height: KSpace.m),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: KSpace.s,
            runSpacing: KSpace.xs,
            children: [
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(AppIcons.chevronRight, size: 18),
                label: Text(c.viewPage),
              ),
              if (suspended)
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onToggle,
                  icon: const Icon(AppIcons.verified, size: 18),
                  label: Text(c.reactivate),
                )
              else
                TextButton(
                  onPressed: busy ? null : onToggle,
                  child: Text(c.suspend, style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        ],
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
    final registryCode = r['registry_code'] as String?;
    final officialEmail = r['official_email'] as String?;
    final position = r['applicant_position'] as String?;
    final proof = r['proof_note'] as String?;
    final council = (r['council_members'] as List?) ?? const [];

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
          if (registryCode != null || officialEmail != null || position != null) ...[
            const SizedBox(height: KSpace.m),
            Wrap(
              spacing: KSpace.s,
              runSpacing: KSpace.xs,
              children: [
                if (registryCode != null) ClubPill('${c.registryCode}: $registryCode'),
                if (position != null) ClubPill(c.positionLabel(position)),
              ],
            ),
            if (officialEmail != null) ...[
              const SizedBox(height: KSpace.xs),
              Row(
                children: [
                  Icon(AppIcons.email, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: KSpace.xs),
                  Flexible(child: SelectableText(officialEmail, maxLines: 1, style: muted)),
                ],
              ),
            ],
          ],
          if (proof != null && proof.trim().isNotEmpty) ...[
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
                  SelectableText(proof),
                ],
              ),
            ),
          ],
          if (council.isNotEmpty) ...[
            const SizedBox(height: KSpace.m),
            Text('${c.council} (${council.length})', style: theme.textTheme.labelMedium),
            const SizedBox(height: KSpace.xs),
            for (final m in council)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${(m as Map)['name'] ?? ''}'
                  '${((m['position'] as String?) ?? '').isEmpty ? '' : ' · ${m['position']}'}',
                  style: muted,
                ),
              ),
          ],
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
