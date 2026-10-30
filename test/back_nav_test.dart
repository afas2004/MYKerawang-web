import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Back-navigation matrix (agreed spec, rules 1–7) against go_router with
/// stand-in pages that use the app's real helpers: historyAwareExit,
/// leaveFormRoute, appBack / AppBackButton, backFallbackFor, selectTab,
/// ShellBackScope and OverlayTracker.
///
/// [FakeBrowser] plays the browser on the web: it records the history
/// entries go_router reports on the navigation channel and replays back /
/// forward as real `pushRouteInformation` messages — the same path a
/// browser's popstate takes.
class FakeBrowser {
  final List<(String, Object?)> entries = [];
  int index = -1;

  String get url => entries[index].$1;
  int get length => entries.length;

  void attach(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final uri = (args['uri'] ?? args['location']).toString();
          final entry = (Uri.parse(uri).toString(), args['state']);
          if (args['replace'] == true && index >= 0) {
            entries[index] = entry;
          } else {
            entries.removeRange(index + 1, entries.length);
            entries.add(entry);
            index++;
          }
        }
        return null;
      },
    );
    WebHistory.isWeb = () => true;
    WebHistory.back = () {
      scheduleMicrotask(() => _go(tester, -1));
      return true;
    };
    WebHistory.forward = () {
      scheduleMicrotask(() => _go(tester, 1));
      return true;
    };
  }

  /// The browser's own back / forward button.
  Future<void> back(WidgetTester tester) async {
    await _go(tester, -1);
    await tester.pumpAndSettle();
  }

  Future<void> forward(WidgetTester tester) async {
    await _go(tester, 1);
    await tester.pumpAndSettle();
  }

  Future<void> _go(WidgetTester tester, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= entries.length) return;
    index = next;
    final (uri, state) = entries[index];
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      SystemChannels.navigation.codec.encodeMethodCall(
        MethodCall('pushRouteInformation', {'location': uri, 'uri': uri, 'state': state}),
      ),
      (_) {},
    );
  }
}

const en = AppStrings.en;

/// A stand-in page: its path as text, an app-bar back arrow, and buttons
/// that push the pages reachable from it (as the real screens do).
Widget page(String path, {List<String> links = const [], bool dialog = false}) =>
    Builder(builder: (context) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton(), title: Text('page:$path')),
        body: Column(children: [
          for (final l in links)
            TextButton(onPressed: () => context.push(l), child: Text('open $l')),
          if (dialog)
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('a dialog')),
              ),
              child: const Text('open dialog'),
            ),
        ]),
      );
    });

class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    FormGuard.register(() => dirty);
  }

  @override
  void dispose() {
    FormGuard.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const AppCloseButton(), title: const Text('page:/create/listing')),
        body: Column(children: [
          TextButton(onPressed: () => setState(() => dirty = true), child: const Text('type')),
          TextButton(
            // As the editor's list icon: the analyses of this form.
            onPressed: () => context.push('/event/e1/form/responses?f=f1&from=edit'),
            child: const Text('open responses'),
          ),
          TextButton(
            onPressed: () => completePublish(context, '/item/new'),
            child: const Text('publish'),
          ),
        ]),
      );
}

late GoRouter router;

