import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/theme_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../services/account_data.dart';
import 'privacy_policy_screen.dart';
import 'profile_cubit.dart';
import '../utils/responsive.dart';
import '../services/update_service.dart';

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

  final _supabase = Supabase.instance.client;

  // ---- Privacy & data (PDPA) ------------------------------------------

  Future<void> _exportData() async {
    final s = context.l10nRead;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      await AccountData.exportToFile();
      messenger.showSnackBar(SnackBar(content: Text(s.social.exportReady)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(s.social.exportFailed.fill([e])),
        action: SnackBarAction(label: s.social.retry, onPressed: _exportData),
      ));
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

  Future<void> _deleteAccount() async {
    final s = context.l10nRead;
    final messenger = ScaffoldMessenger.of(context);
    final String? username;
    try {
      username = await _myUsername();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(s.social.deleteAccountFailed.fill([e])),
        action: SnackBarAction(label: s.social.retry, onPressed: _deleteAccount),
      ));
      return;
    }
    if (!mounted || username == null) return;

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
      messenger.showSnackBar(SnackBar(content: Text(s.social.accountDeleted)));
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final msg = '$e'.contains('owner_cannot_delete')
          ? s.social.ownerCannotDelete
          : s.social.deleteAccountFailed.fill(
              [e is PostgrestException ? e.message : e]);
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: s.social.retry, onPressed: _deleteAccount),
      ));
    }
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    final newer = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);
    // When newer, the button itself turns into "Update"; only confirm the no-op case.
    if (!newer) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10nRead.upToDate)));
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
      // The router's auth redirect also catches this; go explicitly so the
      // whole stack (including pushed routes) is replaced.
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10nRead.errorWithDetail.fill([e]),
                style: TextStyle(color: scheme.onError)),
            backgroundColor: scheme.error,
          ),
        );
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

    return Scaffold(
      appBar: appBarConstrained(context, title: Text(s.settingsTitle)),
      body: PageBody(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // --- APPEARANCE: three named moods (DESIGN_SPEC §2) ---
              _SettingsGroup(
                title: s.shell.appearance,
                icon: Icons.palette_outlined,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SizedBox(
                      height: 110,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: AppTheme.values
                            .map((t) => _themeCard(context, t, t == currentTheme))
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),

              // --- LANGUAGE ---
              _SettingsGroup(
                title: s.language,
                icon: Icons.translate,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: SegmentedButton<AppLanguage>(
                      segments: [
                        for (final lang in kSupportedLanguages)
                          ButtonSegment(value: lang, label: Text(lang.nativeName)),
                      ],
                      selected: {context.watch<LanguageCubit>().state.language},
                      onSelectionChanged: (sel) =>
                          context.read<LanguageCubit>().changeLanguage(sel.first),
                    ),
                  ),
                ],
              ),

              // --- NOTIFICATIONS ---
              _SettingsGroup(
                title: s.notifications,
                icon: Icons.notifications_outlined,
                children: [
                  ListTile(
                    leading: const Icon(Icons.inbox_outlined),
                    title: Text(s.notificationsTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/notifications'),
                  ),
                  // App-settings shortcut only makes sense on mobile
                  if (!kIsWeb)
                    ListTile(
                      leading: const Icon(Icons.settings_applications_outlined),
                      title: Text(s.fixNotifPermissions),
                      subtitle: Text(s.openSystemSettings),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      // Opens the phone's App Settings page
                      onTap: openAppSettings,
                    ),
                ],
              ),

              // --- PRIVACY & DATA ---
              _SettingsGroup(
                title: s.social.privacyData,
                icon: Icons.shield_outlined,
                children: [
                  ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: Text(s.social.privacyPolicy),
                    subtitle: Text(s.social.privacyPolicySub),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                  ),
                  ListTile(
                    leading: _exporting
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(2),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : const Icon(Icons.download_outlined),
                    title: Text(s.social.downloadMyData),
                    subtitle: Text(_exporting
                        ? s.social.preparingExport
                        : s.social.downloadMyDataSub),
                    enabled: !_exporting,
                    onTap: _exportData,
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                    title: Text(s.social.deleteAccount,
                        style: TextStyle(color: scheme.error)),
                    subtitle: Text(s.social.deleteAccountSub),
                    onTap: _deleteAccount,
                  ),
                ],
              ),

              // --- ACCOUNT ---
              _SettingsGroup(
                title: s.shell.account,
                icon: Icons.person_outline,
                children: [
                  if (email != null)
                    ListTile(
                      leading: const Icon(Icons.alternate_email),
                      title: Text(email),
                    ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(UpdateService.isSupported
                        ? s.versionBuildLabel.fill([UpdateService.appVersion, UpdateService.buildId])
                        : s.versionLabel.fill([UpdateService.appVersion])),
                    trailing: !UpdateService.isSupported
                        ? null
                        : ValueListenableBuilder<bool>(
                            valueListenable: UpdateService.instance.updateAvailable,
                            builder: (context, available, _) => available
                                ? FilledButton.icon(
                                    onPressed: UpdateService.instance.applyUpdate,
                                    icon: const Icon(Icons.system_update),
                                    label: Text(s.updateNow),
                                  )
                                : TextButton.icon(
                                    onPressed: _checkingUpdate ? null : _checkForUpdates,
                                    icon: _checkingUpdate
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.refresh),
                                    label: Text(s.checkForUpdates),
                                  ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: OutlinedButton.icon(
                      onPressed: _signOut,
                      // Theme error colour — readable on Songket Noir too.
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.logout),
                      label: Text(s.signOut),
                    ),
                  ),
                ],
              ),
            ],
          )),
    );
  }

  Widget _themeCard(BuildContext context, AppTheme theme, bool selected) {
    final spec = kThemeSpecs[theme]!;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: () => context.read<ThemeCubit>().changeTheme(theme),
        borderRadius: kerawangCut,
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: spec.surface,
            borderRadius: kerawangCut,
            border: Border.all(
              color: selected ? scheme.primary : spec.border,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _swatch(spec.background),
                  _swatch(spec.primary),
                  _swatch(spec.gold),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ],
              ),
              const Spacer(),
              Text(spec.displayName,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: spec.text)),
              Text(_tagline(context, theme),
                  style: TextStyle(
                      fontSize: 11,
                      color: spec.text.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(Color c) => Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );

  String _tagline(BuildContext context, AppTheme theme) {
    final s = context.l10n;
    return switch (theme) {
      AppTheme.kampus => s.taglineKampus,
      AppTheme.istana => s.taglineIstana,
      AppTheme.noir => s.taglineNoir,
    };
  }
}

/// One titled card of settings rows.
class _SettingsGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsGroup(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ),
          Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: kerawangCut,
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
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
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(s.social.deleteAccountTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.social.deleteAccountBody),
          const SizedBox(height: 16),
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
