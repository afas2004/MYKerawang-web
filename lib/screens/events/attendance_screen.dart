import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/share_service.dart';
import '../../theme/app_icons.dart';
import '../../utils/csv_saver.dart';
import '../../utils/feedback.dart';
import '../../widgets/brand/brand.dart';

/// Organiser's attendance screen.
///
/// Shows a QR code that refreshes every 10 seconds. The code encodes a
/// URL, so a student who will not use the app can open it with the phone
/// camera and land on the web check-in page. Tokens stay valid for 20 s,
/// so one slow scan does not fail while a shared screenshot still dies.
class AttendanceScreen extends StatefulWidget {
  final String eventId;
  final String title;

  const AttendanceScreen({super.key, required this.eventId, required this.title});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const _refresh = Duration(seconds: 10);

  Timer? _timer;
  String? _token;
  String? _error;
  int _count = 0;
  bool _loading = true;
  bool _exporting = false;
  bool _enabled = false;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _refreshToken();
    _loadCount();
    _loadEnabled();
    _timer = Timer.periodic(_refresh, (_) => _refreshToken());
  }

  Future<void> _loadEnabled() async {
    try {
      final row = await _db
          .from('events')
          .select('attendance_enabled')
          .eq('id', widget.eventId)
          .maybeSingle();
      if (mounted) {
        setState(() => _enabled = row?['attendance_enabled'] == true);
      }
    } catch (_) {
      // Leave it off; the organiser can switch it on below.
    }
  }

  Future<void> _setEnabled(bool v) async {
    setState(() => _enabled = v);
    try {
      await _db
          .from('events')
          .update({'attendance_enabled': v}).eq('id', widget.eventId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enabled = !v);
      showErrorWithRetry(context, e, onRetry: () => _setEnabled(v));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshToken() async {
    try {
      final rows = await _db
          .rpc('event_checkin_token', params: {'p_event_id': widget.eventId});
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (!mounted) return;
      setState(() {
        _token = list.isEmpty ? null : '${list.first['token']}';
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCount() async {
    try {
      final n = await _db
          .from('event_attendance')
          .count(CountOption.exact)
          .eq('event_id', widget.eventId);
      if (mounted) setState(() => _count = n);
    } catch (_) {
      // The count is a nicety; the export is the source of truth.
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final rows = await _db
          .rpc('event_attendance_list', params: {'p_event_id': widget.eventId});
      final list = List<Map<String, dynamic>>.from(rows as List);
      final out = StringBuffer()
        ..writeln('name,student_id,verified,checked_in_at');
      for (final r in list) {
        out.writeln([
          csvCell(r['display_name'] ?? r['username']),
          csvCell(r['student_id']),
          csvCell(r['verified'] == true ? 'yes' : 'no'),
          csvCell(r['checked_in_at']),
        ].join(','));
      }
      await saveCsv(out.toString(), _fileName());
    } catch (e) {
      if (mounted) showErrorWithRetry(context, e, onRetry: _export);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fileName() {
    final slug = widget.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final d = DateTime.now();
    final stamp =
        '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    return 'attendance-${slug.isEmpty ? 'event' : slug}-$stamp.csv';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = _token == null
        ? null
        : ShareService.absoluteUrl(
            '/event/${widget.eventId}/checkin?t=$_token');

    return Scaffold(
      appBar: AppBar(title: Text(s.evAttendance)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(KSpace.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: KSpace.m),
                Text(s.evAttendanceHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: _setEnabled,
                  title: Text(s.evAttendance),
                  subtitle: Text(
                    _enabled ? s.evAttendanceCount.fill(['$_count']) : s.evAttendanceOff,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: KSpace.s),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  )
                else if (url != null)
                  KCard(
                    padding: const EdgeInsets.all(KSpace.m),
                    child: QrImageView(
                      data: url,
                      size: 260,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square, color: Colors.black),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black),
                    ),
                  )
                else
                  Text(_error ?? s.connectionError,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error)),
                const SizedBox(height: KSpace.l),
                Text(s.evAttendanceCount.fill(['$_count']),
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: KSpace.m),
                OutlinedButton.icon(
                  onPressed: _exporting ? null : _export,
                  icon: Icon(AppIcons.download, size: 18),
                  label: Text(_exporting ? s.saving : s.evExportCsv),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
