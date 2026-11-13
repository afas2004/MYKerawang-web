import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/notification_strings.dart';
import '../language_cubit.dart';
import '../services/notification_prefs.dart';
import '../services/push_service.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../widgets/app_toast.dart';
import '../widgets/brand/brand.dart';
import '../widgets/push_prompt.dart';

/// Settings → Notifications: what reaches the phone, what stays in the bell,
/// quiet hours, and which devices get pushes. Saved in
/// notification_settings (see 20261114000100_notifications_v2.sql), which
/// the database and the push sender both read.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotificationPrefs? _prefs;
  PushState? _push;
  List<Map<String, dynamic>> _devices = const [];
  String? _thisToken;

  @override
  void initState() {
    super.initState();
    PushService.instance.changed.addListener(_loadPush);
    _load();
  }

  @override
  void dispose() {
    PushService.instance.changed.removeListener(_loadPush);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await NotificationPrefs.load();
    if (mounted) setState(() => _prefs = p);
    await _loadPush();
  }

  Future<void> _loadPush() async {
    final st = await PushService.instance.state();
    List<Map<String, dynamic>> devices = const [];
    try {
      devices = List<Map<String, dynamic>>.from(await Supabase.instance.client
          .from('push_tokens')
          .select('token, label, created_at')
          .order('created_at', ascending: false));
    } catch (_) {}
    final mine = await PushService.instance.currentToken();
    if (mounted) {
      setState(() {
        _push = st;
        _devices = devices;
        _thisToken = mine;
      });
    }
  }

  Future<void> _save(NotificationPrefs next) async {
    final before = _prefs;
    setState(() => _prefs = next);
    try {
      await next.save();
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      showToast(context.l10nRead.nsSaveFailed, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final prefs = _prefs;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        leading: const AppBackButton(),
        title: Text(s.nsTitle),
      ),
      body: PageBody(
        child: prefs == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: KSpace.xxl),
                children: [
                  _deviceStatus(context),
                  _section(context, s.nsWhatToSend),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(KSpace.l, 0, KSpace.l, KSpace.s),
                    child: Text(s.nsLegend,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  _group(context, [
                    _level(context, prefs, 'reminders', s.nsReminders, s.nsRemindersSub),
                    _level(context, prefs, 'event_changes', s.nsEventChanges, s.nsEventChangesSub),
                    _level(context, prefs, 'comments', s.nsComments, s.nsCommentsSub),
                    _level(context, prefs, 'mentions', s.nsMentions, s.nsMentionsSub),
                    _level(context, prefs, 'form_answers', s.nsFormAnswers, s.nsFormAnswersSub),
                    _level(context, prefs, 'event_joins', s.nsJoins, s.nsJoinsSub),
                    _level(context, prefs, 'follows', s.nsFollows, null, phone: false),
                    _level(context, prefs, 'new_events', s.nsNewEvents, null),
                    ListTile(
                      title: Text(s.nsAccount),
                      subtitle: Text(s.nsAccountSub),
                      trailing: const Switch(value: true, onChanged: null),
                    ),
                  ]),
                  _section(context, s.nsQuiet),
                  _group(context, [
                    SwitchListTile(
                      secondary: const Icon(AppIcons.quietHours),
                      title: Text(s.nsQuiet),
                      subtitle: Text(s.nsQuietSub),
                      value: prefs.quietEnabled,
                      onChanged: (v) => _save(prefs.copyWith(quietEnabled: v)),
                    ),
                    if (prefs.quietEnabled) ...[
                      _timeRow(context, s.nsFrom, prefs.quietStart,
                          (t) => _save(prefs.copyWith(quietStart: t))),
                      _timeRow(context, s.nsUntil, prefs.quietEnd,
                          (t) => _save(prefs.copyWith(quietEnd: t))),
                    ],
                  ]),
                  if (_devices.isNotEmpty) ...[
                    _section(context, s.nsDevices),
                    _group(context, [
                      for (final d in _devices)
                        ListTile(
                          leading: const Icon(AppIcons.smartphone),
                          title: Text(d['token'] == _thisToken
                              ? '${s.nsThisDevice} · ${d['label'] ?? ''}'
                              : '${d['label'] ?? s.nsThisDevice}'),
                          subtitle: Text(formatDateShort(d['created_at'])),
                          trailing: TextButton(
                            onPressed: () => _removeDevice(d['token'] as String),
                            child: Text(s.nsRemove),
                          ),
                        ),
                    ]),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(KSpace.l),
                    child: OutlinedButton.icon(
                      icon: const Icon(AppIcons.notifications),
                      label: Text(s.nsOpenList),
                      onPressed: () => context.push('/notifications'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _removeDevice(String token) async {
    if (token == _thisToken) {
      await PushService.instance.disableThisDevice();
    } else {
      try {
        await Supabase.instance.client.from('push_tokens').delete().eq('token', token);
      } catch (_) {}
    }
    await _loadPush();
  }

  Widget _deviceStatus(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final st = _push;
    if (st == null) return const SizedBox(height: KSpace.l);

    final (IconData icon, String title, String? body, Color bg, Color fg, Widget? action) = switch (st) {
      PushState.on => (
          AppIcons.check, s.nsDeviceOn, null, scheme.secondaryContainer, scheme.onSecondaryContainer,
          TextButton(onPressed: PushService.instance.disableThisDevice, child: Text(s.nsTurnOffDevice)),
        ),
      PushState.off => (
          AppIcons.notificationsOff, s.nsDeviceOff, s.nsDeviceOffBody, scheme.surfaceContainerHigh,
          scheme.onSurface,
          FilledButton(onPressed: () => turnOnPush(context.l10nRead), child: Text(s.pushTurnOn)),
        ),
      PushState.blocked => (
          AppIcons.warning, s.nsBlocked, s.nsBlockedBody, scheme.errorContainer, scheme.onErrorContainer, null,
        ),
      PushState.iosNeedsInstall => (
          AppIcons.iosShare, s.nsIos, null, scheme.surfaceContainerHigh, scheme.onSurface,
          TextButton(onPressed: () => showPushSheet(context), child: Text(s.pushGotIt)),
        ),
      PushState.unsupported => (
          AppIcons.info, s.nsUnsupported, null, scheme.surfaceContainerHigh, scheme.onSurface, null,
        ),
      PushState.notConfigured => (
          AppIcons.info, s.nsComingSoon, null, scheme.surfaceContainerHigh, scheme.onSurface, null,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, 0),
      child: Container(
        padding: const EdgeInsets.all(KSpace.m),
        decoration: BoxDecoration(color: bg, borderRadius: KRadius.card),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: KSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg)),
                  if (body != null) ...[
                    const SizedBox(height: 2),
                    Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg)),
                  ],
                  if (action != null) ...[const SizedBox(height: KSpace.s), action],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xl, KSpace.l, KSpace.s),
        child: Semantics(
          header: true,
          child: Text(title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant, letterSpacing: .6)),
        ),
      );

  Widget _group(BuildContext context, List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ]),
        ),
      );

  Widget _level(BuildContext context, NotificationPrefs prefs, String key, String title,
      String? sub, {bool phone = true}) {
    final s = context.l10n;
    final value = prefs.level(key);
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final picker = SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        if (phone) ButtonSegment(value: 'push', label: Text(s.nsPhone)),
        ButtonSegment(value: 'bell', label: Text(s.nsBell)),
        ButtonSegment(value: 'off', label: Text(s.nsOff)),
      ],
      selected: {value},
      onSelectionChanged: (v) => _save(prefs.withLevel(key, v.first)),
    );
    if (!narrow) {
      return ListTile(
        title: Text(title),
        subtitle: sub == null ? null : Text(sub),
        trailing: picker,
      );
    }
    // Phones: the picker goes under the label so neither gets squeezed.
    return Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          if (sub != null)
            Text(sub,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: KSpace.s),
          picker,
        ],
      ),
    );
  }

  Widget _timeRow(BuildContext context, String label, TimeOfDay value, ValueChanged<TimeOfDay> onPick) =>
      ListTile(
        title: Text(label),
        trailing: Text(value.format(context),
            style: Theme.of(context).textTheme.titleSmall),
        onTap: () async {
          final t = await showTimePicker(context: context, initialTime: value);
          if (t != null) onPick(t);
        },
      );
}

String formatDateShort(dynamic raw) {
  final t = DateTime.tryParse('$raw')?.toLocal();
  return t == null ? '' : '${t.day}/${t.month}/${t.year}';
}
