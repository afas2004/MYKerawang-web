import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/mention_service.dart';
import 'package:mykerawang/utils/tags.dart';

void main() {
  group('normalizeTag', () {
    test('lowercases and strips #', () {
      expect(normalizeTag('#Question'), 'question');
      expect(normalizeTag('##Rant '), 'rant');
      expect(normalizeTag('#'), '');
    });

    test('every Lost & Found spelling becomes lostfound', () {
      for (final raw in [
        'Lost&Found',
        'lost&found',
        '#LostFound',
        'lost-found',
        'lost_found',
        'LOSTFOUND',
      ]) {
        expect(normalizeTag(raw), kLostFoundTag, reason: raw);
      }
    });

    test('leaves other tags with & or - alone', () {
      expect(normalizeTag('R&D'), 'r&d');
      expect(normalizeTag('final-exam'), 'final-exam');
    });
  });

  group('parseTags', () {
    test('reads hashtags or bare words, deduped in order', () {
      expect(parseTags('#Question #rant question'), ['question', 'rant']);
    });

    test('merges Lost&Found variants', () {
      expect(parseTags('#Lost&Found #lostfound #LostFound'), ['lostfound']);
    });

    test('empty input gives no tags', () {
      expect(parseTags(''), isEmpty);
      expect(parseTags('   # '), isEmpty);
    });
  });

  test('displayTag shows the stored form with #', () {
    expect(displayTag('lost&found'), '#lostfound');
    expect(displayTag('Academic'), '#academic');
  });

  test('tagAliases covers the legacy lost&found spelling', () {
    expect(tagAliases('lostfound'), containsAll(['lostfound', 'lost&found']));
    expect(tagAliases('#Rant'), containsAll(['rant', 'Rant', '#rant']));
  });

  group('v1.3: hashtag feed matched nothing for legacy rows', () {
    // How the first editors stored tags (ChoiceChip label as typed).
    final legacy = {'tags': ['Rant', 'Lost&Found']};
    final hashed = {'tags': ['#rant']};

    // PostgREST `ov` is exact element overlap — simulate it.
    bool overlaps(Map<String, dynamic> row, List<String> values) =>
        List<String>.from(row['tags']).any(values.contains);

    test('the old query values missed them (the bug)', () {
      expect(overlaps(legacy, ['rant']), isFalse);
    });

    test('tagAliases now matches every legacy spelling', () {
      expect(overlaps(legacy, tagAliases('rant')), isTrue);
      expect(overlaps(hashed, tagAliases('rant')), isTrue);
      expect(overlaps(legacy, tagAliases('lostfound')), isTrue);
    });

    test('postHasTag / normalizeTags agree with the SQL backfill', () {
      expect(postHasTag(legacy, '#RANT'), isTrue);
      expect(postHasTag(legacy, 'lostfound'), isTrue);
      expect(normalizeTags(['Rant', '#rant', ' Lost&Found ', 'Academic', '']),
          ['rant', 'lostfound', 'academic']);
    });
  });

  group('MentionService.usernamesIn', () {
    test('finds unique usernames without @', () {
      expect(MentionService.usernamesIn('hi @amir and @siti, @amir again'),
          {'amir', 'siti'});
    });

    test('stops at punctuation and keeps underscores/digits', () {
      expect(MentionService.usernamesIn('(@ali_99) @x.'), {'ali_99', 'x'});
    });

    test('no mentions', () {
      expect(MentionService.usernamesIn('email me at nobody'), isEmpty);
      expect(MentionService.usernamesIn('@'), isEmpty);
    });

    test('a username in an email address is still picked up', () {
      // Documents current behaviour: the pattern is not anchored, so
      // "a@b" mentions "b". Harmless (no such user → no notification).
      expect(MentionService.usernamesIn('a@b'), {'b'});
    });
  });
}
