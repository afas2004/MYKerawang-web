import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../language_cubit.dart';
import 'app_strings.dart';

/// Copy for posts and comments (edit, delete, photos, tags, comment paging).
///
/// Kept beside [AppStrings] rather than inside it so this feature could
/// land without touching the shared table; fold it in when convenient.
/// Same conventions: `{0}` placeholders filled with `fill`. Japanese is
/// being dropped, so strings added after the first batch stay English there.
class PostStrings {
  final String editPost;
  final String deletePost;
  final String deletePostConfirm;
  final String postDeleted;
  final String postUpdated;
  final String editComment;
  final String deleteComment;
  final String deleteCommentConfirm;
  final String commentDeleted;
  final String photoLimit;
  final String anonymityLocked;
  final String postPhoto;
  final String postEmpty;
  final String titleOptionalHint;

  // Tags
  final String tagPostsLabel;
  final String noTaggedPosts;
  final String loadMoreFailed;
  final String loadingPosts;

  // Comments
  final String showEarlierComments;
  final String commentPosted;
  final String commentUpdated;
  final String commentFailed;
  final String sendComment;
  final String commentAnonOn;
  final String commentAnonOff;

  // Menus
  final String postOptions;
  final String commentOptions;

  const PostStrings({
    required this.editPost,
    required this.deletePost,
    required this.deletePostConfirm,
    required this.postDeleted,
    required this.postUpdated,
    required this.editComment,
    required this.deleteComment,
    required this.deleteCommentConfirm,
    required this.commentDeleted,
    required this.photoLimit,
    required this.anonymityLocked,
    required this.postPhoto,
    required this.postEmpty,
    required this.titleOptionalHint,
    required this.tagPostsLabel,
    required this.noTaggedPosts,
    required this.loadMoreFailed,
    required this.loadingPosts,
    required this.showEarlierComments,
    required this.commentPosted,
    required this.commentUpdated,
    required this.commentFailed,
    required this.sendComment,
    required this.commentAnonOn,
    required this.commentAnonOff,
    required this.postOptions,
    required this.commentOptions,
  });

  static const en = PostStrings(
    editPost: "Edit post",
    deletePost: "Delete post",
    deletePostConfirm: "Delete this post? Its comments will be deleted too.",
    postDeleted: "Post deleted",
    postUpdated: "Post updated",
    editComment: "Edit comment",
    deleteComment: "Delete comment",
    deleteCommentConfirm: "Delete this comment?",
    commentDeleted: "Comment deleted",
    photoLimit: "Up to {0} photos per post",
    anonymityLocked: "Anonymity can't be changed after posting",
    postPhoto: "Post photo {0} of {1}",
    postEmpty: "Write something or add a photo",
    titleOptionalHint: "Title (optional)",
    tagPostsLabel: "Posts tagged {0}",
    noTaggedPosts: "No posts with this tag yet",
    loadMoreFailed: "Couldn't load more posts",
    loadingPosts: "Loading posts",
    showEarlierComments: "Show earlier comments",
    commentPosted: "Comment posted",
    commentUpdated: "Comment updated",
    commentFailed: "Couldn't post your comment",
    sendComment: "Send comment",
    commentAnonOn: "Comment anonymously: on",
    commentAnonOff: "Comment anonymously: off",
    postOptions: "Post options",
    commentOptions: "Comment options",
  );

  static const ms = PostStrings(
    editPost: "Edit post",
    deletePost: "Padam post",
    deletePostConfirm: "Padam post ni? Komen dia pun akan dipadam.",
    postDeleted: "Post dipadam",
    postUpdated: "Post dikemas kini",
    editComment: "Edit komen",
    deleteComment: "Padam komen",
    deleteCommentConfirm: "Padam komen ni?",
    commentDeleted: "Komen dipadam",
    photoLimit: "Maksimum {0} gambar setiap post",
    anonymityLocked: "Status tanpa nama tak boleh ditukar lepas post",
    postPhoto: "Gambar post {0} daripada {1}",
    postEmpty: "Tulis sesuatu atau tambah gambar",
    titleOptionalHint: "Tajuk (pilihan)",
    tagPostsLabel: "Post bertanda {0}",
    noTaggedPosts: "Belum ada post dengan tanda ni",
    loadMoreFailed: "Tak dapat muat lagi post",
    loadingPosts: "Memuatkan post",
    showEarlierComments: "Tunjuk komen terdahulu",
    commentPosted: "Komen dihantar",
    commentUpdated: "Komen dikemas kini",
    commentFailed: "Komen tak dapat dihantar",
    sendComment: "Hantar komen",
    commentAnonOn: "Komen tanpa nama: hidup",
    commentAnonOff: "Komen tanpa nama: mati",
    postOptions: "Pilihan post",
    commentOptions: "Pilihan komen",
  );

  static const ja = PostStrings(
    editPost: "投稿を編集",
    deletePost: "投稿を削除",
    deletePostConfirm: "この投稿を削除しますか？コメントも削除されます。",
    postDeleted: "投稿を削除しました",
    postUpdated: "投稿を更新しました",
    editComment: "コメントを編集",
    deleteComment: "コメントを削除",
    deleteCommentConfirm: "このコメントを削除しますか？",
    commentDeleted: "コメントを削除しました",
    photoLimit: "1つの投稿に写真は{0}枚まで",
    anonymityLocked: "匿名設定は投稿後に変更できません",
    postPhoto: "投稿の写真 {0}/{1}",
    // Japanese is being dropped; strings from here on stay English.
    postEmpty: "Write something or add a photo",
    titleOptionalHint: "Title (optional)",
    tagPostsLabel: "Posts tagged {0}",
    noTaggedPosts: "No posts with this tag yet",
    loadMoreFailed: "Couldn't load more posts",
    loadingPosts: "Loading posts",
    showEarlierComments: "Show earlier comments",
    commentPosted: "Comment posted",
    commentUpdated: "Comment updated",
    commentFailed: "Couldn't post your comment",
    sendComment: "Send comment",
    commentAnonOn: "Comment anonymously: on",
    commentAnonOff: "Comment anonymously: off",
    postOptions: "Post options",
    commentOptions: "Comment options",
  );

  static PostStrings of(AppLanguage lang) => switch (lang) {
        AppLanguage.en => en,
        AppLanguage.ms => ms,
        AppLanguage.ja => ja,
      };
}

/// `context.postL10n` in build, `context.postL10nRead` in callbacks —
/// mirrors `l10n` / `l10nRead`.
extension PostL10nContext on BuildContext {
  PostStrings get postL10n =>
      PostStrings.of(watch<LanguageCubit>().state.language);
  PostStrings get postL10nRead =>
      PostStrings.of(read<LanguageCubit>().state.language);
}
