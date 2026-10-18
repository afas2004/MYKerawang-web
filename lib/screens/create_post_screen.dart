import 'package:flutter/material.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';
import '../utils/tags.dart';
import '../widgets/media_picker_grid.dart';

/// Opens the form to edit [post] — a dialog on desktop, a page on mobile,
/// same as the feed composer. Completes with true when saved.
Future<bool> openPostEditor(BuildContext context, Map<String, dynamic> post) async {
  final form = CreatePostScreen(editPost: post);
  final Future<bool?> route = isWide(context)
      ? showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
              child: form,
            ),
          ),
        )
      : Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => form));
  return await route == true;
}

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
  final _bodyCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _isAnon = false;
  bool _isLoading = false;

  /// Existing URLs (`String`) and picked LocalImages; index 0 is the cover.
  final List<dynamic> _photos = [];

  bool get _isEdit => widget.editPost != null;
  Map<String, dynamic>? get _sharedEvent =>
      widget.sharedEvent ?? widget.editPost?['events'];
  Map<String, dynamic>? get _sharedListing =>
      widget.sharedListing ?? widget.editPost?['listings'];

  /// Suggested shortcuts — users can also type anything they like.
  /// Shown as typed; saved through [normalizeTag] (LostFound → lostfound).
  final List<String> _tags = ['Question', 'Confession', 'LostFound', 'Rant', 'Academic'];

  /// Tags currently in the field, in stored form (see utils/tags.dart).
  List<String> get _currentTags => parseTags(_tagsCtrl.text);

  @override
  void initState() {
    super.initState();
    final post = widget.editPost;
    if (post != null) {
      _titleCtrl.text = post['title'] ?? '';
      _bodyCtrl.text = post['body'] ?? '';
      final tags = List<String>.from(post['tags'] ?? const []).map(normalizeTag).toSet();
      if (tags.isNotEmpty) {
        _tagsCtrl.text = "${tags.map((t) => '#$t').join(' ')} ";
      }
      _isAnon = post['is_anonymous'] ?? false;
      _photos.addAll(PostService.photoUrlsOf(post));
    }
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _appendTag(String tag) {
    if (_currentTags.contains(normalizeTag(tag))) return;
    final text = _tagsCtrl.text.trimRight();
    _tagsCtrl.text = text.isEmpty ? "#$tag " : "$text #$tag ";
    _tagsCtrl.selection =
        TextSelection.collapsed(offset: _tagsCtrl.text.length);
    setState(() {});
  }

  void _onPhotosChanged() {
    if (_photos.length > PostService.maxPhotos) {
      _photos.removeRange(PostService.maxPhotos, _photos.length);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.postL10nRead.photoLimit
              .fill([PostService.maxPhotos]))));
    }
    setState(() {});
  }

  Future<void> _submit() async {
    // Title is optional; a post needs something — title, text or a photo.
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty && body.isEmpty && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.postL10nRead.postEmpty)));
      return;
    }

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
          tags: _currentTags,
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
          'tags': _currentTags,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(edit != null ? ps.postUpdated : s.postedSuccess)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEvent = _sharedEvent != null;
    final bool isListing = _sharedListing != null;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        // In a dialog on desktop a ✕ reads better than a back arrow (H4/2.1)
        leading: IconButton(
          tooltip: s.close,
          icon: Icon(isWide(context) ? Icons.close : Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEdit ? ps.editPost : s.createPostTitle),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: Text(_isEdit ? s.saveChanges : s.post,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: PageBody(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isEvent || isListing)
          Container(
            // Optional: Add a little border/color to make it pop (like in the event screen)
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // DYNAMIC ICON: Calendar for Event, Shopping Bag for Item
                Icon(
                  isEvent ? Icons.event : Icons.shopping_bag,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // DYNAMIC LABEL
                      Text(
                        isEvent ? s.referencingEvent : s.referencingItem,
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)
                      ),
                      // DYNAMIC TITLE
                      Text(
                        (isEvent ? _sharedEvent!['title'] : _sharedListing!['title']) ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              hintText: ps.titleOptionalHint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              hintStyle: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
            ),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(),
          MentionInput(
            controller: _bodyCtrl,
            hintText: s.whatsOnYourMind,
            isMultiLine: true,
          ),
          const SizedBox(height: 20),

          Text(s.photosCount.fill([_photos.length, PostService.maxPhotos]),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          MediaPickerGrid(items: _photos, onChanged: _onPhotosChanged),
          const SizedBox(height: 20),

          // Options. Anonymity is fixed once posted: flipping it later
          // would expose (or re-attribute) what was already said under it.
          SwitchListTile(
            title: Text(s.postAnonymously),
            subtitle: Text(_isEdit ? ps.anonymityLocked : s.postAnonymouslySub),
            value: _isAnon,
            onChanged: _isEdit ? null : (val) => setState(() => _isAnon = val),
          ),

          const SizedBox(height: 10),
          Text(s.addTags,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Free-text hashtags. Chips are shortcuts that append into the
          // field; they can't be added twice.
          TextField(
            controller: _tagsCtrl,
            decoration: InputDecoration(
              hintText: s.tagsHint,
              prefixIcon: const Icon(Icons.tag),
            ),
            onChanged: (_) => setState(() {}), // refresh chip states
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _tags.map((tag) {
              final already = _currentTags.contains(normalizeTag(tag));
              return ActionChip(
                avatar: Icon(already ? Icons.check : Icons.add, size: 16),
                label: Text(tag),
                onPressed: already ? null : () => _appendTag(tag),
              );
            }).toList(),
          )
        ],
      )),
    );
  }
}
