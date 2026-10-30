import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../language_cubit.dart';
import '../widgets/app_toast.dart';
import 'browser_history_stub.dart'
    if (dart.library.js_interop) 'browser_history_web.dart';

/// Navigation for the whole app, in one place.
///
/// Model
/// * Tabs (Home, Search, Market, Events, Profile) live in the shell. Tab
///   switches don't pile up history: back from any tab goes to Home, and
///   back on Home leaves the app (see MainScaffold).
/// * Detail pages (/post, /item, /event, /u) are pushed above the shell;
///   back returns to wherever you came from. Opened cold from a shared
///   link there's nothing underneath, so back goes to the matching tab
///   ([backFallbackFor]).
/// * Create / edit forms are routes too (/create/..., /…/:id/edit). Leaving
///   one with unsaved input asks first ([FormGuard], [leaveFormRoute]).
///   Publishing replaces the form with the new item's page
///   ([completePublish]), so back never returns to a filled-in form.
/// * On the web, an in-app back steps the browser history back instead of
///   adding an entry ([historyAwareExit]), so the browser's own back
///   button and the app's back arrow always agree.
///
/// Every pushed page needs `onExit: historyAwareExit` (or [leaveFormRoute]
/// for a form). Without it the pop is reported to the browser as a *new*
/// entry, so the browser's back returns to the page that was just closed —
/// the form that "came back by itself". The form screens were missing it.

// ---------------------------------------------------------------------------
// Typed links
// ---------------------------------------------------------------------------

/// The loaded row is passed as `extra` for an instant push; the route can
/// still rebuild it from the id alone when someone opens the link cold.
extension AppNav on BuildContext {
  void goItem(Map<String, dynamic> item) =>
      push('/item/${item['id']}', extra: item);

  void goEvent(Map<String, dynamic> event) =>
      push('/event/${event['id']}', extra: event);

  void goPost(Map<String, dynamic> post) =>
      push('/post/${post['id']}', extra: post);

  void goUser(String userId) => push('/u/$userId');

  void goSettings() => push('/settings');

  void goNotifications() => push('/notifications');

  void goFollowList(String userId, String type) => push('/u/$userId/$type');

  void goEditProfile() => push('/profile/edit');

  void goTag(String tag) => push('/tag/${Uri.encodeComponent(tag)}');

  void goPrivacyPolicy() => push('/settings/privacy');

  // ---- create / edit (forms are full-screen on phones, a dialog on wide) --

  /// New post. [sharedEvent] / [sharedListing] attach a repost.
  void goCreatePost({Map<String, dynamic>? sharedEvent, Map<String, dynamic>? sharedListing}) =>
      push(_withOrigin(this, '/create/post'), extra: {
        if (sharedEvent != null) 'sharedEvent': sharedEvent,
        if (sharedListing != null) 'sharedListing': sharedListing,
      });

  void goCreateEvent() => push(_withOrigin(this, '/create/event'));

  void goCreateListing() => push(_withOrigin(this, '/create/listing'));

  void goEditPost(Map<String, dynamic> post) =>
      push('/post/${post['id']}/edit', extra: post);

  void goEditEvent(Map<String, dynamic> event) =>
      push('/event/${event['id']}/edit', extra: event);

  void goEditListing(Map<String, dynamic> item) =>
      push('/item/${item['id']}/edit', extra: item);
}

/// `/create/...?from=<tab>` when a form is opened from a tab, so a
/// refreshed form still knows which tab it belongs to.
String _withOrigin(BuildContext context, String path) {
  final here = GoRouter.of(context).routeInformationProvider.value.uri.path;
  return kTabPaths.contains(here)
      ? Uri(path: path, queryParameters: {'from': here}).toString()
      : path;
}

// ---------------------------------------------------------------------------
// Back
// ---------------------------------------------------------------------------

/// The shell's tab roots.
const kTabPaths = {'/home', '/announcements', '/search', '/market', '/events'};

