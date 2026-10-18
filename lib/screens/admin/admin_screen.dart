import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../widgets/moderation_ui.dart';
import 'appeals_tab.dart';
import 'cases_tab.dart';
import 'club_approvals_tab.dart';
import 'log_tab.dart';
import 'restrictions_tab.dart';
import 'settings_tab.dart';

/// /admin — moderation console. The route is reachable by URL, so the
/// page checks the role itself; the database checks it again on every
/// read and action.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<(bool, bool)> _access = _load();

  Future<(bool, bool)> _load() async =>
      (await ModerationService.isAdmin(), await ModerationService.isOwner());

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    return FutureBuilder<(bool, bool)>(
      future: _access,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(m.moderation)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final (admin, owner) = snap.data ?? (false, false);
        if (!admin) {
          return Scaffold(
            appBar: AppBar(title: Text(m.moderation)),
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ModEmptyState(
                    icon: Icons.lock_outline, title: m.adminOnly, body: m.adminOnlyBody),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: Text(context.l10n.goHome),
                ),
                if (snap.hasError)
                  TextButton(
                    onPressed: () => setState(() => _access = _load()),
                    child: Text(m.retry),
                  ),
              ],
            ),
          );
        }

        final tabs = <(String, IconData, Widget)>[
          (m.tabCases, Icons.inbox_outlined, const CasesTab()),
          (m.tabClubs, Icons.verified_outlined, const ClubApprovalsTab()),
          (m.tabAppeals, Icons.gavel_outlined, const AppealsTab()),
          (m.tabRestrictions, Icons.block_outlined, const RestrictionsTab()),
          (m.tabLog, Icons.receipt_long_outlined, const LogTab()),
          if (owner) (m.tabSettings, Icons.tune, const SettingsTab()),
        ];

        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(m.moderation),
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1),
                ],
              ),
            ),
            body: TabBarView(children: [for (final t in tabs) t.$3]),
          ),
        );
      },
    );
  }
}

/// Loading / error-with-retry / empty / list, the same way in every tab.
class AdminAsyncList<T> extends StatelessWidget {
  final Future<List<T>> future;
  final VoidCallback onRetry;
  final Widget empty;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget? header;

  const AdminAsyncList({
    super.key,
    required this.future,
    required this.onRetry,
    required this.empty,
    required this.itemBuilder,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (context, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Center(child: CircularProgressIndicator());
        } else if (snap.hasError) {
          body = _AdminError(error: snap.error!, onRetry: onRetry);
        } else if (snap.data!.isEmpty) {
          body = empty;
        } else {
          final items = snap.data!;
          body = RefreshIndicator(
            onRefresh: () async => onRetry(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: items.length,
              itemBuilder: (c, i) => itemBuilder(c, items[i]),
            ),
          );
        }
        if (header == null) return body;
        return Column(children: [header!, Expanded(child: body)]);
      },
    );
  }
}

class _AdminError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _AdminError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(modErrorText(context, error, fallback: context.l10n.connectionError),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(m.retry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar + name line for a profile json (or "Anonymous author").
class AdminUserLine extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final bool anonymous;
  final String? trailing;

  const AdminUserLine({super.key, required this.profile, this.anonymous = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    final avatar = profile?['avatar_url'] as String?;
    final name = anonymous || profile == null
        ? m.anonymousAuthor
        : '${profile!['display_name'] ?? profile!['username'] ?? '?'}';
    final username = anonymous ? null : profile?['username'] as String?;
    return Row(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: scheme.surfaceContainerHighest,
          backgroundImage: avatar != null && !anonymous ? NetworkImage(avatar) : null,
          child: avatar == null || anonymous
              ? Icon(anonymous ? Icons.visibility_off : Icons.person,
                  size: 14, color: scheme.onSurfaceVariant)
              : null,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            username == null ? name : '$name  @$username',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}
