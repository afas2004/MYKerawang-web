import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/share_service.dart';
import 'package:mykerawang/widgets/form_qr_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers/feed_fixtures.dart';

void main() {
  testWidgets('the dialog shows a QR of the form link, its title and actions', (t) async {
    await pumpAt(t, kCompact,
        const Scaffold(body: FormQrDialog(title: 'Borang KI Hari Sukan', path: '/f/ki-sukan')));
    final qr = t.widget<QrImageView>(find.byKey(const ValueKey('form-qr')));
    final url = ShareService.absoluteUrl('/f/ki-sukan');
    expect(url, endsWith('/f/ki-sukan'));
    expect(find.text('Borang KI Hari Sukan'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(find.byKey(const ValueKey('form-qr-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('form-qr-save')), findsOneWidget);
    expect(qr, isNotNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('a draft says it takes no answers yet', (t) async {
    await pumpAt(t, kCompact,
        const Scaffold(body: FormQrDialog(title: 'Draft', path: '/f/x', draft: true)));
    expect(find.text('Publish the form to start taking answers.'), findsOneWidget);
  });

  test('file names are safe and short', () {
    expect(FormQrDialog.fileName('Borang KI: Hari Sukan 2026!'), 'qr-borang-ki-hari-sukan-2026.png');
    expect(FormQrDialog.fileName('???'), 'qr-form.png');
    expect(FormQrDialog.fileName('a' * 80).length, lessThanOrEqualTo('qr-.png'.length + 40));
  });
}
