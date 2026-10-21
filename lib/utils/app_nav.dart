import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../language_cubit.dart';
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
      push('/create/post', extra: {
        if (sharedEvent != null) 'sharedEvent': sharedEvent,
        if (sharedListing != null) 'sharedListing': sharedListing,
      });

  void goCreateEvent() => push('/create/event');

  void goCreateListing() => push('/create/listing');

  void goEditPost(Map<String, dynamic> post) =>
      push('/post/${post['id']}/edit', extra: post);

  void goEditEvent(Map<String, dynamic> event) =>
      push('/event/${event['id']}/edit', extra: event);

  void goEditListing(Map<String, dynamic> item) =>
      push('/item/${item['id']}/edit', extra: item);
}

// ---------------------------------------------------------------------------
// Back
// ---------------------------------------------------------------------------

/// Where "back" goes when there's nothing to go back to (a page opened
/// cold from a shared link, a refresh, a bookmark).
String backFallbackFor(String path) {
  final segments = Uri.parse(path).pathSegments;
  if (segments.isEmpty) return '/home';
  // An edit form backs out to the thing being edited.
  if (segments.length >= 3 && segments.last == 'edit') {
    return '/${segments[0]}/${segments[1]}';
  }
  return switch (segments.first) {
    'item' => '/market',
    'event' => '/events',
    'create' => switch (segments.length > 1 ? segments[1] : '') {
        'listing' => '/market',
        'event' => '/events',
        _ => '/home',
      },
    'settings' when segments.length > 1 => '/settings',
    // /profile/edit backs out to the profile; /profile itself (no longer
    // a tab) to Home.
    'profile' when segments.length > 1 => '/profile',
    _ => '/home', // post, u, tag, notifications, settings, …
  };
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
  final fallback = backFallbackFor(currentPath(context));
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

/// `onExit` for routes pushed above the shell.
///
/// go_router calls onExit both for an in-app pop and for a navigation that
/// replaces the route (browser back, `go`, `pushReplacement`). On the web
/// an in-app pop would otherwise *add* a browser history entry — which is
/// why back used to walk through every earlier step. Instead, an in-app
/// pop steps the browser back; go_router then restores the page beneath
/// from that history entry (calling onExit again, this time letting it go).
///
/// An in-app pop is recognisable because the location hasn't changed yet.
FutureOr<bool> historyAwareExit(BuildContext context, GoRouterState state) {
  if (!kIsWeb) return true;
  final provider = GoRouter.of(context).routeInformationProvider;
  final stillHere = provider.value.uri.path == state.matchedLocation;
  if (stillHere && browserHistoryBack()) return false;
  return true;
}

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
  final messenger = ScaffoldMessenger.maybeOf(context);
  Router.neglect(context, () => context.pushReplacement(location, extra: extra));
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// After a successful edit: back to the page being edited, which refreshes
/// through [contentChanges].
void completeEdit(BuildContext context, {String? message}) {
  FormGuard.clear();
  notifyContentChanged();
  final messenger = ScaffoldMessenger.maybeOf(context);
  appBack(context);
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
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
