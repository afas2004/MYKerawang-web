import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../theme/app_themes.dart';
import '../utils/tags.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';
import 'profile_cubit.dart';

/// Width at or above which the editor opens as a dialog over the feed;
/// below it is a full-screen page.
const double kComposerDialogBreakpoint = 600;

/// Opens the post editor — new post, or [post] to edit. Dialog over the
/// current page on ≥600 px, full screen below. Completes with true when
/// something was published or saved.
Future<bool> openPostComposer(
  BuildContext context, {
  Map<String, dynamic>? post,
  Map<String, dynamic>? sharedEvent,
  Map<String, dynamic>? sharedListing,
}) async {
  final form = CreatePostScreen(
    editPost: post,
    sharedEvent: sharedEvent,
    sharedListing: sharedListing,
  );
  final dialog =
      MediaQuery.sizeOf(context).width >= kComposerDialogBreakpoint;
  final Future<bool?> route = dialog
      ? showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            insetPadding: const EdgeInsets.all(24),
            shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
              child: form,
            ),
          ),
        )
      : Navigator.push<bool>(
          context,
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => form),
        );
  return await route == true;
}

/// Edit [post] in the composer.
Future<bool> openPostEditor(BuildContext context, Map<String, dynamic> post) =>
    openPostComposer(context, post: post);

class CreatePostScreen extends StatefulWidget {
  final Map<String, dynamic>? sharedEvent;
  final Map<String, dynamic>? sharedListing;

  /// When set, the form edits this post instead of creating one.
  final Map<String, dynamic>? editPost;

  const CreatePostScreen(
      {super.key, this.sharedEvent, this.sharedListing, this.editPost});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  /// Soft limits: counters warn as you approach them; publishing past
  /// [_bodyMax] is blocked with a message.
  static const _bodyMax = 2000;
  static const _titleMax = 120;

  final _bodyCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _tagFocus = FocusNode();
  bool _isAnon = false;
  bool _isLoading = false;

  /// Committed tags in stored form (see utils/tags.dart).
  final List<String> _tags = [];

  /// Existing URLs (`String`) and picked LocalImages; index 0 is the cover.
  final List<dynamic> _photos = [];

  // Initial values, to know whether closing would lose anything.
  late final String _initialTitle;
  late final String _initialBody;
  late final List<String> _initialTags;
  late final int _initialPhotos;

  bool get _isEdit => widget.editPost != null;
  Map<String, dynamic>? get _sharedEvent =>
      widget.sharedEvent ?? widget.editPost?['events'];
  Map<String, dynamic>? get _sharedListing =>
      widget.sharedListing ?? widget.editPost?['listings'];

  /// Suggested shortcuts — users can also type anything they like.
  static const _suggested = ['question', 'confession', kLostFoundTag, 'rant', 'academic'];

  @override
  void initState() {
    super.initState();
    final post = widget.editPost;
    if (post != null) {
      _titleCtrl.text = post['title'] ?? '';
      _bodyCtrl.text = post['body'] ?? '';
      _tags.addAll(List<String>.from(post['tags'] ?? const [])
          .map(normalizeTag)
          .where((t) => t.isNotEmpty)
          .toSet());
      _isAnon = post['is_anonymous'] ?? false;
      _photos.addAll(PostService.photoUrlsOf(post));
    }
    _initialTitle = _titleCtrl.text;
    _initialBody = _bodyCtrl.text;
    _initialTags = List.of(_tags);
    _initialPhotos = _photos.length;
    _bodyCtrl.addListener(_rebuild);
    _titleCtrl.addListener(_rebuild);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _titleCtrl.dispose();
    _tagCtrl.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  bool get _dirty =>
      _titleCtrl.text != _initialTitle ||
      _bodyCtrl.text != _initialBody ||
      _photos.length != _initialPhotos ||
      _photos.any((p) => p is! String) ||
      !listEquals(_tags, _initialTags) ||
      _tagCtrl.text.trim().isNotEmpty;

  // ---------------------------------------------------------- tags

  void _commitTag([String? raw]) {
    final parsed = parseTags(raw ?? _tagCtrl.text);
    setState(() {
      for (final t in parsed) {
        if (!_tags.contains(t)) _tags.add(t);
      }
      _tagCtrl.clear();
    });
  }

  void _onTagChanged(String text) {
    // Space or comma ends a tag, like most tag fields.
    if (text.endsWith(' ') || text.endsWith(',')) _commitTag(text);
  }

  KeyEventResult _onTagKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        _tagCtrl.text.isEmpty &&
        _tags.isNotEmpty) {
      setState(() => _tags.removeLast());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _toggleSuggested(String tag) {
    setState(() => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag));
  }

