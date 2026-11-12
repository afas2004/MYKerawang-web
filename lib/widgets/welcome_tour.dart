import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../l10n/welcome_tour_strings.dart';
import '../language_cubit.dart';
import '../router.dart' show rootNavigator;
import '../utils/app_nav.dart';
import 'brand/brand.dart';

/// The welcome tour: a centred popup, four cards, that a brand-new account
/// sees once, right after account setup.
///
/// How "once, for new accounts" works: onboarding (which only ever runs
/// for an account with no username yet) calls [markPending] for that
/// user, then [showPending]. [showPending] shows the tour only while that
/// flag is set and clears it as it opens, so existing accounts never see
/// it and nobody sees it twice. The flag lives in SharedPreferences, so a
/// reload between setup and Home still shows it (SessionWatcher calls
/// [showPending] at start-up too). Settings can replay it with [show].
abstract final class WelcomeTour {
  static String _key(String userId) => 'welcome_tour_pending:$userId';

  static bool _open = false;

  /// Whether the tour is on screen now (page tips wait for it).
  static bool get isOpen => _open;

  /// Set once the tour has opened in this app session: page tips don't
  /// pile on straight after it, they start on the next visit.
  static bool shownThisSession = false;

  /// Queues the tour for [userId]; [name] is the display name it greets.
  static Future<void> markPending(String userId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), name.trim());
  }

  /// Whether [userId] still has the tour queued (tests, diagnostics).
  static Future<bool> isPending(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(userId));
  }

  /// Opens the tour if one is queued for [userId] (default: the signed-in
  /// user), on [navigator] (default: the app's root navigator). Returns
  /// whether it opened.
  static Future<bool> showPending({String? userId, NavigatorState? navigator}) async {
    final uid = userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || _open) return false;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key(uid));
    if (name == null) return false;
    // Cleared first: a tour that was opened counts as seen, even if the
    // app is closed halfway.
    await prefs.remove(_key(uid));
    // After the frame, so the page it was queued from (onboarding) has
    // been replaced by Home underneath.
    await WidgetsBinding.instance.endOfFrame;
    final nav = navigator ?? rootNavigator;
    if (nav == null || !nav.mounted) return false;
    await show(nav.context, name: name.isEmpty ? null : name);
    return true;
  }

  /// Opens the tour now (Settings › Welcome tour). [name] personalises the
  /// first and last cards.
  static Future<void> show(BuildContext context, {String? name}) async {
    if (_open) return;
    _open = true;
    shownThisSession = true;
    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (_) => WelcomeTourDialog(name: name),
      );
    } finally {
      _open = false;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _open = false;
    shownThisSession = false;
  }
}

/// One card of the tour.
class _Step {
  final Color color;
  final Widget Function(BuildContext) art;
  final String Function(AppStrings, String?) title;
  final String Function(AppStrings) body;
  const _Step(this.color, this.art, this.title, this.body);
}

final _steps = <_Step>[
  _Step(KPalette.plum, (_) => const _WelcomeArt(), (s, n) => s.tourWelcomeTitle(n), (s) => s.tourWelcomeBody),
  _Step(KPalette.jingga, (c) => _MarketArt(c.l10n), (s, _) => s.tourMarketTitle, (s) => s.tourMarketBody),
  _Step(KPalette.hijauPucuk, (c) => _EventArt(c.l10n), (s, _) => s.tourEventsTitle, (s) => s.tourEventsBody),
  _Step(KPalette.plum, (c) => _RulesArt(c.l10n), (s, n) => s.tourDoneTitle(n), (s) => s.tourDoneBody),
];

/// The popup itself. Public so tests (and Settings) can pump it directly.
class WelcomeTourDialog extends StatefulWidget {
  final String? name;
  const WelcomeTourDialog({super.key, this.name});

  @override
  State<WelcomeTourDialog> createState() => _WelcomeTourDialogState();
}

class _WelcomeTourDialogState extends State<WelcomeTourDialog> {
  int _i = 0;

  bool get _last => _i == _steps.length - 1;

  void _close() => Navigator.of(context).pop();

  static double _bandHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 640 ? 136 : 172;

