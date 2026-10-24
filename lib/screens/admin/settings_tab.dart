import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/access_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/admin_unlock.dart';
import '../../services/moderation_service.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';

/// Owner-only editor for moderation_settings (RLS lets only the owner
/// update; every change is logged with before/after values).
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

/// (column, minimum)
const _intFields = <(String, int)>[
  ('auto_hide_report_count', 1),
  ('strike_window_days', 1),
  ('strikes_for_auto_restriction', 1),
  ('auto_restriction_days', 1),
  ('new_account_hours', 0),
  ('new_account_posts_per_hour', 1),
  ('new_account_comments_per_hour', 1),
  ('new_account_listings_per_hour', 1),
  ('new_account_events_per_hour', 1),
  ('reporter_min_resolved', 1),
  ('max_active_pins_per_club', 0),
  ('pin_duration_days', 1),
];

class _SettingsTabState extends State<SettingsTab> with AutomaticKeepAliveClientMixin {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {
    for (final f in _intFields) f.$1: TextEditingController(),
    'reporter_max_dismissed_ratio': TextEditingController(),
  };
  Set<String> _priority = {};
  late Future<void> _loading = _load();
  bool _saving = false;
  bool _pinConfigured = false;
  bool _pinSaving = false;

  /// Owner-only student-verification switch (off unless turned on).
  bool _verification = false;
  bool _verificationSaving = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() async {
    final s = await ModerationService.settings();
    for (final e in _ctrls.entries) {
      e.value.text = '${s[e.key] ?? ''}';
    }
    _priority = {...((s['priority_categories'] as List?) ?? const []).cast<String>()};
    _pinConfigured = await ModerationService.adminPinConfigured();
    try {
      final policy = await ModerationService.accessPolicy();
      _verification = policy['verification_enabled'] == true;
    } catch (_) {
      // Fail closed: an unread policy must not look enabled.
      _verification = false;
    }
  }

  Future<void> _toggleVerification(bool value) async {
    final s = context.l10n;
    if (value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.verifyConfirmTitle),
          content: Text(s.verifyConfirmBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.verifyConfirmAction)),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _verificationSaving = true);
    try {
      await ModerationService.setVerificationEnabled(value);
      if (!mounted) return;
      setState(() => _verification = value);
      showModSnack(context, value ? s.verifyOn : s.verifyOff);
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _verificationSaving = false);
    }
  }

  Future<void> _setPin() async {
    final m = modStrings(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _AdminPinDialog(),
    );
    if (pin == null) return;
    setState(() => _pinSaving = true);
    try {
      await ModerationService.setAdminPin(pin);
      AdminUnlock.instance.setConfigured(true);
      AdminUnlock.instance.startSession();
      if (!mounted) return;
      setState(() => _pinConfigured = true);
      showModSnack(context, m.adminPinSaved);
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _pinSaving = false);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _label(ModerationStrings m, String key) => switch (key) {
        'auto_hide_report_count' => m.sAutoHide,
        'strike_window_days' => m.sStrikeWindow,
        'strikes_for_auto_restriction' => m.sStrikes,
        'auto_restriction_days' => m.sAutoRestrictDays,
        'new_account_hours' => m.sNewHours,
        'new_account_posts_per_hour' => m.sNewPosts,
        'new_account_comments_per_hour' => m.sNewComments,
        'new_account_listings_per_hour' => m.sNewListings,
        'new_account_events_per_hour' => m.sNewEvents,
        'reporter_min_resolved' => m.sReporterMin,
        'reporter_max_dismissed_ratio' => m.sReporterRatio,
        'max_active_pins_per_club' => m.sMaxPins,
        _ => m.sPinDays,
      };

  Future<void> _save() async {
    final m = modStrings(context);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{
        for (final f in _intFields) f.$1: int.parse(_ctrls[f.$1]!.text.trim()),
        'reporter_max_dismissed_ratio':
            double.parse(_ctrls['reporter_max_dismissed_ratio']!.text.trim()),
        'priority_categories': _priority.toList(),
      };
      final ok = await ModerationService.saveSettings(values);
      if (!mounted) return;
      showModSnack(context, ok ? m.settingsSaved : m.settingsNotSaved, error: !ok);
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(modErrorText(context, snap.error!,
                    fallback: context.l10n.connectionError)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _loading = _load()),
                  child: Text(m.retry),
                ),
              ],
            ),
          );
        }
        return Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(ModIcons.lock, size: 20),
                          const SizedBox(width: 8),
                          Text(m.adminPin, style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_pinConfigured ? m.adminPinConfigured : m.adminPinNotConfigured,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pinSaving ? null : _setPin,
                        icon: const Icon(ModIcons.settings, size: 18),
                        label: Text(_pinConfigured ? m.adminPinChange : m.adminPinSet),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ---- student verification (the switch that gates joining,
              // creating events and selling) ----
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(ModIcons.verified, size: 20),
                          const SizedBox(width: 8),
                          Text(context.l10n.verifySectionTitle,
                              style: Theme.of(context).textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(context.l10n.verifySwitchBody,
                          style: Theme.of(context).textTheme.bodySmall),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _verification,
                        onChanged:
                            _verificationSaving ? null : _toggleVerification,
                        title: Text(context.l10n.verifySwitchTitle),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final f in _intFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: _ctrls[f.$1],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: _label(m, f.$1), border: const OutlineInputBorder()),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return n == null || n < f.$2 ? m.mustBeAtLeast.fill([f.$2]) : null;
                    },
                  ),
                ),
              TextFormField(
                controller: _ctrls['reporter_max_dismissed_ratio'],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: _label(m, 'reporter_max_dismissed_ratio'),
                    border: const OutlineInputBorder()),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  return n == null || n < 0 || n > 1 ? m.mustBeRatio : null;
                },
              ),
              const SizedBox(height: 16),
              Text(m.sPriority, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kReportCategories)
                    FilterChip(
                      label: Text(m.categoryLabel(c)),
                      selected: _priority.contains(c),
                      onSelected: (v) =>
                          setState(() => v ? _priority.add(c) : _priority.remove(c)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(ModIcons.saveFile),
                label: Text(m.save),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// New admin PIN + confirmation. Pops the PIN when valid.
class _AdminPinDialog extends StatefulWidget {
  const _AdminPinDialog();

  @override
  State<_AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<_AdminPinDialog> {
  final _form = GlobalKey<FormState>();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, _pin.text);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    return AlertDialog(
      title: Text(m.adminPin),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _pin,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: m.adminPin),
              validator: (v) => (v ?? '').length < 4 ? m.adminPinTooShort : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(labelText: m.adminPinConfirm),
              validator: (v) => v != _pin.text ? m.adminPinMismatch : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(m.cancel)),
        FilledButton(onPressed: _save, child: Text(m.save)),
      ],
    );
  }
}