  // ---------------------------------------------------------- photos

  void _onPhotosChanged() {
    if (_photos.length > PostService.maxPhotos) {
      _photos.removeRange(PostService.maxPhotos, _photos.length);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.postL10nRead.photoLimit
              .fill([PostService.maxPhotos]))));
    }
    setState(() {});
  }

  // ---------------------------------------------------------- close

  Future<bool> _confirmDiscard() async {
    final s = context.l10nRead;
    final fs = context.feedL10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fs.discardPostTitle),
        content: Text(fs.discardPostBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.keepEditing)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.discard,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _close() async {
    if (!_dirty || await _confirmDiscard()) {
      if (mounted) Navigator.of(context).pop(false);
    }
  }

  // ---------------------------------------------------------- submit

  Future<void> _submit() async {
    if (_isLoading) return;
    if (_tagCtrl.text.trim().isNotEmpty) _commitTag();
    // Title is optional; a post needs something — title, text or a photo.
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (title.isEmpty && body.isEmpty && _photos.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(context.postL10nRead.postEmpty)));
      return;
    }
    if (_bodyCtrl.text.length > _bodyMax) {
      messenger.showSnackBar(SnackBar(
          content: Text(context.feedL10nRead.tooLong.fill([_bodyMax]))));
      return;
    }
    if (!await ensureCanWrite(context, ModScope.post) || !mounted) return;

    final s = context.l10nRead;
    final ps = context.postL10nRead;
    setState(() => _isLoading = true);

    try {
      final photoUrls = await PostService.uploadPhotos(_photos);
      final edit = widget.editPost;

      if (edit != null) {
        await PostService.updatePost(
          edit['id'],
          title: title.isEmpty ? null : title,
          body: _bodyCtrl.text,
          tags: _tags,
          photoUrls: photoUrls,
          removedPhotoUrls: PostService.photoUrlsOf(edit)
              .where((u) => !photoUrls.contains(u))
              .toList(),
        );
        // Only people the edit newly mentions.
        await MentionService.notify(
          text: _bodyCtrl.text,
          postId: edit['id'],
          anonymous: _isAnon,
          alreadyNotified: MentionService.usernamesIn(edit['body'] ?? ''),
        );
      } else {
        final newPost = await Supabase.instance.client.from('posts').insert({
          'user_id': Supabase.instance.client.auth.currentUser!.id,
          'title': title.isEmpty ? null : title,
          'body': _bodyCtrl.text,
          'is_anonymous': _isAnon,
          'shared_event_id': widget.sharedEvent?['id'],
          'shared_listing_id': widget.sharedListing?['id'],
          'tags': _tags,
          'image_url': photoUrls.firstOrNull,
          'gallery_urls': photoUrls.skip(1).toList(),
        }).select('id').single();
        PostService.rememberMine(newPost['id']);

        await MentionService.notify(
          text: _bodyCtrl.text,
          postId: newPost['id'],
          anonymous: _isAnon,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        messenger.showSnackBar(SnackBar(
            content: Text(edit != null ? ps.postUpdated : s.postedSuccess)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(describeWriteError(context, e)),
          action: SnackBarAction(
            label: s.tryAgain,
            onPressed: () {
              if (mounted) _submit();
            },
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------- build

  /// Signed-in profile for the "posting as" line, if the app provides one.
  Map<String, dynamic>? _profile(BuildContext context) {
    try {
      return context.select<ProfileCubit, Map<String, dynamic>?>(
          (c) => c.state.profile);
    } catch (_) {
      return null; // no ProfileCubit above (tests, isolated use)
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;
    final fs = context.feedL10n;
    final isDialog = MediaQuery.sizeOf(context).width >= kComposerDialogBreakpoint;
    final bodyLen = _bodyCtrl.text.length;
    final overLimit = bodyLen > _bodyMax;

    final submit = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: FilledButton(
        onPressed: _isLoading ? null : _submit,
        child: _isLoading
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_isEdit ? s.saveChanges : s.publish),
      ),
    );

    final editor = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _IdentityLine(anonymous: _isAnon, profile: _profile(context)),
        if (_sharedEvent != null || _sharedListing != null) ...[
          const SizedBox(height: 12),
          _SharedRef(event: _sharedEvent, listing: _sharedListing),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          autofocus: isDialog,
          maxLength: _titleMax,
          textInputAction: TextInputAction.next,
          style: theme.textTheme.titleLarge,
          decoration: InputDecoration(
            hintText: ps.titleOptionalHint,
            hintStyle: theme.textTheme.titleLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        MentionInput(
          controller: _bodyCtrl,
          hintText: fs.bodyHint,
          isMultiLine: true,
          minLines: 4,
          maxLines: 14,
          style: theme.textTheme.bodyLarge,
        ),
        // Live character hint (+ shortcut on web keyboards).
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 16),
          child: Row(
            children: [
              if (kIsWeb && isDialog)
                Expanded(
                  child: Text(fs.shortcutHint,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                )
              else
                const Spacer(),
              Semantics(
                liveRegion: overLimit,
                child: Text(
                  fs.charCount.fill([bodyLen, _bodyMax]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: overLimit
                        ? scheme.error
                        : (bodyLen > _bodyMax * 0.9
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant),
                    fontWeight: overLimit ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Photos
        Text(s.photosCount.fill([_photos.length, PostService.maxPhotos]),
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        MediaPickerGrid(items: _photos, onChanged: _onPhotosChanged),
        const SizedBox(height: 20),

        // Tags: chips inside the field
        Text(s.addTags, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _TagField(
          tags: _tags,
          controller: _tagCtrl,
          focusNode: _tagFocus,
          onChanged: _onTagChanged,
          onSubmitted: (_) => _commitTag(),
          onKey: _onTagKey,
          onRemove: (t) => setState(() => _tags.remove(t)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(fs.suggestedTags,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            for (final tag in _suggested)
              FilterChip(
                label: Text(displayTag(tag)),
                selected: _tags.contains(tag),
                onSelected: (_) => _toggleSuggested(tag),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Anonymity, explained. Fixed once posted: flipping it later
        // would expose (or re-attribute) what was already said under it.
        Container(
          decoration: BoxDecoration(
            borderRadius: kerawangCut,
            border: Border.all(
                color: _isAnon ? scheme.primary : scheme.outlineVariant),
          ),
          child: SwitchListTile(
            secondary: Icon(
                _isAnon ? Icons.visibility_off : Icons.visibility_outlined),
            title: Text(s.postAnonymously),
            subtitle: Text(_isEdit ? ps.anonymityLocked : fs.anonExplain),
            value: _isAnon,
            onChanged: _isEdit ? null : (val) => setState(() => _isAnon = val),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: !_dirty || _isLoading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: s.close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(_isEdit ? ps.editPost : s.createPostTitle),
              actions: [submit],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: editor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Posting as @you" or the masked anonymous identity.
class _IdentityLine extends StatelessWidget {
  final bool anonymous;
  final Map<String, dynamic>? profile;

  const _IdentityLine({required this.anonymous, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final avatar = anonymous ? null : profile?['avatar_url'] as String?;
    final who = anonymous
        ? s.anonymous
        : (profile?['username'] != null
            ? '@${profile!['username']}'
            : (profile?['display_name'] as String? ?? s.roleStudent));
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor:
              anonymous ? scheme.surfaceContainerHighest : scheme.primaryContainer,
          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
          child: avatar == null
              ? Icon(anonymous ? Icons.visibility_off : Icons.person,
                  size: 16,
                  color: anonymous
                      ? scheme.onSurfaceVariant
                      : scheme.onPrimaryContainer)
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              context.feedL10n.postingAs.fill([who]),
              key: ValueKey(who),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// The event or listing this post is about.
class _SharedRef extends StatelessWidget {
  final Map<String, dynamic>? event;
  final Map<String, dynamic>? listing;

  const _SharedRef({this.event, this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final isEvent = event != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: kerawangCut,
      ),
      child: Row(
        children: [
          Icon(isEvent ? Icons.event : Icons.shopping_bag,
              size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isEvent ? s.referencingEvent : s.referencingItem,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Text(
                  ((isEvent ? event : listing)!['title'] as String?) ?? '',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Committed tags as chips inside an outlined field, with the typing area
/// after them. Space/comma/enter commits; backspace on empty removes the
/// last chip.
class _TagField extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final FocusOnKeyEventCallback onKey;
  final ValueChanged<String> onRemove;

  const _TagField({
    required this.tags,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onKey,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fs = context.feedL10n;
    return GestureDetector(
      onTap: focusNode.requestFocus,
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) => Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: kerawangCut,
            border: Border.all(
              color: focusNode.hasFocus ? scheme.primary : scheme.outline,
              width: focusNode.hasFocus ? 2 : 1,
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.tag, size: 20, color: scheme.onSurfaceVariant),
              for (final t in tags)
                InputChip(
                  label: Text(displayTag(t)),
                  onDeleted: () => onRemove(t),
                  deleteButtonTooltipMessage: fs.removeTag.fill([displayTag(t)]),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
                child: IntrinsicWidth(
                  child: Focus(
                    onKeyEvent: onKey,
                    skipTraversal: true,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: tags.isEmpty ? fs.tagFieldHint : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
