import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../utils/file_saver_stub.dart'
    if (dart.library.js_interop) '../../utils/file_saver_web.dart' as saver;
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';

/// Append-only audit trail, filterable, exportable as CSV (browser
/// download on web, clipboard elsewhere).
class LogTab extends StatefulWidget {
  const LogTab({super.key});

  @override
  State<LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<LogTab> with AutomaticKeepAliveClientMixin {
  String? _actor;
  String _action = '';
  Timer? _debounce;
  late Future<List<Map<String, dynamic>>> _future = ModerationService.log();

  static final _time = DateFormat('d MMM yyyy HH:mm');
  static const _columns = [
    'created_at', 'actor', 'actor_id', 'action', 'target_type', 'target_id', 'reason', 'metadata',
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() =>
      setState(() => _future = ModerationService.log(action: _action, actor: _actor));

  Future<void> _export() async {
    final m = modStrings(context);
    try {
      final rows = await _future;
      final csv = toCsv(_columns, rows);
      if (!mounted) return;
      if (kIsWeb) {
        final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
        saver.downloadBytes(utf8.encode(csv), 'moderation-log-$stamp.csv');
        showModSnack(context, m.csvDownloaded);
      } else {
        await Clipboard.setData(ClipboardData(text: csv));
        if (mounted) showModSnack(context, m.csvCopied);
      }
    } catch (e) {
      if (mounted) showModError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(ModIcons.search, size: 18),
                  hintText: m.filterAction,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  _action = v.trim();
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _reload);
                },
              ),
            ),
            DropdownButton<String?>(
              value: _actor,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: null, child: Text(m.actorAll)),
                DropdownMenuItem(value: 'system', child: Text(m.actorSystem)),
                DropdownMenuItem(value: 'admin', child: Text(m.actorAdmin)),
                DropdownMenuItem(value: 'owner', child: Text(m.actorOwner)),
                DropdownMenuItem(value: 'user', child: Text(m.actorUser)),
              ],
              onChanged: (v) {
                _actor = v;
                _reload();
              },
            ),
            OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(ModIcons.download, size: 18),
              label: Text(m.downloadCsv),
            ),
          ],
        ),
      ),
      empty: ModEmptyState(icon: ModIcons.log, title: m.noLog),
      itemBuilder: (context, row) {
        final at = DateTime.tryParse('${row['created_at']}');
        final system = row['actor'] == 'system';
        final target = [row['target_type'], row['target_id']]
            .where((e) => e != null)
            .join(' ');
        return ListTile(
          dense: true,
          leading: Icon(system ? ModIcons.bot : ModIcons.person,
              color: system ? scheme.secondary : scheme.primary),
          title: Text('${row['action']}  ·  $target',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              if (at != null) _time.format(at.toLocal()),
              '${row['actor']}',
              if ((row['reason'] as String?)?.isNotEmpty == true) '“${row['reason']}”',
            ].join(' · '),
          ),
        );
      },
    );
  }
}
