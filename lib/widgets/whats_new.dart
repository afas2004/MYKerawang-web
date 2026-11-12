import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/whats_new_strings.dart';
import '../language_cubit.dart';
import '../router.dart' show rootNavigator;
import '../services/update_service.dart';
import '../services/whats_new_notes.dart';
import '../utils/app_nav.dart';
import 'brand/brand.dart';

/// "What's new in 1.x": a small centred card someone sees once, the first
/// time they open a version that has release notes.
///
/// How "once per version" works: the last version this device showed is
/// kept in SharedPreferences. [maybeShow] compares it with the running
/// version, records the new one first (so a reload never shows it twice),
/// then shows the notes of every release in between (see
/// [releasesSince]). A version with no notes shows nothing.
///
/// Brand-new accounts never see it: onboarding calls [markSeen] when it
/// queues the welcome tour, and start-up only calls [maybeShow] when no
/// tour opened.
abstract final class WhatsNew {
  static const _key = 'whats_new_seen';

  /// Releases shown in the pop-up at most; the rest are in Settings.
  static const maxReleases = 3;

  static bool _open = false;

  /// Records [version] (default: the running one) as already seen.
  static Future<void> markSeen([String? version]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, version ?? UpdateService.appVersion);
  }

  /// The version this device last showed notes for (tests, diagnostics).
  static Future<String?> lastSeen() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  /// Shows the notes since the last version this device saw, if any.
  /// Returns whether the card opened. [version] and [notes] are for tests.
  static Future<bool> maybeShow({
    NavigatorState? navigator,
    String? version,
    List<ReleaseNote>? notes,
  }) async {
    if (_open) return false;
    final current = version ?? UpdateService.appVersion;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(_key);
    if (seen != null && compareVersions(seen, current) >= 0) return false;
    await prefs.setString(_key, current);
    final releases = releasesSince(seen, current, notes: notes);
    if (releases.isEmpty) return false;

    await WidgetsBinding.instance.endOfFrame;
    final nav = navigator ?? rootNavigator;
    if (nav == null || !nav.mounted) return false;
    _open = true;
    try {
      await showDialog<void>(
        context: nav.context,
        useRootNavigator: true,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => WhatsNewDialog(
          version: current,
          releases: releases.take(maxReleases).toList(),
        ),
      );
    } finally {
      _open = false;
    }
    return true;
  }

  @visibleForTesting
  static void debugReset() => _open = false;
}

/// The card itself. Public so tests can pump it directly.
class WhatsNewDialog extends StatelessWidget {
  final String version;
  final List<ReleaseNote> releases;
  const WhatsNewDialog({super.key, required this.version, required this.releases});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final accent = KPalette.onTheme(KPalette.plum, theme.brightness);
    final lines = [for (final r in releases) ...r.visibleLines];
    final nav = Navigator.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(KSpace.l),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: KPalette.plum,
              padding: const EdgeInsets.fromLTRB(KSpace.l + 4, KSpace.l, KSpace.xs, KSpace.l),
              child: Row(children: [
                const Icon(AppIcons.sparkle, color: Colors.white),
                const SizedBox(width: KSpace.s),
                Expanded(
                  child: Text(
                    s.whatsNewIn(version),
                    style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600, height: 1.25),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(AppIcons.close, color: Colors.white),
                  onPressed: nav.pop,
                ),
              ]),
            ),
            // The list scrolls on a small phone; the buttons stay put.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(KSpace.l + 4, KSpace.l, KSpace.l + 4, 0),
                child: Column(children: [
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: KSpace.m),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          child: Text('${i + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: KSpace.s + 2),
                        Expanded(
                          child: Text(lines[i].of(s),
                              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.xs, KSpace.l, KSpace.l),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: KSpace.xs,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: accent),
                    onPressed: () {
                      nav.pop();
                      nav.context.goWhatsNew();
                    },
                    child: Text(s.whatsNewSeeAll),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: KPalette.plum,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(96, 44),
                    ),
                    onPressed: nav.pop,
                    child: Text(s.whatsNewGotIt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
