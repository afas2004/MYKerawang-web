import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/safe_links.dart';

void main() {
  const allowed = kSeedAllowedDomains;
  List<String> links(String t) => [for (final l in findLinks(t)) l.text];
  bool ok(String link) => allowedLinkUri(link, allowed) != null;

  group('findLinks', () {
    test('http, https and bare www', () {
      expect(links('see https://forms.gle/abc now'), ['https://forms.gle/abc']);
      expect(links('see http://wa.me/60123'), ['http://wa.me/60123']);
      expect(links('go www.uitm.edu.my today'), ['www.uitm.edu.my']);
      expect(links('HTTPS://FORMS.GLE/X and WWW.Instagram.com'),
          ['HTTPS://FORMS.GLE/X', 'WWW.Instagram.com']);
    });

    test('trailing punctuation is not part of the link', () {
      expect(links('Fill it in: https://forms.gle/abc.'), ['https://forms.gle/abc']);
      expect(links('(https://forms.gle/abc)'), ['https://forms.gle/abc']);
      expect(links('link https://forms.gle/abc, then https://wa.me/1!'),
          ['https://forms.gle/abc', 'https://wa.me/1']);
      expect(links('xhttps://t.me/x?'), isEmpty); // glued to a word
      expect(links('done?https://t.me/x?'), ['https://t.me/x']);
      expect(links('"https://t.me/x"'), ['https://t.me/x']);
      expect(links('[www.youtube.com/watch?v=1];'), ['www.youtube.com/watch?v=1']);
    });

    test('a bracket the link opened stays', () {
      expect(links('https://example.com/Foo_(bar)'), ['https://example.com/Foo_(bar)']);
      expect(links('(see https://example.com/Foo_(bar))'),
          ['https://example.com/Foo_(bar)']);
    });

    test('not links', () {
      expect(links('awww.so cute'), isEmpty);
      expect(links('email me ali@www.example.com'), isEmpty);
      expect(links('https:// nothing'), isEmpty);
      expect(links('plain text forms.gle'), isEmpty); // no scheme, no www
    });

    test('stops at a backslash', () {
      expect(links(r'https://evil.com\@forms.gle'), ['https://evil.com']);
    });

    test('positions', () {
      final l = findLinks('a https://wa.me/1.').single;
      expect([l.start, l.end], [2, 17]);
    });
  });

  group('hostAllowed', () {
    test('exact and subdomains', () {
      expect(hostAllowed('forms.gle', allowed), isTrue);
      expect(hostAllowed('student.uitm.edu.my', allowed), isTrue);
      expect(hostAllowed('a.b.uitm.edu.my', allowed), isTrue);
      expect(hostAllowed('www.instagram.com', allowed), isTrue);
    });

    test('look-alikes do not match', () {
      expect(hostAllowed('evil-forms.gle.com', allowed), isFalse);
      expect(hostAllowed('forms.gle.com', allowed), isFalse);
      expect(hostAllowed('notforms.gle', allowed), isFalse);
      expect(hostAllowed('uitm.edu.my.evil.com', allowed), isFalse);
      expect(hostAllowed('xuitm.edu.my', allowed), isFalse);
      expect(hostAllowed('wa.me.evil.io', allowed), isFalse);
      expect(hostAllowed('fake-whatsapp.com', allowed), isFalse);
      expect(hostAllowed('', allowed), isFalse);
    });

    test('empty list allows nothing', () {
      expect(hostAllowed('forms.gle', const []), isFalse);
    });
  });

  group('allowedLinkUri', () {
    test('uppercase, ports, paths', () {
      expect(ok('HTTPS://FORMS.GLE/AbC'), isTrue);
      expect(ok('https://Docs.Google.com/forms/d/1/viewform'), isTrue);
      expect(ok('https://forms.gle:443/x'), isTrue);
      expect(ok('http://student.uitm.edu.my:8080/a?b=c#d'), isTrue);
      expect(ok('www.youtube.com/watch?v=1'), isTrue);
      expect(ok('https://forms.gle./x'), isTrue); // trailing-dot host
    });

    test('refused', () {
      expect(ok('https://evil-forms.gle.com/x'), isFalse);
      expect(ok('https://example.com'), isFalse);
      expect(ok('www.example.com'), isFalse);
      // The part before @ is a user name: the real host is evil.com.
      expect(ok('https://forms.gle@evil.com/x'), isFalse);
      // Allowed host, but a user-name trick: refused anyway.
      expect(ok('https://evil.com@forms.gle/x'), isFalse);
    });

    test('bare www gets https', () {
      expect(allowedLinkUri('www.uitm.edu.my/x', allowed).toString(),
          'https://www.uitm.edu.my/x');
    });
  });

  group('app links', () {
    test('kerawang.my opens inside the app', () {
      expect(isAppLink(Uri.parse('https://kerawang.my/event/1')), isTrue);
      expect(isAppLink(Uri.parse('https://www.kerawang.my/')), isTrue);
      expect(isAppLink(Uri.parse('https://kerawang.my.evil.com/')), isFalse);
      expect(appRouteOf(Uri.parse('https://kerawang.my/event/1')), '/event/1');
      expect(appRouteOf(Uri.parse('https://kerawang.my/f/abc?x=1')), '/f/abc?x=1');
      expect(appRouteOf(Uri.parse('https://kerawang.my')), '/home');
      expect(appRouteOf(Uri.parse('https://kerawang.my/')), '/home');
    });
  });

  group('linkLabel', () {
    test('short links shown whole, long ones cut to 40 with …', () {
      expect(linkLabel('https://forms.gle/abc'), 'https://forms.gle/abc');
      final long = 'https://docs.google.com/forms/d/e/1FAIpQLSexample/viewform';
      final label = linkLabel(long);
      expect(label.length, kLinkDisplayMax);
      expect(label.endsWith('…'), isTrue);
      expect(long.startsWith(label.substring(0, label.length - 1)), isTrue);
      expect(linkLabel('x' * 40), 'x' * 40);
    });
  });

  group('normalizeDomainInput', () {
    test('domains and pasted links become a host', () {
      expect(normalizeDomainInput('forms.gle'), 'forms.gle');
      expect(normalizeDomainInput('  Forms.GLE  '), 'forms.gle');
      expect(normalizeDomainInput('https://forms.gle/abc?x=1'), 'forms.gle');
      expect(normalizeDomainInput('https://www.instagram.com/kerawang/'), 'instagram.com');
      expect(normalizeDomainInput('www.uitm.edu.my'), 'uitm.edu.my');
      expect(normalizeDomainInput('student.uitm.edu.my/path'), 'student.uitm.edu.my');
      expect(normalizeDomainInput('http://example.org:8080'), 'example.org');
    });

    test('invalid input', () {
      for (final bad in [
        '', '   ', 'forms', 'not a domain', 'https://', 'mailto:x@y.com',
        'https://user@evil.com', 'a..com', '-bad.com', 'exa_mple.com', '1.2.3.4',
      ]) {
        expect(normalizeDomainInput(bad), isNull, reason: bad);
      }
    });
  });
}
