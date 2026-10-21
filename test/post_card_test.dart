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
