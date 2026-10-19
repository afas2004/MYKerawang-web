import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/access_strings.dart';
import '../language_cubit.dart';
import 'report_helper.dart';
import 'app_nav.dart';

/// Shared links open read-only for visitors who aren't logged in
/// (/event, /item, /post, /u). These helpers gate the actions on those
/// pages and bring the visitor back to the same page after login.

bool get isLoggedIn => Supabase.instance.client.auth.currentSession != null;

/// Only same-app paths are honoured as a post-login destination: an
/// absolute URL or `//host` would make `?from=` an open redirect.
String? safeReturnPath(String? from) {
  if (from == null || from.isEmpty) return null;
  if (!from.startsWith('/') || from.startsWith('//')) return null;
  final path = Uri.tryParse(from)?.path ?? '';
  if (path == '/login' || path == '/') return null;
  return from;
}

/// `/login`, remembering [from] when it's worth returning to.
String loginPathFor(String? from) {
  final safe = safeReturnPath(from);
  if (safe == null || safe == '/home') return '/login';
  return Uri(path: '/login', queryParameters: {'from': safe}).toString();
}

/// The page currently shown, as a path + query (OAuth `code` dropped).
String currentLocation(BuildContext context) {
  final uri = GoRouter.of(context).routerDelegate.currentConfiguration.uri;
  final query = Map.of(uri.queryParameters)..remove('code');
  return Uri(path: uri.path, queryParameters: query.isEmpty ? null : query)
      .toString();
}

/// Sends the visitor to the login page, returning here afterwards.
void goToLogin(BuildContext context) =>
    context.go(loginPathFor(currentLocation(context)));

/// True when logged in. Otherwise explains why and offers to log in
/// (returning to this page), and answers false so the caller stops.
bool requireLogin(BuildContext context) {
  if (isLoggedIn) return true;
  final s = context.l10nRead;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.guestPromptTitle),
      content: Text(s.guestPromptBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(s.notNow),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            goToLogin(context);
          },
          child: Text(s.loginOrSignUp),
        ),
      ],
    ),
  );
  return false;
}

/// Back button for pages that can be opened cold from a shared link,
/// where there is nothing underneath to pop to.
///
/// Opened cold, back goes to the matching tab (item → Market, event →
/// Events, post / user → Home) — see [appBack].
void popOrHome(BuildContext context) => appBack(context);

/// Full-width "Log in to …" bar used in place of an action bar for guests.
class GuestActionBar extends StatelessWidget {
  final String label;
  const GuestActionBar({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => goToLogin(context),
        icon: const Icon(Icons.login, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

/// [ReportMenuButton] for pages guests can open: for them the same icon
/// asks them to log in instead of opening the menu.
class GuardedReportButton extends StatelessWidget {
  final String targetId;
  final String type;
  final Widget? icon;
  final double? iconSize;
  final String? label;

  const GuardedReportButton({
    super.key,
    required this.targetId,
    required this.type,
    this.icon,
    this.iconSize,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn) {
      return ReportMenuButton(
        targetId: targetId,
        type: type,
        icon: icon,
        iconSize: iconSize,
        label: label,
      );
    }
    return IconButton(
      tooltip: context.l10n.more,
      icon: icon ??
          Icon(Icons.more_vert,
              size: iconSize,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: () => requireLogin(context),
    );
  }
}
