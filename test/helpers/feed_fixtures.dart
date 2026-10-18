import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/services/moderation_service.dart';
import 'package:mykerawang/services/post_service.dart';
import 'package:mykerawang/services/saved_items.dart';
import 'package:mykerawang/widgets/comment_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supabase-free hooks for widgets that read the session (PostCard,
/// SaveButton, PinMenuButton). Call from setUp; [resetFeedHooks] in tearDown.
void installFeedHooks({String me = 'me', bool signedIn = false}) {
  SharedPreferences.setMockInitialValues({});
  PostService.debugCurrentUserId = () => me;
  ModerationService.debugCurrentUserId = () => me;
  ModerationService.debugMyRole = () async => 'student';
  SavedItems.debugSignedIn = () => signedIn;
  CommentTile.debugLoggedIn = true;
}

void resetFeedHooks() {
  PostService.debugCurrentUserId = null;
  ModerationService.debugCurrentUserId = null;
  ModerationService.debugMyRole = null;
  SavedItems.debugSignedIn = null;
  CommentTile.debugLoggedIn = null;
}

/// A posts_public-shaped row.
Map<String, dynamic> samplePost({
  String id = 'p1',
  String? title = 'Lost wallet',
  String? body = 'Brown, near the library. Ada sesiapa nampak? @amir',
  bool anonymous = false,
  String userId = 'someone',
  bool verified = false,
  bool pinned = false,
  int photos = 0,
  List<String> tags = const [],
  int comments = 2,
}) {
  final urls = [for (var i = 0; i < photos; i++) 'https://example.invalid/$id-$i.jpg'];
  return {
    'id': id,
    'title': title,
    'body': body,
    'is_anonymous': anonymous,
    'is_pinned': pinned,
    'user_id': anonymous ? null : userId,
    'profiles': anonymous
        ? null
        : {
            'id': userId,
            'username': 'amir_the_long_username_kolej',
            'display_name': 'Amir bin Abdullah Kolej Kerawang',
            'avatar_url': null,
            'is_verified': verified,
          },
    'image_url': urls.isEmpty ? null : urls.first,
    'gallery_urls': urls.skip(1).toList(),
    'tags': tags,
    'comment_count': comments,
    'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
  };
}

Map<String, dynamic> sampleEvent(String id) => {
      'id': id,
      'type': 'event',
      'title': 'Malam Kebudayaan $id',
      'start_datetime': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      'end_datetime': DateTime.now().add(const Duration(days: 2, hours: 3)).toIso8601String(),
      'location': 'Dewan Kolej',
      'image_url': null,
    };

Map<String, dynamic> sampleListing(String id) => {
      'id': id,
      'type': 'listing',
      'title': 'Kettle $id',
      'price': 15,
      'image_url': null,
    };

/// MaterialApp + LanguageCubit at a fixed logical size.
Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
}

const kCompact = Size(375, 812);
const kMedium = Size(768, 1024);
const kExpanded = Size(1280, 900);
