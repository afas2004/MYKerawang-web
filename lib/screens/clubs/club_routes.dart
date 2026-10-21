import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_sidebar.dart';
import 'club_directory_screen.dart';
import 'club_manage_screen.dart';
import 'club_page_screen.dart';
import 'club_register_screen.dart';

/// Club routes, spread into the router's list with one line:
/// `...clubRoutes(_rootKey).map(_withHistoryAwareExit)`.
///   /clubs                 directory
///   /clubs/register        request a club page
///   /c/:handle             club page
///   /c/:handle/manage      officers: edit page, officers, transfer
List<RouteBase> clubRoutes(GlobalKey<NavigatorState> rootKey) => [
      GoRoute(
        path: '/clubs',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            const DesktopChrome(maxWidth: 1100, child: ClubDirectoryScreen()),
      ),
      GoRoute(
        path: '/clubs/register',
        parentNavigatorKey: rootKey,
        builder: (context, state) => const DesktopChrome(child: ClubRegisterScreen()),
      ),
      GoRoute(
        path: '/c/:handle',
        parentNavigatorKey: rootKey,
        builder: (context, state) => DesktopChrome(
          maxWidth: 1000,
          child: ClubPageScreen(handle: state.pathParameters['handle']!),
        ),
      ),
      GoRoute(
        path: '/c/:handle/manage',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            DesktopChrome(child: ClubManageScreen(handle: state.pathParameters['handle']!)),
      ),
    ];
