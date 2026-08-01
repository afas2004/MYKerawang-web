import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_screen.dart';
import 'package:mykerawang/theme_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/responsive.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Toggle states
  bool _newEvents = true;
  bool _eventReminders = true;
  bool _marketplaceUpdates = false;
  bool _isLoading = true;

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 1. Fetch current settings from Supabase
  Future<void> _loadSettings() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('notify_new_events, notify_reminders, notify_marketplace')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _newEvents = profile['notify_new_events'] ?? true;
          _eventReminders = profile['notify_reminders'] ?? true;
          _marketplaceUpdates = profile['notify_marketplace'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Save changes to Supabase instantly
  Future<void> _updateSetting(String column, bool value) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('profiles').update({column: value}).eq('id', user.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving setting: $e")));
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error signing out: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = context.watch<ThemeCubit>().state.appTheme;
    return Scaffold(
      appBar: appBarConstrained(context, title: Text(context.l10n.settingsTitle)),
      body: PageBody(child: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- THEME (three named moods, DESIGN_SPEC §2) ---
              const ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text("Theme"),
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
                title: Text(context.l10n.language),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<AppLanguage>(
                  segments: const [
                    ButtonSegment(value: AppLanguage.en, label: Text("English")),
                    ButtonSegment(value: AppLanguage.ms, label: Text("B. Melayu")),
                    ButtonSegment(value: AppLanguage.ja, label: Text("日本語")),
                  ],
                  selected: {context.watch<LanguageCubit>().state.language},
                  onSelectionChanged: (sel) =>
                      context.read<LanguageCubit>().changeLanguage(sel.first),
                ),
              ),

              const Divider(height: 40),
              _sectionHeader("Event Alerts"),

              SwitchListTile(
                title: const Text("New Events"),
                subtitle: const Text("Get notified when new events are posted"),
                value: _newEvents,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) {
                  setState(() => _newEvents = v);
                  _updateSetting('notify_new_events', v); // Save to DB
                },
              ),
              SwitchListTile(
                title: const Text("Reminders"),
                subtitle: const Text("1 hour before events you joined"),
                value: _eventReminders,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) {
                  setState(() => _eventReminders = v);
                  _updateSetting('notify_reminders', v); // Save to DB
                },
              ),
              // App-settings shortcut only makes sense on mobile
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.settings_applications, color: Colors.orange),
                  title: const Text("Fix Notification Permissions"),
                  subtitle: const Text("Open system settings to enable"),
                  onTap: () async {
                    // This forces the phone's App Settings page to open
                    await openAppSettings();
                  },
                ),
              
              const Divider(height: 40),
              _sectionHeader("Marketplace"),
              SwitchListTile(
                title: const Text("Price Drops"),
                subtitle: const Text("Notify when saved items drop in price"),
                value: _marketplaceUpdates,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) {
                  setState(() => _marketplaceUpdates = v);
                  _updateSetting('notify_marketplace', v); // Save to DB
                },
              ),
              
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
                  child: const Text("Sign Out", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text("Version 1.0.0",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              Text(spec.tagline,
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
          border: Border.all(color: Colors.black12),
        ),
      );

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 16),
      child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}

