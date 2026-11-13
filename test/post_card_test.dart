import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/services/post_service.dart';
import 'package:mykerawang/services/moderation_service.dart';
import 'package:mykerawang/services/saved_items.dart';
import 'package:mykerawang/theme/app_icons.dart';
import 'package:mykerawang/widgets/post_card.dart';
import 'package:mykerawang/widgets/post_card_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PostCard with injected rows — no Supabase.
void main() {
  const en = AppStrings.en;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PostService.debugCurrentUserId = () => 'me';
    ModerationService.debugCurrentUserId = () => 'me';
    ModerationService.debugMyRole = () async => 'student';
    SavedItems.debugSignedIn = () => false;
  });
  tearDown(() {
    PostService.debugCurrentUserId = null;
    ModerationService.debugCurrentUserId = null;
    ModerationService.debugMyRole = null;
    SavedItems.debugSignedIn = null;
  });

  Map<String, dynamic> post({
    String? title = 'Lost wallet',
    String? body = 'Brown, near the library',
    bool anonymous = false,
    String? userId = 'someone',
    String? imageUrl,
    List<String> gallery = const [],
    List<String> tags = const [],
  }) =>
      {
        'id': 'p1',
        'title': title,
        'body': body,
        'is_anonymous': anonymous,
        'user_id': anonymous ? null : userId,
        'profiles': anonymous
            ? null
            : {
                'id': userId,
                'username': 'amir',
                'display_name': 'Amir',
                'avatar_url': null,
              },
        'image_url': imageUrl,
        'gallery_urls': gallery,
        'tags': tags,
        'comment_count': 2,
        'created_at': DateTime.now().toIso8601String(),
      };

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with a title: title then body', (tester) async {
    await pump(tester, PostCard(post: post()));
    expect(find.text('Lost wallet'), findsOneWidget);
    expect(find.text('Amir'), findsOneWidget);
    expect(find.textContaining('@amir'), findsOneWidget);
    expect(find.text(en.untitled), findsNothing);
  });

  testWidgets('without a title: no placeholder, body leads', (tester) async {
    await pump(tester, PostCard(post: post(title: null)));
    expect(find.text(en.untitled), findsNothing);
    expect(find.text('Lost wallet'), findsNothing);
    // MentionText renders through RichText.
    expect(find.textContaining('Brown, near the library', findRichText: true),
        findsOneWidget);
  });

  testWidgets('blank title is treated as none', (tester) async {
    await pump(tester, PostCard(post: post(title: '   ')));
    expect(find.text(en.untitled), findsNothing);
  });

  testWidgets('anonymous: no name or handle, anonymous label', (tester) async {
    await pump(tester, PostCard(post: post(anonymous: true)));
    expect(find.text(en.anonymous), findsOneWidget);
    expect(find.text('Amir'), findsNothing);
    expect(find.textContaining('@amir'), findsNothing);
    expect(find.byIcon(AppIcons.anonymous), findsOneWidget);
    expect(find.byTooltip(en.postedAnonymously), findsOneWidget);
  });

  testWidgets('no photos: no photo block', (tester) async {
    await pump(tester, PostCard(post: post()));
    expect(find.bySemanticsLabel(RegExp('Post photo')), findsNothing);
  });

  testWidgets('photos: labelled cover and a count when several',
      (tester) async {
    await pump(
      tester,
      PostCard(
        post: post(
          imageUrl: 'https://example.invalid/a.jpg',
          gallery: ['https://example.invalid/b.jpg'],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Post photo 1 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Post photo 2 of 2'), findsOneWidget);
  });

  group('compact feed card', () {
    final long = List.filled(
            12, 'Patience is a virtue and great leaders let things happen.')
        .join('\n');
    final many = [
      for (var i = 1; i < 5; i++) 'https://example.invalid/$i.jpg',
    ];

    RichText bodyText(WidgetTester tester) => tester.widget<RichText>(find
        .descendant(
            of: find.byType(PostBodyPreview), matching: find.byType(RichText))
        .first);

    testWidgets('long body stops at 5 lines with Read more', (tester) async {
      var opened = 0;
      await pump(
          tester, PostCard(post: post(body: long), onTap: () => opened++));
      expect(bodyText(tester).maxLines, 5);
      expect(bodyText(tester).overflow, TextOverflow.ellipsis);
      expect(find.text('Read more'), findsOneWidget);
      await tester.tap(find.text('Read more'));
      expect(opened, 1);
    });

    testWidgets('short body: no Read more', (tester) async {
      await pump(tester, PostCard(post: post()));
      expect(find.text('Read more'), findsNothing);
    });

    testWidgets('post page (expanded) shows the whole body', (tester) async {
      await pump(tester, PostCard(post: post(body: long), expanded: true));
      expect(find.byType(PostBodyPreview), findsNothing);
      expect(find.text('Read more'), findsNothing);
      expect(find.byType(PostPhotoPreview), findsNothing);
    });

    testWidgets('several photos: one short row with +N', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        PostCard(
            post: post(imageUrl: 'https://example.invalid/0.jpg', gallery: many)),
      );
      expect(find.byType(PostPhotoPreview), findsOneWidget);
      expect(find.text('+2'), findsOneWidget); // 5 photos, 3 shown
      expect(tester.getSize(find.byType(PostPhotoPreview)).height,
          lessThanOrEqualTo(140));
    });

    testWidgets('one photo is at most 190 px tall on a phone', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester,
          PostCard(post: post(imageUrl: 'https://example.invalid/0.jpg')));
      expect(tester.getSize(find.byType(PostPhotoPreview)).height,
          lessThanOrEqualTo(190));
    });

    for (final size in const [Size(320, 568), Size(1280, 800)]) {
      testWidgets('fits at ${size.width.toInt()}×${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final photos in [
          <String>[],
          ['https://example.invalid/a.jpg'],
          many,
        ]) {
          await pump(
            tester,
            PostCard(
              key: UniqueKey(),
              post: post(
                title: 'A very long title ' * 6,
                body: long,
                imageUrl: photos.isEmpty ? null : photos.first,
                gallery: photos.skip(1).toList(),
                tags: ['question', 'events'],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Read more'), findsOneWidget);
          // The whole card stays shorter than one screen.
          expect(tester.getSize(find.byType(PostCard)).height,
              lessThan(size.height));
        }
      });
    }
  });

  testWidgets('tags show as #text, Lost&Found as #lostfound', (tester) async {
    String? tapped;
    await pump(
      tester,
      PostCard(
        post: post(tags: ['question', 'lost&found']),
        onTagTap: (t) => tapped = t,
      ),
    );
    expect(find.text('#question'), findsOneWidget);
    expect(find.text('#lostfound'), findsOneWidget);
    await tester.tap(find.text('#lostfound'));
    expect(tapped, 'lostfound');
  });

  testWidgets('own post shows Post options; others show More',
      (tester) async {
    await pump(tester, PostCard(post: post(userId: 'me')));
    expect(find.byTooltip('Post options'), findsOneWidget);

    await pump(tester, PostCard(key: UniqueKey(), post: post()));
    expect(find.byTooltip('Post options'), findsNothing);
    expect(find.byTooltip(en.more), findsOneWidget);
  });

  testWidgets('deleted elsewhere: card hides itself', (tester) async {
    await pump(tester, PostCard(post: post()));
    expect(find.text('Lost wallet'), findsOneWidget);
    // Simulate the change stream without a server round trip.
    PostService.debugEmit(const PostChange.deleted('p1'));
    await tester.pump(); // deliver the broadcast event
    await tester.pump();
    expect(find.text('Lost wallet'), findsNothing);
  });

  testWidgets('skeleton list announces loading', (tester) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(builder: (c) => PostCardSkeleton.list(c)),
            ),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading posts'), findsOneWidget);
    expect(find.byType(PostCardSkeleton), findsNWidgets(4));
  });
}