/// The logical parent of a page: where the back arrow goes ("up") when
/// the page was opened cold — a shared link, a refresh, a bookmark, a new
/// tab — so there is no in-app page underneath. With history, back always
/// returns to the page actually seen before; this is only the fallback.
///
/// A create form opened from a tab carries `?from=<tab>` and goes back up
/// to that tab.
String backFallbackFor(String location) {
  final uri = Uri.parse(location);
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.isEmpty) return '/home';

  // The form screens belong to an event: /event/:id/form, …/form/edit,
  // …/form/responses all go up to the event, not to the events list.
  if (seg.length >= 3 && seg.first == 'event' && seg[2] == 'form') {
    return '/event/${seg[1]}';
  }

  // Edit forms → the thing being edited (/post|event|item/:id/edit).
  if (seg.length == 3 && seg.last == 'edit') return '/${seg[0]}/${seg[1]}';

  switch (seg.first) {
    case 'settings':
      return seg.length > 1 ? '/settings' : '/profile';
    case 'profile':
      return seg.length > 1 ? '/profile' : '/home';
    case 'notifications':
    case 'post':
    case 'tag':
      return '/home';
    case 'u':
      // /u/:id/followers|following → that profile.
      return seg.length > 2 ? '/u/${seg[1]}' : '/home';
    case 'item':
      return '/market';
    case 'event':
      return '/events';
    case 'clubs':
      return seg.length > 1 ? '/clubs' : '/announcements';
    case 'c':
      // /c/:handle/manage → the club page; /c/:handle → the directory.
      return seg.length > 2 ? '/c/${seg[1]}' : '/clubs';
    case 'admin':
    case 'standing':
      return '/profile';
    case 'create':
      final from = uri.queryParameters['from'];
      if (from != null && kTabPaths.contains(from)) return from;
      return switch (seg.length > 1 ? seg[1] : '') {
        'listing' => '/market',
        'event' => '/events',
        _ => '/home',
      };
  }
  return '/home';
}

/// The current location as go_router sees it.
String currentPath(BuildContext context) =>
    GoRouter.of(context).routeInformationProvider.value.uri.path;

/// Back for app bars and close buttons: pops when there's a page beneath,
/// otherwise goes to the matching tab (replacing the entry, so the
/// browser's back afterwards leaves rather than bouncing).
void appBack(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.maybePop();
    return;
  }
  final fallback = backFallbackFor(
      GoRouter.of(context).routeInformationProvider.value.uri.toString());
  Router.neglect(context, () => context.go(fallback));
}

/// App-bar back arrow that always shows on pushed pages, including when
/// they were opened cold (it then goes to the matching tab).
class AppBackButton extends StatelessWidget {
  final Color? color;
  const AppBackButton({super.key, this.color});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: Icon(Icons.arrow_back, color: color),
        onPressed: () => appBack(context),
      );
}

/// Close (X) for create / edit forms; same behaviour as [appBack].
class AppCloseButton extends StatelessWidget {
  const AppCloseButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.l10n.close,
        icon: const Icon(Icons.close),
        onPressed: () => appBack(context),
      );
}

// ---------------------------------------------------------------------------
// History-aware exits (GoRoute.onExit)
// ---------------------------------------------------------------------------

/// Tracks pageless routes — dialogs, bottom sheets, menus, the photo
/// viewer — on every navigator, so a browser / system back can close the
/// topmost one first instead of leaving the page under it (rule: overlays
/// first). Each navigator needs its own instance; they share the list.
class OverlayTracker extends NavigatorObserver {
  static final List<Route<dynamic>> _open = [];

  static bool get hasOverlay => _open.any((r) => r.navigator != null);

  /// Closes the topmost overlay. Returns false if there was none.
  static bool closeTopmost() {
    _open.removeWhere((r) => r.navigator == null);
    if (_open.isEmpty) return false;
    final route = _open.removeLast();
    final navigator = route.navigator!;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
    return true;
  }

  @visibleForTesting
  static void debugReset() => _open.clear();

  static bool _isOverlay(Route<dynamic> route) => route.settings is! Page;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isOverlay(route)) _open.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _open.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _open.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _open.remove(oldRoute);
    if (newRoute != null && _isOverlay(newRoute)) _open.add(newRoute);
  }
}

/// The browser's history, behind hooks so tests can stand in a fake.
abstract final class WebHistory {
  static bool Function() isWeb = () => kIsWeb;
  static bool Function() back = browserHistoryBack;
  static bool Function() forward = browserHistoryForward;

  @visibleForTesting
  static void debugReset() {
    isWeb = () => kIsWeb;
    back = browserHistoryBack;
    forward = browserHistoryForward;
  }
}

