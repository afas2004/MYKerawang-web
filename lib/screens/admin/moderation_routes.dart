import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_sidebar.dart';
import '../standing_screen.dart';
import 'admin_screen.dart';

/// Moderation routes, spread into the router's list so router.dart only
/// needs one line: `...moderationRoutes(_rootKey)`.
///   /admin     console (the screen checks is_admin; so does the DB)
///   /standing  the user's own restrictions, decisions and appeals
List<RouteBase> moderationRoutes(GlobalKey<NavigatorState> rootKey) => [
      GoRoute(
        path: '/admin',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            const DesktopChrome(maxWidth: 1000, child: AdminScreen()),
      ),
      GoRoute(
        path: '/standing',
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DesktopChrome(child: StandingScreen()),
      ),
    ];
