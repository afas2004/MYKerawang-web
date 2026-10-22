import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/profile_avatar_action.dart';

import 'helpers/feed_fixtures.dart';

/// Home app bar: avatar action always; the bell only when signed in;
/// no settings icon (it lives behind the avatar / in Profile).
void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    ShellAuth.debugLoggedIn = null;
  });

  Widget bar() => Scaffold(
        appBar: AppBar(
          actions: [
            Builder(
              builder: (context) => Row(
                mainAxisSize: MainAxisSize.min,
                children: homeAppBarActions(context, onRefresh: () {}, unreadBadge: false),
              ),
            ),
          ],
        ),
      );

  testWidgets('signed in: bell + avatar, no settings', (tester) async {
    ShellAuth.debugLoggedIn = true;
    await pumpAt(tester, kCompact, bar());
    expect(tester.takeException(), isNull);
    expect(find.byIcon(AppIcons.notifications), findsOneWidget);
    expect(find.byType(ProfileAvatarAction), findsOneWidget);
    expect(find.byIcon(AppIcons.settings), findsNothing);
  });

  testWidgets('guest: no bell, avatar action still there', (tester) async {
    ShellAuth.debugLoggedIn = false;
    await pumpAt(tester, kCompact, bar());
    expect(tester.takeException(), isNull);
    expect(find.byIcon(AppIcons.notifications), findsNothing);
    expect(find.byType(ProfileAvatarAction), findsOneWidget);
  });
}
