import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/access_strings.dart';
import '../../language_cubit.dart';
import '../../services/form_service.dart';
import '../../services/share_service.dart';
import '../../utils/attendance_rules.dart';
import '../../utils/csv_saver.dart';
import '../../utils/feedback.dart';
import '../../utils/form_csv.dart';
import '../../widgets/brand/brand.dart';

/// The door, while it is open.
///
/// One screen with two states: **live** (the rotating code, the running count
/// and the last person in) and **closed** (the totals and the exports). It is
/// the organiser's screen only — the student path is the QR, which is a URL.
class AttendanceLiveScreen extends StatefulWidget {
  final String eventId;
  final String title;

  /// Whether the KI form was included when attendance was started.
  final bool withKi;

  /// The open form, when there is one; the KI export needs it.
  final String? formId;

  const AttendanceLiveScreen({
    super.key,
    required this.eventId,
    required this.title,
    this.withKi = false,
    this.formId,
  });

  @override
  State<AttendanceLiveScreen> createState() => _AttendanceLiveScreenState();
}

class _AttendanceLiveScreenState extends State<AttendanceLiveScreen> {
  static const _refresh = Duration(seconds: 10);

  final _db = Supabase.instance.client;

  Timer? _timer;
  RealtimeChannel? _channel;
  String? _token;
  String? _error;
  int _count = 0;
  String? _latestName;
  bool _closed = false;
  bool _ending = false;
  int _kiResponses = 0;

  @override
  void initState() {
    super.initState();
    _refreshToken();
    _refreshCounts();
    _timer = Timer.periodic(_refresh, (_) => _refreshToken());
    _watch();
  }

  @override
  void dispose() {
    _timer?.cancel();
    final channel = _channel;
    if (channel != null) _db.removeChannel(channel);
    super.dispose();
  }

