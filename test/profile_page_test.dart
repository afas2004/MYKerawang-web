import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/profile_screen.dart';
import 'package:mykerawang/utils/app_nav.dart';

import 'helpers/pump_app.dart';

/// Profile is a pushed page now (not a shell tab).
void main() {
  for (final width in kTestWidths) {
    testWidgets('own profile, signed out, at ${width.toInt()} px: back + login',
        (tester) async {
      await initTestSupabase(tester);
      await setWidth(tester, width);
      await pumpScreen(tester, const ProfileScreen());

      expect(tester.takeException(), isNull);
      // Outside the shell branch → a back button.
      expect(find.byType(AppBackButton), findsOneWidget);
      // Signed out → a login prompt, not "user not found".
      expect(find.text('Log in / Sign up'), findsOneWidget);
    });
  }
}
