import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_sidebar.dart';
import '../../widgets/error_state.dart';
import '../standing_screen.dart';
// Deferred: the admin console is ~5,000 lines only a handful of people ever
// open. Where the compiler supports splitting, its code downloads the first
// time /admin is opened instead of with everyone's first visit.
import 'admin_screen.dart' deferred as admin;
import 'club_registry_screen.dart' deferred as registry;
import '../clubs/club_routes.dart' show clubsOffRedirect;

export '../clubs/club_routes.dart' show clubRoutes;

/// Moderation routes, spread into the router's list so router.dart only
/// needs one line: `...moderationRoutes(_rootKey)`.
///   /admin                    console (the screen checks is_admin; so does the DB)
///   /admin/clubs/registry     recognised clubs students can register
///   /standing                 the user's own restrictions, decisions and appeals
List<RouteBase> moderationRoutes(GlobalKey<NavigatorState> rootKey) => [
      GoRoute(
        path: '/admin',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            DesktopChrome(maxWidth: 1000, child: DeferredPage(admin.loadLibrary, () => admin.AdminScreen())),
      ),
      GoRoute(
        path: '/admin/clubs/registry',
        parentNavigatorKey: rootKey,
        redirect: clubsOffRedirect,
        builder: (context, state) =>
            DesktopChrome(maxWidth: 900, child: DeferredPage(registry.loadLibrary, () => registry.ClubRegistryScreen())),
      ),
      GoRoute(
        path: '/standing',
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DesktopChrome(child: StandingScreen()),
      ),
    ];

/// Shows a spinner while a deferred library downloads, then the page. A
/// failed download (offline) offers a retry instead of a blank screen.
class DeferredPage extends StatefulWidget {
  final Future<void> Function() load;
  final Widget Function() page;
  const DeferredPage(this.load, this.page, {super.key});

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  late Future<void> _loading = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: ErrorState(onRetry: () => setState(() => _loading = widget.load())),
          );
        }
        return widget.page();
      },
    );
  }
}
