import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/create_post_screen.dart';
import 'package:mykerawang/widgets/brand/brand.dart';

import 'helpers/feed_fixtures.dart';

/// The post editor at phone / tablet / desktop: no overflow, the short
/// anonymous row with its info dialog, and a Post button.
Future<void> reveal(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
      f, 300,
      scrollable: find
          .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
          .first);

void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  for (final size in [kCompact, kMedium, kExpanded]) {
    final w = size.width.toInt();
    testWidgets('editor at $w px: no overflow', (tester) async {
      await pumpAt(tester, size, const CreatePostScreen());
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Post'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await reveal(tester, find.text('Post anonymously'));
      expect(tester.takeException(), isNull);
      expect(find.text('Your name and photo are hidden'), findsOneWidget);
      // Suggested tags are chips under the tag field.
      expect(find.widgetWithText(FilterChip, '#lostfound'), findsOneWidget);
    });
  }

  testWidgets('anonymous switch flips the author row', (tester) async {
    await pumpAt(tester, kCompact, const CreatePostScreen());
    expect(find.text('Anonymous'), findsNothing);
    await reveal(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 3000)); // back to top
    await tester.pumpAndSettle();
    expect(find.text('Anonymous'), findsOneWidget);
    expect(find.byIcon(AppIcons.anonymous), findsWidgets);
  });

  testWidgets('the long explanation sits behind the info icon', (tester) async {
    await pumpAt(tester, kCompact, const CreatePostScreen());
    expect(find.textContaining('Admins can still see'), findsNothing);
    await reveal(tester, find.byTooltip('About anonymous posts'));
    await tester.tap(find.byTooltip('About anonymous posts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Admins can still see'), findsOneWidget);
  });

  testWidgets('editing locks anonymity', (tester) async {
    await pumpAt(tester, kCompact,
        CreatePostScreen(editPost: samplePost(userId: 'me', anonymous: true)));
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);
    await reveal(tester, find.byType(Switch));
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isTrue);
    expect(sw.onChanged, isNull);
  });
}
