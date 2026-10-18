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

  final _supabase = Supabase.instance.client;

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
    return Scaffold(
      appBar: appBarConstrained(context, title: Text(s.settingsTitle)),
      body: PageBody(child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- THEME (three named moods, DESIGN_SPEC §2) ---
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(s.theme),
              ),
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: AppTheme.values
                      .map((t) => _themeCard(context, t, t == currentTheme))
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),

              // --- LANGUAGE (belongs with Appearance, not Event Alerts) ---
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(s.language),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

              // App-settings shortcut only makes sense on mobile
              if (!kIsWeb) ...[
                const Divider(height: 40),
                _sectionHeader(s.notifications),
                ListTile(
                  leading: Icon(Icons.settings_applications, color: theme.colorScheme.primary),
                  title: Text(s.fixNotifPermissions),
                  subtitle: Text(s.openSystemSettings),
                  onTap: () async {
                    // This forces the phone's App Settings page to open
                    await openAppSettings();
                  },
                ),
              ],

              const Divider(height: 40),
              // Preview card removed — it didn't show anything the live
              // theme cards don't already demonstrate (H4/14.7).
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  // Theme error colour — the old red[50] fill was unreadable
                  // on Songket Noir (verified in browser).
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(color: Theme.of(context).colorScheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(s.signOut, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                    UpdateService.isSupported
                        ? s.versionBuildLabel.fill([UpdateService.appVersion, UpdateService.buildId])
                        : s.versionLabel.fill([UpdateService.appVersion]),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              if (UpdateService.isSupported)
                Center(
                  child: ValueListenableBuilder<bool>(
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

  Widget _sectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 16),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

