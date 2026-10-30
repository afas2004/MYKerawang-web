import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/theme_cubit.dart';
import '../theme/app_themes.dart';
import '../widgets/brand/brand.dart';
import '../utils/adaptive.dart';
import '../l10n/app_strings.dart';
import '../l10n/access_strings.dart';
import '../l10n/account_strings.dart';
import '../language_cubit.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../l10n/brand_strings.dart';
import '../widgets/app_logo.dart';
import '../l10n/moderation_strings.dart';
import '../services/account_data.dart';
import '../services/moderation_service.dart';
import '../services/student_verification.dart';
import '../utils/app_nav.dart';
import '../utils/browser_history_stub.dart'
    if (dart.library.js_interop) '../utils/browser_history_web.dart';
import 'profile_cubit.dart';
import 'login_cubit.dart';
import 'verification/verify_sheet.dart';
import '../services/update_service.dart';
import '../widgets/app_toast.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Event-alert toggles (notify_new_events / notify_reminders) are hidden
  // until something actually sends those notifications; the DB columns
  // stay. Market "price drops" was removed — there's no saved-items feature.
  bool _checkingUpdate = false;
  bool _exporting = false;

  /// The account's recovery address, loaded from profile_contacts (the
  /// owner's own row is the only one readable).
  String? _backupEmail;
  bool _backupLoaded = false;

  /// Student verification: shown only while the owner has the switch on.
  bool _verifyEnabled = false;
  StudentVerification? _verification;

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadBackupEmail();
    _loadVerification();
  }

  Future<void> _loadVerification() async {
    final enabled = await StudentVerificationService.isEnabled();
    final v = enabled ? await StudentVerificationService.mine() : null;
    if (!mounted) return;
    setState(() {
      _verifyEnabled = enabled;
      _verification = v;
    });
  }

  String _verificationLabel(AppStrings s) => switch (_verification?.status) {
        'verified' => s.verifyStatusVerified,
        'pending' => s.verifyStatusPending,
        'rejected' => s.verifyStatusRejected,
        'revoked' => s.verifyStatusRevoked,
        _ => s.verifyStatusNone,
      };

  Future<void> _loadBackupEmail() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _supabase
          .from('profile_contacts')
          .select('backup_email')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _backupEmail = (row?['backup_email'] as String?)?.trim();
        _backupLoaded = true;
      });
    } catch (e) {
      debugPrint('Backup email load failed: $e');
      if (mounted) setState(() => _backupLoaded = true);
    }
  }

  // ---- Privacy & data (PDPA) ------------------------------------------

  Future<void> _exportData() async {
    final s = context.l10nRead;
    setState(() => _exporting = true);
    try {
      await AccountData.exportToFile();
      showToast(s.social.exportReady);
    } catch (e) {
      showToast(s.social.exportFailed.fill([e]), actionLabel: s.social.retry, onAction: _exportData);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<String?> _myUsername() async {
    final cached = context.read<ProfileCubit>().state.profile?['username'];
    if (cached is String && cached.isNotEmpty) return cached;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _supabase
        .from('profiles')
        .select('username')
        .eq('id', uid)
        .maybeSingle();
    return row?['username'] as String?;
  }

  Future<String?> _myRole() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;
    final row =
        await _supabase.from('profiles').select('role').eq('id', uid).maybeSingle();
    return row?['role'] as String?;
  }

  Future<void> _deleteAccount() async {
    final s = context.l10nRead;
    final String? username;
    try {
      username = await _myUsername();
    } catch (e) {
      showToast(s.social.deleteAccountFailed.fill([e]), actionLabel: s.social.retry, onAction: _deleteAccount);
      return;
    }
    if (!mounted) return;

    // Refuse before asking them to type anything: the owner account is the
    // only one the database will not delete, and silently failing after the
    // confirmation reads as "the button does nothing".
    try {
      if (await _myRole() == 'owner' && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(AppIcons.lock, color: Theme.of(ctx).colorScheme.error),
            title: Text(s.social.deleteAccountTitle),
            content: Text(s.ownerDeleteBlocked),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx), child: Text(s.close)),
            ],
          ),
        );
        return;
      }
    } catch (_) {
      // Cannot read the role: let the RPC decide.
    }
    if (!mounted) return;

    if (username == null || username.isEmpty) {
      showToast(s.deleteNeedsUsername);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(username: username!),
    );
    if (confirmed != true || !mounted) return;

    // Blocking progress: nothing else should happen mid-deletion.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(s.social.deletingAccount)),
          ]),
        ),
      ),
    );
    try {
      await AccountData.deleteAccount(username);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      showToast(s.social.accountDeleted);
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final msg = '$e'.contains('owner_cannot_delete')
          ? s.social.ownerCannotDelete
          : s.social.deleteAccountFailed.fill(
              [e is PostgrestException ? e.message : e]);
      showToast(msg, actionLabel: s.social.retry, onAction: _deleteAccount);
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    final newer = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    // When newer, the button itself turns into "Update"; only confirm the no-op case.
    if (!newer) {
      showToast(context.l10nRead.upToDate);
    }
  }

  Future<void> _signOut() async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(AppIcons.logout),
        title: Text(s.signOutConfirmTitle),
        content: Text(s.signOutConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.signOut)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _supabase.auth.signOut();
      // Straight to Home as a guest. On the web that is a fresh page load:
      // a `go` from here would be turned into a browser back by this page's
      // onExit (landing on the profile, still showing the old account), and
      // the tabs' cubits would keep the old account's data anyway.
      if (reloadAt('/home')) return;
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        showToast(context.l10nRead.errorWithDetail.fill([e]), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = context.watch<ThemeCubit>().state.appTheme;
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final email = _supabase.auth.currentUser?.email;
    // The student address stops working after graduation; without a
    // backup the account is unrecoverable. Only nag about a real gap.
    final needsBackup = _backupLoaded &&
        isStudentEmail(email) &&
        (_backupEmail == null || _backupEmail!.isEmpty);

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppBackButton(), title: Text(s.settingsTitle)),
      body: PageBody(child: ListView(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.xxl),
            children: [
              // --- APPEARANCE: three named themes, always one row ---
              _SettingsGroup(
                title: s.shell.appearance,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(KSpace.m),
                    child: Row(
                      children: [
                        for (final (i, t) in AppTheme.values.indexed) ...[
                          if (i > 0) const SizedBox(width: KSpace.s),
                          Expanded(child: _themeCard(context, t, t == currentTheme)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // --- LANGUAGE ---
              _SettingsGroup(
                title: s.language,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(KSpace.m),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AppLanguage>(
                        showSelectedIcon: false,
                        segments: [
                          for (final lang in kSupportedLanguages)
                            ButtonSegment(value: lang, label: Text(lang.nativeName)),
                        ],
                        selected: {context.watch<LanguageCubit>().state.language},
                        onSelectionChanged: (sel) =>
                            context.read<LanguageCubit>().changeLanguage(sel.first),
                      ),
                    ),
                  ),
                ],
              ),

              // --- NOTIFICATIONS ---
              _SettingsGroup(
                title: s.notifications,
                children: [
                  ListTile(
                    leading: const Icon(AppIcons.notifications),
                    title: Text(s.notificationsTitle),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: () => context.push('/notifications'),
                  ),
                  // App-settings shortcut only makes sense on mobile
                  if (!kIsWeb)
                    ListTile(
                      leading: const Icon(AppIcons.settings),
                      title: Text(s.fixNotifPermissions),
                      subtitle: Text(s.openSystemSettings),
                      trailing: const Icon(AppIcons.externalLink, size: 18),
                      // Opens the phone's App Settings page
                      onTap: openAppSettings,
                    ),
                ],
              ),

              // --- PRIVACY & DATA ---
              _SettingsGroup(
                title: s.social.privacyData,
                children: [
                  ListTile(
                    leading: const Icon(AppIcons.lock),
                    title: Text(s.social.privacyPolicy),
                    subtitle: Text(s.social.privacyPolicySub),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: () => context.goPrivacyPolicy(),
                  ),
                  ListTile(
                    leading: const Icon(AppIcons.sparkle),
                    title: Text(s.brand.openSourceCredits),
                    subtitle: Text(s.brand.openSourceCreditsSub),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: AppStrings.appName,
                      applicationIcon: const Padding(
                        padding: EdgeInsets.all(KSpace.s),
                        child: AppLogo(size: 56),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: _exporting
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : const Icon(AppIcons.download),
                    title: Text(s.social.downloadMyData),
                    subtitle: Text(_exporting
                        ? s.social.preparingExport
                        : s.social.downloadMyDataSub),
                    enabled: !_exporting,
                    onTap: _exportData,
                  ),
                ],
              ),

              // --- MODERATION (admins and the owner only) ---
              FutureBuilder<bool>(
                future: ModerationService.isAdmin(),
                builder: (context, snap) => snap.data == true
                    ? _SettingsGroup(
                        title: context.l10n.mod.moderation,
                        children: [
                          ListTile(
                            leading: const Icon(AppIcons.moderation),
                            title: Text(context.l10n.mod.moderation),
                            subtitle: Text(context.l10n.mod.adminConsoleSub),
                            trailing: const Icon(AppIcons.chevronRight),
                            onTap: () => context.push('/admin'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),

              // --- ACCOUNT ---
              _SettingsGroup(
                title: s.shell.account,
                children: [
                  if (email != null)
                    ListTile(
                      leading: const Icon(AppIcons.email),
                      title: Text(email),
                    ),
                  ListTile(
                    leading: const Icon(AppIcons.lock),
                    title: Text(s.account.backupEmail),
                    subtitle: Text((_backupEmail == null || _backupEmail!.isEmpty)
                        ? s.account.backupEmailNone
                        : _backupEmail!),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: () async {
                      await context.push('/profile/edit');
                      if (mounted) _loadBackupEmail();
                    },
                  ),
                  if (needsBackup)
                    ListTile(
                      leading: Icon(AppIcons.warning, color: scheme.tertiary),
                      title: Text(s.account.backupNudgeTitle,
                          style: TextStyle(color: scheme.tertiary)),
                      subtitle: Text(s.account.backupNudgeBody.fill([email ?? ''])),
                      isThreeLine: true,
                      onTap: () async {
                        await context.push('/profile/edit');
                        if (mounted) _loadBackupEmail();
                      },
                    ),
                  if (_verifyEnabled)
                    ListTile(
                      leading: Icon(
                        AppIcons.verified,
                        color: _verification?.isVerified == true
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(s.verifyTitle),
                      subtitle: Text(_verificationLabel(s)),
                      trailing: const Icon(AppIcons.chevronRight),
                      onTap: () async {
                        await showVerifySheet(context);
                        if (mounted) _loadVerification();
                      },
                    ),
                  ListTile(
                    leading: const Icon(AppIcons.info),
                    title: Text(UpdateService.isSupported
                        ? s.versionBuildLabel.fill([UpdateService.appVersion, UpdateService.buildId])
                        : s.versionLabel.fill([UpdateService.appVersion])),
                    trailing: !UpdateService.isSupported
                        ? null
                        : ValueListenableBuilder<bool>(
                            valueListenable: UpdateService.instance.updateAvailable,
                            builder: (context, available, _) => available
                                ? FilledButton(
                                    onPressed: UpdateService.instance.applyUpdate,
                                    child: Text(s.updateNow),
                                  )
                                : TextButton(
                                    onPressed: _checkingUpdate ? null : _checkForUpdates,
                                    child: _checkingUpdate
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(s.checkForUpdates),
                                  ),
                          ),
                  ),
                ],
              ),

              // --- DESTRUCTIVE, last and in the error colour ---
              const SizedBox(height: KSpace.xl),
              _SettingsGroup(
                children: [
                  ListTile(
                    leading: Icon(AppIcons.logout, color: scheme.error),
                    title: Text(s.signOut, style: TextStyle(color: scheme.error)),
                    onTap: _signOut,
                  ),
                  ListTile(
                    leading: Icon(AppIcons.delete, color: scheme.error),
                    title: Text(s.social.deleteAccount,
                        style: TextStyle(color: scheme.error)),
                    subtitle: Text(s.social.deleteAccountSub),
                    onTap: _deleteAccount,
                  ),
                ],
              ),
            ],
          )),
    );
  }

  /// One theme: a mini preview (background, primary, accent) + name.
  /// Sized by its Expanded parent so all three always fit one row.
  Widget _themeCard(BuildContext context, AppTheme theme, bool selected) {
    final spec = kThemeSpecs[theme]!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: spec.displayName,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.read<ThemeCubit>().changeTheme(theme),
        borderRadius: KRadius.card,
        child: AnimatedContainer(
          duration: KMotion.of(context).fast,
          padding: const EdgeInsets.all(KSpace.s),
          decoration: BoxDecoration(
            borderRadius: KRadius.card,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview tile in the theme's own colours.
              AspectRatio(
                aspectRatio: 1.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: spec.background,
                    borderRadius: KRadius.small,
                    border: Border.all(color: spec.border),
                  ),
                  padding: const EdgeInsets.all(KSpace.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 8,
                        width: 36,
                        decoration: BoxDecoration(
                            color: spec.primary, borderRadius: KRadius.pill),
                      ),
                      const SizedBox(height: KSpace.xs),
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                            color: spec.text.withValues(alpha: 0.25),
                            borderRadius: KRadius.pill),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(radius: 6, backgroundColor: spec.gold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: KSpace.s),
              Row(
                children: [
                  Expanded(
                    child: Text(spec.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge),
                  ),
                  if (selected)
                    Icon(AppIcons.success, size: 16, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section title over one rounded group of rows.
class _SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const _SettingsGroup({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: KSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: KSpace.xs, bottom: KSpace.s),
              child: Semantics(
                header: true,
                child: Text(title!,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.primary)),
              ),
            ),
          Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(borderRadius: KRadius.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: KSpace.l, color: scheme.outlineVariant),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Strong confirmation: the user has to type their username.
class _DeleteAccountDialog extends StatefulWidget {
  final String username;
  const _DeleteAccountDialog({required this.username});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final ok = AccountData.confirms(_ctrl.text, widget.username);

    return AlertDialog(
      icon: Icon(AppIcons.warning, color: scheme.error),
      title: Text(s.social.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.social.deleteAccountBody),
          const SizedBox(height: KSpace.l),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.social.typeUsernameToConfirm.fill(['@${widget.username}']),
              prefixText: '@',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text(s.social.deleteForever),
        ),
      ],
    );
  }
}
