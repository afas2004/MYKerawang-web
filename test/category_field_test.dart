import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/category_field.dart';

import 'helpers/feed_fixtures.dart';

/// Category entry is a text field with suggestions now, not a wall of chips.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  Widget host(List<String> initial, void Function(List<String>) onChanged) {
    var value = initial;
    return StatefulBuilder(
      builder: (context, setState) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: CategoryField(
            kind: 'event',
            value: value,
            onChanged: (v) {
              setState(() => value = v);
              onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  testWidgets('typing suggests a category and picking it adds a chip', (tester) async {
    final changes = <List<String>>[];
    await pumpAt(tester, kCompact, host(const [], changes.add));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'enter');
    await tester.pumpAndSettle();

    expect(find.text('Entertainment'), findsWidgets);

    await tester.tap(find.text('Entertainment').last);
    await tester.pumpAndSettle();

    expect(changes.last, ['entertainment']);
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Entertainment'), findsOneWidget);
  });

  testWidgets('the field clears after a pick, ready for the next one', (tester) async {
    await pumpAt(tester, kCompact, host(const [], (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'work');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workshops & training').last);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('a selected chip can be removed', (tester) async {
    final changes = <List<String>>[];
    await pumpAt(tester, kCompact, host(const ['games', 'workshop'], changes.add));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(2));

    final chip = tester.widget<InputChip>(find.byType(InputChip).first);
    chip.onDeleted!();
    await tester.pumpAndSettle();

    expect(changes.last, ['workshop']);
  });

  testWidgets('the maximum is enforced', (tester) async {
    final changes = <List<String>>[];
    await pumpAt(tester, kCompact,
        host(const ['academic', 'games', 'workshop'], changes.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'tech');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tech').last);
    await tester.pumpAndSettle();

    // three + tech is still under five, so it lands
    expect(changes.last.length, 4);
  });
}
