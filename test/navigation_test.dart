import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/create_event_screen.dart';
import 'package:mykerawang/screens/create_listing_screen.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Navigation behaviour with go_router and stand-in pages: the same
/// helpers the app's router uses (selectTab, ShellBackScope, appBack,
/// leaveFormRoute, completePublish), without Supabase.
import 'helpers/toast_host.dart';
void main() {
  const en = AppStrings.en;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormGuard.clear();
    // As in buildRouter: pushed pages get their own URL.
    GoRouter.optionURLReflectsImperativeAPIs = true;
  });

  late GoRouter router;

  Widget app(String initial) {
    final rootKey = GlobalKey<NavigatorState>();
    const tabs = ['/home', '/search', '/market', '/events', '/profile'];
    router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: initial,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => ShellBackScope(
            currentIndex: shell.currentIndex,
            goHome: () => selectTab(context, shell, ShellBranch.home),
            child: Scaffold(
              body: shell,
              bottomNavigationBar: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    TextButton(
                      onPressed: () => selectTab(context, shell, i),
                      child: Text('tab$i'),
                    ),
                ],
              ),
            ),
          ),
          branches: [
            for (final path in tabs)
              StatefulShellBranch(routes: [
                GoRoute(
                  path: path,
                  builder: (context, _) => Scaffold(
                    body: Column(
                      children: [
                        Text('page:$path'),
                        TextButton(
                          onPressed: () => context.goCreateListing(),
                          child: const Text('sell'),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
          ],
        ),
        GoRoute(
          path: '/item/:id',
          parentNavigatorKey: rootKey,
          onExit: historyAwareExit,
          builder: (context, state) => Scaffold(
            appBar: AppBar(leading: const AppBackButton()),
            body: Text('item:${state.pathParameters['id']}'),
          ),
        ),
        GoRoute(
          path: '/create/listing',
          parentNavigatorKey: rootKey,
          onExit: leaveFormRoute,
          builder: (context, state) => const _FakeForm(),
        ),
      ],
    );
    return BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp.router(builder: withToasts, routerConfig: router),
    );
  }

  String location() => router.routeInformationProvider.value.uri.path;

  testWidgets('switching tabs then back goes to Home, not through every tab',
      (tester) async {
    await tester.pumpWidget(app('/home'));
    await tester.tap(find.text('tab2')); // Market
    await tester.pumpAndSettle();
    await tester.tap(find.text('tab3')); // Events
    await tester.pumpAndSettle();
    expect(location(), '/events');

    await tester.binding.handlePopRoute(); // system back
    await tester.pumpAndSettle();
    expect(location(), '/home');
    expect(find.text('page:/home'), findsOneWidget);
  });

  testWidgets('a detail page opened cold goes back to its tab', (tester) async {
    await tester.pumpWidget(app('/item/x'));
    await tester.pumpAndSettle();
    expect(find.text('item:x'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(location(), '/market');
  });

  testWidgets('publish replaces the form; back lands on the starting tab',
      (tester) async {
    await tester.pumpWidget(app('/market'));
    await tester.tap(find.text('sell'));
    await tester.pumpAndSettle();
    expect(location(), '/create/listing');

    await tester.tap(find.text('publish'));
    await tester.pumpAndSettle();
    expect(location(), '/item/new');
    expect(find.text(en.listingPublished), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(location(), '/market');
    expect(find.text('form'), findsNothing);
  });

  testWidgets('leaving a form with input asks to discard', (tester) async {
    await tester.pumpWidget(app('/market'));
    await tester.tap(find.text('sell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('type something'));
    await tester.pump();

    // Back once: asked, keep editing.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(en.discardChangesTitle), findsOneWidget);
    await tester.tap(find.text(en.keepEditing));
    await tester.pumpAndSettle();
    expect(location(), '/create/listing');
    expect(find.text('form'), findsOneWidget);

    // Close (X): asked again, discard this time.
    await tester.tap(find.byTooltip(en.close));
    await tester.pumpAndSettle();
    expect(find.text(en.discardChangesTitle), findsOneWidget);
    await tester.tap(find.text(en.discard));
    await tester.pumpAndSettle();
    expect(location(), '/market');
  });

  testWidgets('leaving an untouched form does not ask', (tester) async {
    await tester.pumpWidget(app('/market'));
    await tester.tap(find.text('sell'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(en.close));
    await tester.pumpAndSettle();
    expect(find.text(en.discardChangesTitle), findsNothing);
    expect(location(), '/market');
  });

  test('cold back targets the matching tab', () {
    expect(backFallbackFor('/item/abc'), '/market');
    expect(backFallbackFor('/event/abc'), '/events');
    expect(backFallbackFor('/post/abc'), '/home');
    expect(backFallbackFor('/u/abc'), '/home');
    expect(backFallbackFor('/create/listing'), '/market');
    expect(backFallbackFor('/create/event'), '/events');
    expect(backFallbackFor('/create/post'), '/home');
    expect(backFallbackFor('/item/abc/edit'), '/item/abc');
    expect(backFallbackFor('/settings/privacy'), '/settings');
  });

  // ---- the real create pages (the reported blank screen) ----

  Future<void> pumpForm(WidgetTester tester, Widget form) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(builder: withToasts, home: form),
    ));
    await tester.pump();
  }

  testWidgets('Sell item at 375x812 shows its fields and a close button',
      (tester) async {
    await pumpForm(tester, const CreateListingScreen());
    expect(tester.takeException(), isNull);
    expect(find.text(en.sellItem), findsOneWidget); // app bar title
    expect(find.byTooltip(en.close).hitTestable(), findsOneWidget);
    expect(find.widgetWithText(TextFormField, en.title).hitTestable(), findsOneWidget);
    expect(find.text(en.publish).hitTestable(), findsOneWidget);
  });

  testWidgets('Create event at 375x812 shows its fields and a close button',
      (tester) async {
    await pumpForm(tester, const CreateEventScreen());
    expect(tester.takeException(), isNull);
    expect(find.text(en.createEvent), findsOneWidget);
    expect(find.byTooltip(en.close).hitTestable(), findsOneWidget);
    expect(find.text(en.eventTitle).hitTestable(), findsOneWidget);
    expect(find.text(en.publish).hitTestable(), findsOneWidget);
  });
}

/// Stand-in create form: registers with FormGuard like the real ones.
class _FakeForm extends StatefulWidget {
  const _FakeForm();

  @override
  State<_FakeForm> createState() => _FakeFormState();
}

class _FakeFormState extends State<_FakeForm> {
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    FormGuard.register(() => _dirty);
  }

  @override
  void dispose() {
    FormGuard.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const AppCloseButton(), title: const Text('form')),
      body: Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _dirty = true),
            child: const Text('type something'),
          ),
          TextButton(
            onPressed: () => completePublish(context, '/item/new',
                message: context.l10nRead.listingPublished),
            child: const Text('publish'),
          ),
        ],
      ),
    );
  }
}
