import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/utils/app_nav.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/admin_unlock.dart';
import '../../services/moderation_service.dart';
import '../../services/student_verification.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_lock_screen.dart';
import 'admin_overview.dart';
import 'appeals_tab.dart';
import 'cases_tab.dart';
import 'categories_tab.dart';
import 'club_approvals_tab.dart';
import 'join_requests_tab.dart';
import 'log_tab.dart';
import 'restrictions_tab.dart';
import 'settings_tab.dart';
import 'verifications_tab.dart';

/// /admin — moderation console. The route is reachable by URL, so the
/// page checks the role itself; the database checks it again on every
/// read and action.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<(bool, bool, bool, bool)> _access = _load();

  Future<(bool, bool, bool, bool)> _load() async {
    final admin = await ModerationService.isAdmin();
    var owner = false;
    var configured = false;
    var verifyEnabled = false;
    if (admin) {
      owner = await ModerationService.isOwner();
      try {
        configured = await ModerationService.adminPinConfigured();
      } catch (_) {
        // A transient failure must not lock an admin out of the console.
        configured = false;
      }
      verifyEnabled = await StudentVerificationService.isEnabled();
    }
    AdminUnlock.instance.setConfigured(configured);
    return (admin, owner, configured, verifyEnabled);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    return FutureBuilder<(bool, bool, bool, bool)>(
      future: _access,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(leading: const AppBackButton(), title: Text(m.moderation)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final (admin, owner, _, verifyEnabled) =
            snap.data ?? (false, false, false, false);
        if (!admin) {
          return Scaffold(
            appBar: AppBar(leading: const AppBackButton(), title: Text(m.moderation)),
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ModEmptyState(
                    icon: ModIcons.lock, title: m.adminOnly, body: m.adminOnlyBody),
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

        return ListenableBuilder(
          listenable: AdminUnlock.instance,
          builder: (context, _) {
            if (AdminUnlock.instance.configured && !AdminUnlock.instance.unlocked) {
              return Scaffold(
                appBar: AppBar(leading: const AppBackButton(), title: Text(m.moderation)),
                body: AdminLockScreen(
                  unlock: AdminUnlock.instance.unlock,
                  onUnlocked: () {},
                ),
              );
            }
            return _console(context, owner, AdminUnlock.instance.configured, verifyEnabled);
          },
        );
      },
    );
  }

  Widget _console(
      BuildContext context, bool owner, bool configured, bool verifyEnabled) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    final tabs = <(String, IconData, Widget)>[
      (m.tabCases, ModIcons.inbox, const CasesTab()),
      (m.tabClubs, ModIcons.verified, const ClubApprovalsTab()),
      (m.tabJoinRequests, ModIcons.person, const JoinRequestsTab()),
      (m.tabAppeals, ModIcons.appeal, const AppealsTab()),
      (m.tabRestrictions, ModIcons.ban, const RestrictionsTab()),
      (m.tabLog, ModIcons.log, const LogTab()),
      (context.l10n.catTitle, ModIcons.category, const CategoriesTab()),
      if (verifyEnabled)
        (context.l10n.verifyQueueTitle, ModIcons.verified, const VerificationsTab()),
      if (owner) (m.tabSettings, ModIcons.settings, const SettingsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: Text(m.moderation),
          actions: [
            if (configured)
              IconButton(
                tooltip: m.lockNow,
                icon: const Icon(ModIcons.lock),
                onPressed: AdminUnlock.instance.lock,
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1),
            ],
          ),
        ),
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => AdminUnlock.instance.touch(),
          onPointerSignal: (_) => AdminUnlock.instance.touch(),
          child: Builder(
            builder: (context) => Column(
              children: [
                if (!configured && owner)
                  Container(
                    width: double.infinity,
                    color: scheme.tertiaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(ModIcons.info, size: 18, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(m.adminPinSetupHint,
                              style: TextStyle(color: scheme.onTertiaryContainer)),
                        ),
                      ],
                    ),
                  ),
                _OverviewLoader(
                    onOpenTab: (i) => DefaultTabController.of(context).animateTo(i)),
                Expanded(child: TabBarView(children: [for (final t in tabs) t.$3])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fetches the queue summary for [AdminOverview]; refetches whenever a
/// tab bumps [adminSummaryRefresh].
class _OverviewLoader extends StatefulWidget {
  final void Function(int) onOpenTab;
  const _OverviewLoader({required this.onOpenTab});

  @override
  State<_OverviewLoader> createState() => _OverviewLoaderState();
}

class _OverviewLoaderState extends State<_OverviewLoader> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    adminSummaryRefresh.addListener(_fetch);
    _fetch();
  }

  @override
  void dispose() {
    adminSummaryRefresh.removeListener(_fetch);
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final s = await ModerationService.queueSummary();
      if (mounted) setState(() => _summary = s);
    } catch (_) {
      // The tabs show their own errors; the cards keep their last values.
    }
  }

  @override
  Widget build(BuildContext context) =>
      AdminOverview(summary: _summary, onOpenTab: widget.onOpenTab);
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
            Icon(ModIcons.error, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(modErrorText(context, error, fallback: context.l10n.connectionError),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(ModIcons.refresh),
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
              ? Icon(anonymous ? ModIcons.hidden : ModIcons.person,
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
