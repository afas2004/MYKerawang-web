import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
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

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() async {
    final s = await ModerationService.settings();
    for (final e in _ctrls.entries) {
      e.value.text = '${s[e.key] ?? ''}';
    }
    _priority = {...((s['priority_categories'] as List?) ?? const []).cast<String>()};
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