/// `onExit` for routes pushed above the shell.
///
/// go_router calls onExit both for an in-app pop and for a navigation that
/// replaces the route (browser back / forward, `go`, `pushReplacement`).
///
/// * In-app pop on the web (app-bar back, close, code calling pop): a pop
///   would otherwise *add* a history entry, so it steps the browser back
///   instead; go_router then restores the page beneath from that entry.
///   Recognised by: the exiting page is the top of the current stack AND
///   the address bar still shows it.
///
///   Both conditions matter. When the browser restores an entry, go_router
///   rebuilds the restored stack, so pages *under* the one being left exit
///   and re-enter too — and the address bar already shows them. Checking
///   only the address bar (as before) made such a page step back a second
///   time: Home → Profile → Settings, back, landed on Home.
///
/// * Browser / system back with a dialog, sheet, menu or the photo viewer
///   open: that overlay closes and the page stays; the history step is
///   undone so the address bar keeps matching the page.
FutureOr<bool> historyAwareExit(BuildContext context, GoRouterState state) {
  if (!WebHistory.isWeb()) return true;
  // Our own forward step after closing an overlay: the browser comes back
  // to this same page; let go_router settle without treating it as a pop.
  if (_restoringAfterOverlay) {
    _restoringAfterOverlay = false;
    _restoreTimeout?.cancel();
    return true;
  }
  final router = GoRouter.of(context);
  final top = router.routerDelegate.currentConfiguration.last;
  final isTopPage = top.pageKey == state.pageKey;
  if (!isTopPage) return true; // rebuilt as part of a restored stack

  final shownInBar = router.routeInformationProvider.value.uri.path == state.matchedLocation;
  if (shownInBar) {
    // In-app pop: let the browser do it, so history stays in step.
    return !WebHistory.back();
  }

  // Browser back / forward / go away from this page.
  if (_fromBrowser(router) && OverlayTracker.closeTopmost()) {
    _restoringAfterOverlay = true;
    // Safety: never let the flag outlive the step it is for.
    _restoreTimeout?.cancel();
    _restoreTimeout = Timer(const Duration(seconds: 2), () => _restoringAfterOverlay = false);
    WebHistory.forward(); // put the address bar back on this page
    return false;
  }
  return true;
}

bool _restoringAfterOverlay = false;
Timer? _restoreTimeout;

/// Whether the pending location came from the browser (back / forward)
/// rather than from the app (go / push / pop).
bool _fromBrowser(GoRouter router) =>
    router.routeInformationProvider.value.state is! RouteInformationState;

// ---------------------------------------------------------------------------
// Unsaved forms
// ---------------------------------------------------------------------------

/// The create / edit form on screen registers how to tell whether it has
/// unsaved input, and optionally its own "discard?" dialog.
abstract final class FormGuard {
  static bool Function()? _isDirty;
  static Future<bool> Function(BuildContext context)? _confirm;

  static void register(bool Function() isDirty,
      {Future<bool> Function(BuildContext context)? confirm}) {
    _isDirty = isDirty;
    _confirm = confirm;
  }

  /// Call from the form's dispose, and before leaving on purpose
  /// (after publishing or saving).
  static void clear() {
    _isDirty = null;
    _confirm = null;
  }

  static bool get isDirty => _isDirty?.call() ?? false;

  /// True when it's fine to leave: nothing unsaved, or the user chose
  /// Discard.
  static Future<bool> confirmLeave(BuildContext context) async {
    if (!isDirty) return true;
    final ok = await (_confirm ?? confirmDiscard)(context);
    if (ok) clear(); // don't ask again for the same exit
    return ok;
  }
}

/// "Discard changes?" — Keep editing / Discard.
Future<bool> confirmDiscard(BuildContext context) async {
  final s = context.l10nRead;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.discardChangesTitle),
      content: Text(s.unsavedChanges),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.keepEditing)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.discard, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// `onExit` for create / edit routes: ask before throwing input away
/// (close button, Android back, browser back, any `go`), then leave the
/// history-aware way.
Future<bool> leaveFormRoute(BuildContext context, GoRouterState state) async {
  if (!await FormGuard.confirmLeave(context)) return false;
  if (!context.mounted) return true;
  return historyAwareExit(context, state);
}

// ---------------------------------------------------------------------------
// After publishing / saving
// ---------------------------------------------------------------------------

/// Bumped whenever a post, event or listing is created, edited or deleted,
/// so lists and detail pages can refresh — route futures don't complete
/// when the browser removes a page.
final ValueNotifier<int> contentChanges = ValueNotifier(0);

void notifyContentChanged() => contentChanges.value++;

/// After a successful publish: the form is replaced by the new item's page
/// (no history entry for the form survives), so back from that page lands
/// where the user started, not on a filled-in form.
void completePublish(BuildContext context, String location,
    {Object? extra, String? message}) {
  FormGuard.clear();
  notifyContentChanged();
  Router.neglect(context, () => context.pushReplacement(location, extra: extra));
  if (message != null) {
    showToast(message);
  }
}

/// After a successful edit: back to the page being edited, which refreshes
/// through [contentChanges].
void completeEdit(BuildContext context, {String? message}) {
  FormGuard.clear();
  notifyContentChanged();
  appBack(context);
  if (message != null) {
    showToast(message);
  }
}

/// Runs [onChange] whenever content changes, for the lifetime of a State.
mixin RefreshOnContentChange<T extends StatefulWidget> on State<T> {
  void onContentChanged();

  @override
  void initState() {
    super.initState();
    contentChanges.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) onContentChanged();
  }

  @override
  void dispose() {
    contentChanges.removeListener(_onChange);
    super.dispose();
  }
}
