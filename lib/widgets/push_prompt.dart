import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/notification_strings.dart';
import '../language_cubit.dart';
import '../services/push_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../utils/adaptive.dart';
import 'app_toast.dart';

/// Asks to turn on phone notifications at a moment where they clearly help
/// (right after joining an event), never on first load. Our own sheet comes
/// first; the browser's prompt only appears if they tap "Turn on", so a
/// hard-to-undo "Block" is rare. "Not now" waits two weeks.
Future<void> maybeOfferPushAfterJoin(BuildContext context, String eventTitle) async {
  if (!await PushService.instance.shouldOffer()) return;
  if (!context.mounted) return;
  await showPushSheet(context, eventTitle: eventTitle);
}

Future<void> showPushSheet(BuildContext context, {String? eventTitle}) async {
  final ios = await PushService.instance.state() == PushState.iosNeedsInstall;
  if (!context.mounted) return;
  Widget body(BuildContext ctx) => _PushSheet(eventTitle: eventTitle, ios: ios);
  if (isWide(context)) {
    await showAdaptiveSheet<void>(context: context, builder: body);
  } else {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: body,
    );
  }
}

/// Runs the browser prompt and says how it went. Call straight from a tap
/// (before any await): the browser only prompts during one.
Future<void> turnOnPush(AppStrings s) async {
  final r = await PushService.instance.enable();
  showToast(switch (r) {
    EnableResult.enabled => s.pushEnabled,
    EnableResult.denied => s.pushDenied,
    _ => s.pushFailed,
  }, error: r != EnableResult.enabled);
}

class _PushSheet extends StatelessWidget {
  final String? eventTitle;
  final bool ios;
  const _PushSheet({this.eventTitle, required this.ios});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget point(Widget lead, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.xs),
          child: Row(children: [
            lead,
            const SizedBox(width: KSpace.m),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ]),
        );
    Widget check(String t) => point(Icon(AppIcons.check, size: 20, color: scheme.primary), t);
    Widget step(int n, String t) => point(
        SizedBox(width: 20, child: Text('$n.', style: theme.textTheme.titleSmall)), t);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(KSpace.xl, 0, KSpace.xl, KSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: KRadius.card,
            ),
            child: Icon(AppIcons.notificationsActive, size: 28, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: KSpace.m),
          Text(ios ? s.pushIosTitle : (eventTitle != null ? s.pushAskEventTitle : s.pushBannerTitle),
              style: theme.textTheme.titleLarge),
          const SizedBox(height: KSpace.xs),
          Text(
            ios
                ? s.pushIosBody
                : eventTitle != null
                    ? s.pushAskEventBody(eventTitle!)
                    : s.pushBannerBody,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KSpace.m),
          if (ios) ...[
            step(1, s.pushIosStep1),
            step(2, s.pushIosStep2),
            step(3, s.pushIosStep3),
          ] else ...[
            check(s.pushPoint1),
            check(s.pushPoint2),
            check(s.pushPoint3),
          ],
          const SizedBox(height: KSpace.l),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final strings = context.l10nRead;
                if (ios) {
                  PushService.instance.snooze();
                } else {
                  turnOnPush(strings); // starts the prompt inside this tap
                }
                Navigator.of(context).pop();
              },
              child: Text(ios ? s.pushGotIt : s.pushTurnOnFull),
            ),
          ),
          if (!ios)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  PushService.instance.snooze();
                  Navigator.of(context).pop();
                },
                child: Text(s.pushNotNow),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Get these on your phone" at the top of the bell list. Shown only when
/// push is possible here, off, and not snoozed.
class PushOfferBanner extends StatefulWidget {
  const PushOfferBanner({super.key});

  @override
  State<PushOfferBanner> createState() => _PushOfferBannerState();
}

class _PushOfferBannerState extends State<PushOfferBanner> {
  late Future<bool> _show = PushService.instance.shouldOffer();

  void _recheck() => setState(() => _show = PushService.instance.shouldOffer());

  @override
  void initState() {
    super.initState();
    PushService.instance.changed.addListener(_recheck);
  }

  @override
  void dispose() {
    PushService.instance.changed.removeListener(_recheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _show,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        final s = context.l10n;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(KSpace.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer, borderRadius: KRadius.input),
                    child: Icon(AppIcons.notificationsActive, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: KSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.pushBannerTitle, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(s.pushBannerBody,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: KSpace.s),
                        Wrap(spacing: KSpace.s, children: [
                          FilledButton(
                            onPressed: () => showPushSheet(context),
                            child: Text(s.pushTurnOn),
                          ),
                          TextButton(
                            onPressed: PushService.instance.snooze,
                            child: Text(s.pushNotNow),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