  /// Closes the tour, then runs [then] with a context that outlives it.
  void _closeThen(void Function(BuildContext) then) {
    final nav = Navigator.of(context);
    nav.pop();
    then(nav.context);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final step = _steps[_i];

    return Dialog(
      insetPadding: const EdgeInsets.all(KSpace.l),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The coloured band with the card's picture.
              // At least [_bandHeight] tall, taller if a long translation
              // wraps; shorter on small phones so the buttons stay in view.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                constraints: BoxConstraints(minHeight: _bandHeight(context)),
                color: step.color,
                child: Stack(alignment: Alignment.center, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xl, KSpace.l, KSpace.l),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(key: ValueKey(_i), child: step.art(context)),
                    ),
                  ),
                  Positioned(
                    top: KSpace.xs,
                    right: KSpace.xs,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      icon: const Icon(AppIcons.close, color: Colors.white),
                      onPressed: _close,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KSpace.l + 4, KSpace.l + 4, KSpace.l + 4, KSpace.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Dots(index: _i, count: _steps.length, color: step.color),
                    const SizedBox(height: KSpace.m),
                    Text(
                      step.title(s, widget.name),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                    ),
                    const SizedBox(height: KSpace.s),
                    Text(step.body(s), style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                    if (_i == 0) ...[
                      const SizedBox(height: KSpace.s),
                      Text(s.tourWelcomeHint, style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    if (_last) ...[
                      const SizedBox(height: KSpace.s),
                      Text(s.tourDisclaimer, style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36),
                            foregroundColor: KPalette.onTheme(step.color, theme.brightness),
                          ),
                          onPressed: () => _closeThen((c) => c.goPrivacyPolicy()),
                          child: Text(s.social.privacyPolicy),
                        ),
                      ),
                    ],
                    const SizedBox(height: KSpace.m),
                    _last ? _lastButtons(s, step) : _navButtons(s, step),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButtons(AppStrings s, _Step step) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _i == 0 ? _close : () => setState(() => _i--),
            child: Text(_i == 0 ? s.tourSkip : s.tourBack),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: step.color,
              foregroundColor: Colors.white,
              minimumSize: const Size(112, 46),
            ),
            onPressed: () => setState(() => _i++),
            child: Text(_i == 0 ? s.tourShowMe : s.tourNext),
          ),
        ],
      );

  Widget _lastButtons(AppStrings s, _Step step) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: step.color,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _close,
            child: Text(s.tourStartExploring),
          ),
          const SizedBox(height: KSpace.xs),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            onPressed: () => _closeThen((c) => c.goCreateListing()),
            child: Text(s.tourSellFirst),
          ),
        ],
      );
}

class _Dots extends StatelessWidget {
  final int index;
  final int count;
  final Color color;
  const _Dots({required this.index, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.tourStep(index + 1, count),
      child: Row(children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.only(right: 6),
            width: i == index ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? KPalette.onTheme(color, theme.brightness)
                  : theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ the pictures
// Drawn from widgets, on the coloured band, always light cards with dark
// text (an illustration, not themed UI). Sample items, never real posts.

// Brand palette only (test/identity_rules_test.dart): ink is kelabu arang,
// the pale fills are each colour lifted most of the way to white.
const _ink = KPalette.kelabuArang;
final _muted = Color.lerp(KPalette.kelabuArang, Colors.white, 0.3)!;
Color _pale(Color c) => Color.lerp(c, Colors.white, 0.88)!;

class _Tile extends StatelessWidget {
  final double size;
  final Color color;
  final Widget child;
  final double turns;
  const _Tile({required this.size, required this.color, required this.child, this.turns = 0});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: turns,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.28)),
          alignment: Alignment.center,
          child: child,
        ),
      );
}

class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const _Tile(size: 48, color: KPalette.jingga, turns: -0.14,
                child: Icon(AppIcons.market, color: Colors.white, size: 24)),
            const SizedBox(width: 10),
            _Tile(size: 64, color: Colors.white,
                child: Text('K', style: TextStyle(color: KPalette.plum, fontSize: 28,
                    fontWeight: FontWeight.w700, fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily))),
            const SizedBox(width: 10),
            const _Tile(size: 48, color: KPalette.hijauPucuk, turns: 0.14,
                child: Icon(AppIcons.events, color: Colors.white, size: 24)),
          ]),
          const SizedBox(height: 14),
          Text('Kolej Kerawang', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _MiniListing extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String price;
  final double turns;
  final double dy;
  const _MiniListing(this.icon, this.tint, this.label, this.price, {this.turns = 0, this.dy = 0});

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: Offset(0, dy),
        child: Transform.rotate(
          angle: turns,
          child: Container(
            width: 108,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 68, color: tint, alignment: Alignment.center,
                  child: Icon(icon, color: KPalette.jingga, size: 28)),
              Padding(
                padding: const EdgeInsets.all(7),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(price, style: const TextStyle(color: KPalette.jingga, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _MarketArt extends StatelessWidget {
  final AppStrings s;
  const _MarketArt(this.s);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _MiniListing(Icons.ramen_dining_outlined, _pale(KPalette.merahSaga), s.tourSampleRamen, 'RM5.50', turns: -0.07),
          const SizedBox(width: 10),
          _MiniListing(Icons.light_outlined, _pale(KPalette.jingga), s.tourSampleLamp, 'RM15.00', turns: 0.05, dy: 10),
        ]),
      );
}

class _EventArt extends StatelessWidget {
  final AppStrings s;
  const _EventArt(this.s);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 212,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              height: 64,
              color: _pale(KPalette.hijauPucuk),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7)),
                  alignment: Alignment.center,
                  child: const Icon(AppIcons.events, color: KPalette.hijauPucuk, size: 20),
                ),
                const Spacer(),
                const Icon(Icons.sports_soccer_outlined, color: KPalette.hijauPucuk, size: 32),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.tourSampleEvent, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(s.tourSampleEventWhen, style: TextStyle(color: _muted, fontSize: 11)),
                  ]),
                ),
                const Icon(AppIcons.saved, color: KPalette.hijauPucuk, size: 18),
              ]),
            ),
          ]),
        ),
      );
}

class _RulesArt extends StatelessWidget {
  final AppStrings s;
  const _RulesArt(this.s);

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: Colors.black12)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: KPalette.plum),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w500))),
          ]),
        );
    // Not excluded: the rules are worth reading out.
    return Container(
        width: 248,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          row(AppIcons.like, s.tourRuleKind),
          row(AppIcons.lock, s.tourRulePrivate),
          row(AppIcons.report, s.tourRuleReport, last: true),
        ]),
      );
  }
}
