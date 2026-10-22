import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/create_post_screen.dart';
import 'package:mykerawang/services/club_service.dart';

import 'helpers/feed_fixtures.dart';

/// v1.4: officers can post as their club; club posts have no anonymity.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  const options = [
    PostAsOption.self('Amir'),
    PostAsOption.club(clubId: 'c1', label: 'Kelab Fotografi', handle: 'foto'),
  ];

  Future<void> revealAnon(WidgetTester tester) => tester.scrollUntilVisible(
        find.text('Post anonymously'),
        300,
        scrollable: find
            .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
            .first,
      );

  for (final size in [kCompact, kExpanded]) {
    testWidgets('officer at ${size.width.toInt()} px: Post as club hides anonymity',
        (tester) async {
      await pumpAt(tester, size, const CreatePostScreen(postAsOptions: options));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Kelab Fotografi'), findsOneWidget); // the chip
      await revealAnon(tester);
      expect(find.text('Post anonymously'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Kelab Fotografi'));
      await tester.pumpAndSettle();
      expect(find.text('@foto'), findsOneWidget); // author row is the club
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Post anonymously'), findsNothing);
    });
  }

  testWidgets('students see no Post as row', (tester) async {
    await pumpAt(tester, kCompact,
        const CreatePostScreen(postAsOptions: [PostAsOption.self('Amir')]));
    await tester.pump();
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
