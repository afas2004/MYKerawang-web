import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/app_toast.dart';

void main() {
  Widget host() => const MaterialApp(
        home: AppToastHost(child: Scaffold(body: SizedBox.expand())),
      );

  testWidgets('goes away by itself, even with an action', (t) async {
    await t.pumpWidget(host());
    showToast('Unpinned', actionLabel: 'Undo', onAction: () {});
    await t.pumpAndSettle();
    expect(find.text('Unpinned'), findsOneWidget);
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();
    expect(find.text('Unpinned'), findsNothing);
  });

  testWidgets('the action runs once and closes it', (t) async {
    var runs = 0;
    await t.pumpWidget(host());
    showToast('Unpinned', actionLabel: 'Undo', onAction: () => runs++);
    await t.pumpAndSettle();
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(runs, 1);
    expect(find.text('Unpinned'), findsNothing);
  });

  testWidgets('a new one replaces the old one', (t) async {
    await t.pumpWidget(host());
    showToast('First');
    await t.pumpAndSettle();
    showToast('Second');
    await t.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
  });

  testWidgets('the close button dismisses it', (t) async {
    await t.pumpWidget(host());
    showToast('Saved');
    await t.pumpAndSettle();
    await t.tap(find.byType(IconButton));
    await t.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
