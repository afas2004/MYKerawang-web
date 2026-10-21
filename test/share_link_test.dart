import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/share_service.dart';

/// Chat and share texts carry the exact page URL.
void main() {
  test('absoluteUrl points at the deployed app off the web', () {
    expect(ShareService.absoluteUrl('/item/abc'), '$kAppBaseUrl/item/abc');
    expect(ShareService.absoluteUrl('/event/xyz'), '$kAppBaseUrl/event/xyz');
  });

  test('withPageLink puts the URL on its own line after the text', () {
    final msg = ShareService.withPageLink('Hi! I am interested', '/item/abc');
    expect(msg, 'Hi! I am interested\n$kAppBaseUrl/item/abc');
  });
}
