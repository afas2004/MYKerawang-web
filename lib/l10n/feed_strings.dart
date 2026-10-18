import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../language_cubit.dart';
import 'app_strings.dart';

/// Copy for the feed / post redesign (ui/feed). Kept beside [AppStrings]
/// so parallel UI work doesn't collide on app_strings.dart; fold in later.
/// English and Malay (BM-mix voice); Japanese maps to English.
///
/// Usage: `context.feedL10n.share` in build, `context.feedL10nRead` in
/// callbacks.
class FeedStrings {
  // Post card
  final String commentAction;
  final String shareAction;
  final String commentsCountLabel; // a11y: "{0} comments"
  final String anonymousSub;
  final String verified;
  final String official;
  final String morePhotos; // "+{0}"
  final String photoOf; // "Photo {0} of {1}"

  // Composer + create
  final String composerHintCompact;
  final String addPhotoAction;
  final String postingAs; // "Posting as {0}"
  final String anonExplain;
  final String bodyHint;
  final String charCount; // "{0}/{1}"
  final String tooLong;
  final String tagFieldHint;
  final String suggestedTags;
  final String removeTag; // a11y: "Remove {0}"
  final String shortcutHint;
  final String discardPostTitle;
  final String discardPostBody;

  // Post detail
  final String anonToggle;
  final String anonToggleOn;
  final String replyingAs; // "Commenting as {0}"
  final String commentCount; // "{0} comments" header

  // Tag feed
  final String tagPostCount; // "{0} posts"
  final String tagPostCountOne;

  // Feed
  final String feedEnd;

  const FeedStrings({
    required this.commentAction,
    required this.shareAction,
    required this.commentsCountLabel,
    required this.anonymousSub,
    required this.verified,
    required this.official,
    required this.morePhotos,
    required this.photoOf,
    required this.composerHintCompact,
    required this.addPhotoAction,
    required this.postingAs,
    required this.anonExplain,
    required this.bodyHint,
    required this.charCount,
    required this.tooLong,
    required this.tagFieldHint,
    required this.suggestedTags,
    required this.removeTag,
    required this.shortcutHint,
    required this.discardPostTitle,
    required this.discardPostBody,
    required this.anonToggle,
    required this.anonToggleOn,
    required this.replyingAs,
    required this.commentCount,
    required this.tagPostCount,
    required this.tagPostCountOne,
    required this.feedEnd,
  });

  static const en = FeedStrings(
    commentAction: "Comment",
    shareAction: "Share",
    commentsCountLabel: "{0} comments",
    anonymousSub: "Name hidden",
    verified: "Verified",
    official: "Official",
    morePhotos: "+{0}",
    photoOf: "Photo {0} of {1}",
    composerHintCompact: "Share something with kolej…",
    addPhotoAction: "Add photos",
    postingAs: "Posting as {0}",
    anonExplain:
        "Your name and photo are hidden from everyone, including people you mention. Admins can still see who posted if it's reported.",
    bodyHint: "What's on your mind? Use @ to mention someone",
    charCount: "{0}/{1}",
    tooLong: "A bit too long — trim it to {0} characters",
    tagFieldHint: "Add tags — press space or enter",
    suggestedTags: "Suggested",
    removeTag: "Remove {0}",
    shortcutHint: "Ctrl + Enter to post",
    discardPostTitle: "Discard this post?",
    discardPostBody: "What you've written will be lost.",
    anonToggle: "Comment anonymously",
    anonToggleOn: "Anonymous — your name is hidden",
    replyingAs: "Commenting as {0}",
    commentCount: "{0} comments",
    tagPostCount: "{0} posts",
    tagPostCountOne: "1 post",
    feedEnd: "You're all caught up",
  );

  static const ms = FeedStrings(
    commentAction: "Komen",
    shareAction: "Kongsi",
    commentsCountLabel: "{0} komen",
    anonymousSub: "Nama disembunyikan",
    verified: "Disahkan",
    official: "Rasmi",
    morePhotos: "+{0}",
    photoOf: "Gambar {0} daripada {1}",
    composerHintCompact: "Kongsi sesuatu dengan kolej…",
    addPhotoAction: "Tambah gambar",
    postingAs: "Post sebagai {0}",
    anonExplain:
        "Nama dan gambar kau disembunyikan daripada semua orang, termasuk yang kau mention. Admin masih boleh tengok siapa yang post kalau ia dilaporkan.",
    bodyHint: "Apa cerita? Guna @ untuk mention orang",
    charCount: "{0}/{1}",
    tooLong: "Panjang sangat — pendekkan ke {0} aksara",
    tagFieldHint: "Tambah tag — tekan space atau enter",
    suggestedTags: "Cadangan",
    removeTag: "Buang {0}",
    shortcutHint: "Ctrl + Enter untuk post",
    discardPostTitle: "Buang post ni?",
    discardPostBody: "Apa yang kau tulis akan hilang.",
    anonToggle: "Komen tanpa nama",
    anonToggleOn: "Tanpa nama — nama kau disembunyikan",
    replyingAs: "Komen sebagai {0}",
    commentCount: "{0} komen",
    tagPostCount: "{0} post",
    tagPostCountOne: "1 post",
    feedEnd: "Dah habis baca semua",
  );

  static FeedStrings of(AppLanguage lang) =>
      lang == AppLanguage.ms ? ms : en;
}

extension FeedL10nContext on BuildContext {
  FeedStrings get feedL10n =>
      FeedStrings.of(watch<LanguageCubit>().state.language);
  FeedStrings get feedL10nRead =>
      FeedStrings.of(read<LanguageCubit>().state.language);
}
