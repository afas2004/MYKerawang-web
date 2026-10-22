import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/edit_profile_screen.dart';

import 'helpers/pump_app.dart';

/// Regression: a bare Center in bottomNavigationBar filled the screen and
/// put "Save changes" in the middle, covering the form (v1.2.0, phone).
void main() {
  testWidgets('Save bar sits at the bottom on a 375x812 phone',
      (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const EditProfileScreen());

    expect(tester.takeException(), isNull);
    // FilledButton.icon builds a private subclass, so match by predicate.
    final save = tester.getRect(find.ancestor(
      of: find.text('Save changes'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    ));
    expect(save.bottom, greaterThan(812 - 80),
        reason: 'button should be in the bottom bar, got $save');
    expect(save.height, lessThan(80));

    // The form is visible above it.
    final username = tester.getRect(find.text('Username'));
    expect(username.bottom, lessThan(save.top));
    expect(find.text('Profile photo'), findsOneWidget);
  });
}
