import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/app_links.dart';

void main() {
  group('userIdFromProfileCode', () {
    test('https profile link', () {
      expect(userIdFromProfileCode('https://mykerawang-app.web.app/u/abc-123'),
          'abc-123');
      expect(userIdFromProfileCode('http://localhost:5000/u/abc'), 'abc');
    });

    test('legacy custom scheme', () {
      expect(userIdFromProfileCode('mykerawang://user/abc-123'), 'abc-123');
    });

    test('rejects other codes', () {
      expect(userIdFromProfileCode('https://example.com/post/1'), isNull);
      expect(userIdFromProfileCode('https://example.com/u/1/extra'), isNull);
      expect(userIdFromProfileCode('hello world'), isNull);
      expect(userIdFromProfileCode(''), isNull);
    });
  });
}
