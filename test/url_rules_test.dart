import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/utils/filter_rules.dart';
import 'package:mykerawang/utils/url_rules.dart';

/// Links and search terms are the two places user text reaches an interpreter:
/// the browser/OS (launchUrl) and PostgREST's filter string.
void main() {
  group('launchableUri', () {
    test('web links and contact schemes are allowed', () {
      expect(launchableUri('https://forms.gle/abc')?.host, 'forms.gle');
      expect(launchableUri('http://example.invalid/x')?.scheme, 'http');
      expect(launchableUri('mailto:a@b.my')?.scheme, 'mailto');
      expect(launchableUri('tel:+60123456789')?.scheme, 'tel');
      expect(launchableUri('  https://mykerawang-app.web.app/u/x  ')?.host,
          'mykerawang-app.web.app');
    });

    test('code-bearing schemes are refused', () {
      expect(launchableUri('javascript:alert(1)'), isNull);
      expect(launchableUri('JavaScript:alert(1)'), isNull);
      expect(launchableUri('data:text/html,<script>alert(1)</script>'), isNull);
      expect(launchableUri('file:///etc/passwd'), isNull);
      expect(launchableUri('intent://scan/#Intent;scheme=zxing;end'), isNull);
      expect(launchableUri('content://com.android.contacts/1'), isNull);
      // a Telegram handle that is really a URL
      expect(launchableUri('javascript:/alert(1)'), isNull);
    });

    test('rubbish and relative paths are refused', () {
      expect(launchableUri(''), isNull);
      expect(launchableUri('/event/e1'), isNull);
      expect(launchableUri('not a url'), isNull);
      expect(launchableUri('https://'), isNull); // no host
    });
  });

  group('validateHttpsUrl (registration links)', () {
    test('https only', () {
      expect(validateHttpsUrl('https://forms.gle/abc'), isNull);
      // A script URL is refused; the code (bad url vs not https) only picks
      // which sentence the organiser reads.
      expect(validateHttpsUrl('javascript:alert(1)'), isNotNull);
      expect(validateHttpsUrl('http://forms.gle/abc'), ActionLinkIssue.notHttps);
      expect(validateHttpsUrl('forms.gle/abc'), ActionLinkIssue.badUrl);
      expect(validateHttpsUrl('  '), ActionLinkIssue.emptyUrl);
    });
  });

  group('filterSafe', () {
    test('strips the characters that mean structure inside a filter', () {
      expect(filterSafe('ali,status.eq.banned'), 'ali status.eq.banned');
      expect(filterSafe('name(1)'), 'name 1');
      expect(filterSafe('a"b\\c:d'), 'a b c d');
    });

    test('keeps the words, collapses spaces', () {
      expect(filterSafe('  kelab   bahasa  '), 'kelab bahasa');
      expect(filterSafe('50%'), '50%');
    });

    test('an all-structure query becomes empty', () {
      expect(filterSafe('(),'), '');
    });
  });
}