Widget app(String initial) {
  final rootKey = GlobalKey<NavigatorState>();
  const tabs = ['/home', '/announcements', '/search', '/market', '/events'];
  GoRoute root(String path, Widget Function(GoRouterState s) build,
          {FutureOr<bool> Function(BuildContext, GoRouterState)? onExit}) =>
      GoRoute(
        path: path,
        parentNavigatorKey: rootKey,
        onExit: onExit ?? historyAwareExit,
        builder: (_, s) => build(s),
      );

  router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: initial,
    observers: [OverlayTracker()],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ShellBackScope(
          currentIndex: shell.currentIndex,
          goHome: () => selectTab(context, shell, ShellBranch.home),
          child: Scaffold(
            body: shell,
            bottomNavigationBar: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                TextButton(onPressed: () => selectTab(context, shell, i), child: Text('tab$i')),
            ]),
          ),
        ),
        branches: [
          for (final t in tabs)
            StatefulShellBranch(observers: [OverlayTracker()], routes: [
              GoRoute(
                path: t,
                builder: (_, __) => page(t, links: const [
                  '/profile', '/post/p1', '/item/i1', '/event/e1', '/notifications', '/create/listing',
                ]),
              ),
            ]),
        ],
      ),
      root('/profile', (_) => page('/profile', links: const ['/settings', '/profile/edit', '/admin'])),
      root('/profile/edit', (_) => page('/profile/edit')),
      root('/settings', (_) => page('/settings', links: const ['/settings/privacy'], dialog: true)),
      root('/settings/privacy', (_) => page('/settings/privacy')),
      root('/notifications', (_) => page('/notifications', links: const ['/post/p1'])),
      root('/post/:id', (s) => page('/post/${s.pathParameters['id']}', links: const ['/u/u1', '/tag/t1'])),
      root('/u/:id', (s) => page('/u/${s.pathParameters['id']}', links: const ['/post/p2'])),
      root('/tag/:t', (s) => page('/tag/${s.pathParameters['t']}')),
      root('/item/:id', (s) => page('/item/${s.pathParameters['id']}')),
      root('/event/:id', (s) => page('/event/${s.pathParameters['id']}', links: [
            '/event/e1/form',
            '/event/e1/form/responses',
            '/event/e1/form/edit',
          ])),
      // The form screens, shaped exactly like lib/router.dart: the answer page
      // and the analyses are pushed pages (historyAwareExit), the editor is a
      // form (leaveFormRoute).
      root('/event/:id/form', (s) => page('/event/${s.pathParameters['id']}/form')),
      root('/event/:id/form/responses',
          (s) => page('/event/${s.pathParameters['id']}/form/responses')),
      root('/event/:id/form/edit', (_) => const _Form(), onExit: leaveFormRoute),
      root('/clubs', (_) => page('/clubs', links: const ['/c/kelab'])),
      root('/c/:h', (s) => page('/c/${s.pathParameters['h']}', links: const ['/c/kelab/manage'])),
      root('/c/:h/manage', (s) => page('/c/${s.pathParameters['h']}/manage')),
      root('/admin', (_) => page('/admin')),
      root('/standing', (_) => page('/standing')),
      root('/create/listing', (_) => const _Form(), onExit: leaveFormRoute),
    ],
  );
  return BlocProvider(
    create: (_) => LanguageCubit(),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoRouter.optionURLReflectsImperativeAPIs = true;
    FormGuard.clear();
    OverlayTracker.debugReset();
    TabHistory.homeIsBelow = false;
  });
  tearDown(WebHistory.debugReset);

  String shown() => router.routeInformationProvider.value.uri.path;
  Future<void> open(WidgetTester t, String path) async {
    await t.tap(find.text('open $path').last);
    await t.pumpAndSettle();
  }

  Future<void> arrow(WidgetTester t) async {
    await t.tap(find.byTooltip('Back').last);
    await t.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester t) async {
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
  }

  // ---------------------------------------------------------------- rule 1+2

  group('web: back = the previous screen, one step at a time', () {
    testWidgets('profile -> settings -> privacy, app-bar back x3', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await open(t, '/settings/privacy');
      expect(b.url, '/settings/privacy');

      await arrow(t);
      expect(shown(), '/settings'); // was: Home (two steps at once)
      expect(find.text('page:/settings'), findsOneWidget);
      await arrow(t);
      expect(shown(), '/profile');
      await arrow(t);
      expect(shown(), '/home');
      expect(b.index, 0);
    });

    testWidgets('same chain with the browser back button', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await open(t, '/settings/privacy');

      await b.back(t);
      expect(shown(), '/settings');
      expect(find.text('page:/settings'), findsOneWidget);
      await b.back(t);
      expect(shown(), '/profile');
      await b.back(t);
      expect(shown(), '/home');
    });

    testWidgets('post -> author -> another post: arrow and browser mixed', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/post/p1');
      await open(t, '/u/u1');
      await open(t, '/post/p2');

      await arrow(t);
      expect(shown(), '/u/u1');
      await b.back(t);
      expect(shown(), '/post/p1');
      await arrow(t);
      expect(shown(), '/home');
    });

    testWidgets('rule 7: forward after back returns, URL matches', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await b.back(t);
      expect(shown(), '/profile');
      await b.forward(t);
      expect(shown(), '/settings');
      expect(b.url, '/settings');
      expect(find.text('page:/settings'), findsOneWidget);
    });
  });

  group('Android / native: system back = previous screen', () {
    testWidgets('profile -> settings -> privacy, system back x3', (t) async {
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await open(t, '/settings/privacy');
      await systemBack(t);
      expect(shown(), '/settings');
      await systemBack(t);
      expect(shown(), '/profile');
      await systemBack(t);
      expect(shown(), '/home');
    });
  });

  // ---------------------------------------------------------------- rule 2+3

  group('cold open: the arrow goes up to the logical parent', () {
    const parents = {
      '/settings': '/profile',
      '/settings/privacy': '/settings',
      '/profile/edit': '/profile',
      '/profile': '/home',
      '/notifications': '/home',
      '/u/u1': '/home',
      '/post/p1': '/home',
      '/tag/t1': '/home',
      '/item/i1': '/market',
      '/event/e1': '/events',
      '/c/kelab': '/clubs',
      '/c/kelab/manage': '/c/kelab',
      '/admin': '/profile',
      '/standing': '/profile',
    };
    for (final entry in parents.entries) {
      testWidgets('${entry.key} -> ${entry.value}', (t) async {
        final b = FakeBrowser()..attach(t);
        await t.pumpWidget(app(entry.key));
        await t.pumpAndSettle();
        final before = b.length;
        await arrow(t);
        expect(shown(), entry.value);
        // "Up" replaces the entry: the browser's back then leaves rather
        // than bouncing back to the cold page.
        expect(b.length, before);
      });
    }

    test('parents table (incl. clubs, create and edit forms)', () {
      expect(backFallbackFor('/clubs'), '/announcements');
      expect(backFallbackFor('/clubs/register'), '/clubs');
      expect(backFallbackFor('/u/x/followers'), '/u/x');
      expect(backFallbackFor('/create/post'), '/home');
      expect(backFallbackFor('/create/post?from=/market'), '/market');
      expect(backFallbackFor('/create/post?from=/evil'), '/home');
      expect(backFallbackFor('/create/listing'), '/market');
      expect(backFallbackFor('/create/event'), '/events');
      expect(backFallbackFor('/item/i1/edit'), '/item/i1');
      expect(backFallbackFor('/event/e1/edit'), '/event/e1');
      expect(backFallbackFor('/post/p1/edit'), '/post/p1');
      // The form screens belong to their event, not to the events list.
      expect(backFallbackFor('/event/e1/form'), '/event/e1');
      expect(backFallbackFor('/event/e1/form/edit'), '/event/e1');
      expect(backFallbackFor('/event/e1/form/responses'), '/event/e1');
    });

    testWidgets('two levels cold: settings -> back -> profile -> back -> home', (t) async {
      FakeBrowser().attach(t);
      await t.pumpWidget(app('/settings'));
      await t.pumpAndSettle();
      await arrow(t);
      expect(shown(), '/profile');
      await arrow(t);
      expect(shown(), '/home');
    });
  });

  // ---------------------------------------------------------------- rule 4

  group('tabs add no history', () {
    testWidgets('native: home -> market -> events, back -> home', (t) async {
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await t.tap(find.text('tab3'));
      await t.pumpAndSettle();
      await t.tap(find.text('tab4'));
      await t.pumpAndSettle();
      expect(shown(), '/events');
      await systemBack(t);
      expect(shown(), '/home');
    });

    testWidgets('web: home -> market -> events, browser back -> home', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await t.tap(find.text('tab3'));
      await t.pumpAndSettle();
      await t.tap(find.text('tab4'));
      await t.pumpAndSettle();
      expect(b.length, 2); // home, then one entry for the tabs
      await b.back(t);
      expect(shown(), '/home');
    });
  });

  // ---------------------------------------------------------------- rule 5

  group('overlays close first', () {
    testWidgets('native: system back closes the dialog, page stays', (t) async {
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await t.tap(find.text('open dialog'));
      await t.pumpAndSettle();
      await systemBack(t);
      expect(find.text('a dialog'), findsNothing);
      expect(shown(), '/settings');
    });

    testWidgets('web: browser back closes the dialog, URL stays', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/profile');
      await open(t, '/settings');
      await t.tap(find.text('open dialog'));
      await t.pumpAndSettle();
      await b.back(t);
      await t.pumpAndSettle();
      expect(find.text('a dialog'), findsNothing);
      expect(find.text('page:/settings'), findsOneWidget);
      expect(b.url, '/settings');
      // The next back then leaves the page as usual.
      await b.back(t);
      expect(shown(), '/profile');
    });
  });

  // ---------------------------------------------------------------- rule 6

  group('forms', () {
    testWidgets('web: dirty form + browser back asks to discard', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/market'));
      await t.pumpAndSettle();
      await open(t, '/create/listing');
      await t.tap(find.text('type'));
      await t.pump();
      await b.back(t);
      expect(find.text(en.discardChangesTitle), findsOneWidget);
      await t.tap(find.text(en.discard));
      await t.pumpAndSettle();
      expect(shown(), '/market');
    });

    testWidgets('web: publish replaces the form; back skips it', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/market'));
      await t.pumpAndSettle();
      await open(t, '/create/listing');
      await t.tap(find.text('publish'));
      await t.pumpAndSettle();
      expect(shown(), '/item/new');
      await b.back(t);
      expect(shown(), '/market');
    });
  });

  // ------------------------------------------------- the form screens (KI)

  group('event form screens', () {
    testWidgets('web: leaving the answer page adds no history entry', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/event/e1');
      await open(t, '/event/e1/form');
      expect(b.length, 3);

      await arrow(t);
      expect(shown(), '/event/e1');
      // Was 4: the pop was reported as a new entry, so the browser's back
      // returned to the form that had just been closed.
      expect(b.length, 3);

      await b.back(t);
      expect(shown(), '/home');
      expect(find.text('page:/event/e1/form'), findsNothing);
    });

    testWidgets('web: back from the analyses lands on the editor, not a copy', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/event/e1');
      await open(t, '/event/e1/form/edit');
      await t.tap(find.text('open responses'));
      await t.pumpAndSettle();
      expect(b.length, 4);

      await arrow(t);
      expect(shown(), '/event/e1/form/edit');
      expect(b.length, 4);
    });

    testWidgets('cold open: the answer page goes up to its event', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/event/e1/form'));
      await t.pumpAndSettle();
      final before = b.length;
      await arrow(t);
      expect(shown(), '/event/e1');
      expect(b.length, before);
    });

    testWidgets('cold open: the analyses go up to their event', (t) async {
      FakeBrowser().attach(t);
      await t.pumpWidget(app('/event/e1/form/responses'));
      await t.pumpAndSettle();
      await arrow(t);
      expect(shown(), '/event/e1');
    });

    testWidgets('web: a dirty editor still asks, and Keep editing stays put', (t) async {
      final b = FakeBrowser()..attach(t);
      await t.pumpWidget(app('/home'));
      await t.pumpAndSettle();
      await open(t, '/event/e1');
      await open(t, '/event/e1/form/edit');
      await t.tap(find.text('type'));
      await t.pump();

      await b.back(t);
      expect(find.text(en.discardChangesTitle), findsOneWidget);
      await t.tap(find.text(en.keepEditing));
      await t.pumpAndSettle();

      // Still on the form, with the address bar back on it.
      expect(find.text('page:/create/listing'), findsOneWidget);
      expect(shown(), '/event/e1/form/edit');
      expect(b.url, '/event/e1/form/edit');
      // And the entry under it survived: discarding now leaves in one step.
      await b.back(t);
      await t.tap(find.text(en.discard));
      await t.pumpAndSettle();
      expect(shown(), '/event/e1');
    });
  });
}