  /// Every check-in, live. Realtime is best-effort (a project without
  /// replication simply never fires), so the values are always re-read.
  void _watch() {
    _channel = _db
        .channel('attendance-${widget.eventId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'event_attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'event_id',
            value: widget.eventId,
          ),
          callback: (_) => _refreshCounts(),
        )
        .subscribe();
  }

  Future<void> _refreshToken() async {
    if (_closed) return;
    try {
      final rows =
          await _db.rpc('event_checkin_token', params: {'p_event_id': widget.eventId});
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (!mounted || _closed) return;
      setState(() {
        _token = list.isEmpty ? null : '${list.first['token']}';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _refreshCounts() async {
    try {
      final n = await _db
          .from('event_attendance')
          .count(CountOption.exact)
          .eq('event_id', widget.eventId);

      // Who was last in. profiles is readable by signed-in users, and this
      // screen only exists for the organiser.
      final last = await _db
          .from('event_attendance')
          .select('checked_in_at, profiles(display_name)')
          .eq('event_id', widget.eventId)
          .order('checked_in_at', ascending: false)
          .limit(1) as List;

      String? name;
      if (last.isNotEmpty) {
        final profile = (last.first as Map)['profiles'];
        if (profile is Map) name = '${profile['display_name'] ?? ''}';
      }

      if (!mounted) return;
      setState(() {
        _count = n;
        if (name != null && name.trim().isNotEmpty) {
          _latestName = shortAttendeeName(name);
        }
      });
    } catch (e) {
      debugPrint('Attendance refresh failed: $e');
    }
  }

  Future<void> _end() async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.evEndConfirmTitle),
        content: Text(s.evEndConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.evEndAttendance)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _ending = true);
    _timer?.cancel();
    final channel = _channel;
    if (channel != null) {
      await _db.removeChannel(channel);
      _channel = null;
    }

    // The KI total is only meaningful when the form was part of this session.
    if (widget.withKi && widget.formId != null) {
      try {
        final a = await FormService.instance.analysis(widget.formId!);
        if (mounted) setState(() => _kiResponses = a.peserta + a.penganjur);
      } catch (e) {
        debugPrint('KI count unavailable: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _closed = true;
      _ending = false;
    });
  }

  Future<void> _export({required bool attendance, required bool ki}) async {
    final s = context.l10nRead;
    try {
      if (attendance) {
        final rows = await _db
            .rpc('event_attendance_list', params: {'p_event_id': widget.eventId});
        final csv = attendanceCsv(List<Map<String, dynamic>>.from(rows as List));
        await saveCsv(csv, flowFileName('attendance', widget.title));
      }
      if (ki && widget.formId != null) {
        final view = await FormService.instance.load(widget.formId!);
        final responses = await FormService.instance.responses(widget.formId!);
        await saveCsv(
          responsesCsv(view.doc.fields, responses),
          flowFileName('ki', widget.title),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is! StateError) {
        showErrorWithRetry(context, e, onRetry: () => _export(attendance: attendance, ki: ki));
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.evExportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final url = _token == null
        ? null
        : ShareService.absoluteUrl('/event/${widget.eventId}/checkin?t=$_token');

    return Scaffold(
      appBar: AppBar(
        title: Text(_closed ? s.evAttendanceClosed : s.evTakeAttendance),
        leading: _closed
            ? IconButton(
                tooltip: s.evDone,
                icon: const Icon(AppIcons.close),
                onPressed: () => Navigator.of(context).pop(true),
              )
            : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _closed
                ? _summary(context)
                : _live(context, url),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- live

  Widget _live(BuildContext context, String? url) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      key: const ValueKey('live'),
      padding: const EdgeInsets.all(KSpace.l),
      children: [
        Text(widget.title,
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: KSpace.xs),
        Text(
          widget.withKi ? s.evAddKiHint : s.evAttendanceHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: KSpace.l),
        if (url != null)
          Center(
            child: KCard(
              padding: const EdgeInsets.all(KSpace.m),
              child: QrImageView(
                data: url,
                size: 260,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
          )
        else if (_error != null)
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),

        const SizedBox(height: KSpace.l),
        // The number is the whole point of standing at the door with this open,
        // so it counts up rather than snapping.
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: _count),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        Text(s.evTotalAttendance,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: KSpace.m),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _latestName == null
              ? Text(
                  s.evWaitingFirstScan,
                  key: const ValueKey('waiting'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                )
              : Container(
                  key: ValueKey(_latestName),
                  padding: const EdgeInsets.symmetric(
                      horizontal: KSpace.m, vertical: KSpace.s),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.check, size: 16, color: scheme.onPrimaryContainer),
                      const SizedBox(width: KSpace.xs),
                      Flexible(
                        child: Text(
                          s.evJustCheckedIn(_latestName!),
                          style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: KSpace.xl),
        FilledButton.icon(
          onPressed: _ending ? null : _end,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(AppIcons.lock, size: 18),
          label: Text(_ending ? s.saving : s.evEndAttendance),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ summary

  Widget _summary(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasKi = widget.formId != null && widget.withKi;

    return ListView(
      key: const ValueKey('summary'),
      padding: const EdgeInsets.all(KSpace.l),
      children: [
        const SizedBox(height: KSpace.l),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Icon(AppIcons.success, size: 64, color: scheme.primary),
        ),
        const SizedBox(height: KSpace.m),
        Text(s.evAttendanceClosed,
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: KSpace.xs),
        Text(widget.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: KSpace.xl),
        Row(
          children: [
            Expanded(
              child: _Stat(
                value: _count,
                label: s.evTotalAttendance,
                delay: 0,
              ),
            ),
            if (hasKi) ...[
              const SizedBox(width: KSpace.m),
              Expanded(
                child: _Stat(
                  value: _kiResponses,
                  label: s.evKiReports,
                  delay: 120,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: KSpace.xl),
        OutlinedButton.icon(
          onPressed: () => _export(attendance: true, ki: false),
          icon: const Icon(AppIcons.download, size: 18),
          label: Text(s.evExportAttendance),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (hasKi) ...[
          const SizedBox(height: KSpace.s),
          OutlinedButton.icon(
            onPressed: () => _export(attendance: false, ki: true),
            icon: const Icon(AppIcons.download, size: 18),
            label: Text(s.evExportKi),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: KSpace.s),
          FilledButton.icon(
            onPressed: () => _export(attendance: true, ki: true),
            icon: const Icon(AppIcons.download, size: 18),
            label: Text(s.evExportBoth),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
        const SizedBox(height: KSpace.l),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(s.evDone),
        ),
      ],
    );
  }
}

/// One animated number in the summary.
class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final int delay;

  const _Stat({required this.value, required this.label, this.delay = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: Duration(milliseconds: 600 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: KSpace.l),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '$v',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
            ),
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
