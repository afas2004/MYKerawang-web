import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/announce_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../services/announcement_service.dart';
import '../utils/announcement_rules.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/local_image.dart';
import '../widgets/announcement_view.dart';
import '../widgets/brand/brand.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';

/// Composer for announcements (/create/announcement, and
/// /post/:id/edit-announcement with [editPost]).
///
/// Only club officers (as their club; club / event / general) and admins
/// (any category, incl. kolej / jpk) get past the permission check.
/// Preview shows exactly what readers will see before publishing.
class CreateAnnouncementScreen extends StatefulWidget {
  final Map<String, dynamic>? editPost;

  const CreateAnnouncementScreen({super.key, this.editPost});

  @override
  State<CreateAnnouncementScreen> createState() => _CreateAnnouncementScreenState();
}

class _ActionRow {
  final label = TextEditingController();
  final url = TextEditingController();
  void dispose() {
    label.dispose();
    url.dispose();
  }
}

class _CreateAnnouncementScreenState extends State<CreateAnnouncementScreen> {
  late final AnnouncementDraft _d = widget.editPost != null
      ? AnnouncementDraft.fromPost(widget.editPost!)
      : AnnouncementDraft();
  late final _title = TextEditingController(text: _d.title);
  late final _body = TextEditingController(text: _d.body);
  final List<_ActionRow> _actions = [];

  late final Future<AnnouncePermission> _permission = AnnouncementService.permission();
  bool _preview = false;
  bool _saving = false;
  bool _showErrors = false;
  bool _touched = false;

  bool get _isEdit => widget.editPost != null;

  @override
  void initState() {
    super.initState();
    for (final a in _d.actions) {
      _actions.add(_ActionRow()
        ..label.text = a.label
        ..url.text = a.url);
    }
    _title.addListener(_touch);
    _body.addListener(_touch);
    FormGuard.register(() => _touched && !_saving);
  }

  @override
  void dispose() {
    FormGuard.clear();
    _title.dispose();
    _body.dispose();
    for (final a in _actions) {
      a.dispose();
    }
    super.dispose();
  }

  void _touch() {
    _touched = true;
    if (_showErrors) setState(() {});
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _touched = true;
      });

  /// Copies the text fields into the draft.
  void _sync() {
    _d.title = _title.text;
    _d.body = _body.text;
    _d.actions
      ..clear()
      ..addAll([for (final a in _actions) ActionLink(a.label.text.trim(), a.url.text.trim())]);
  }

  // ---------------------------------------------------------------- pickers

  Future<void> _pickCover() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: kPhotoMaxDimension,
        maxHeight: kPhotoMaxDimension,
        imageQuality: kPhotoQuality,
      );
      if (picked == null) return;
      final img = await LocalImage.fromXFile(picked);
      _set(() => _d.cover
        ..clear()
        ..add(img));
    } catch (e) {
      debugPrint('Cover pick failed: $e');
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final start = initial ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: start.isBefore(now) ? now : start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickEvent() async {
    final a = context.announceL10nRead;
    final events = await AnnouncementService.linkableEvents(clubId: _d.clubId)
        .catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(a.chooseEvent, style: Theme.of(ctx).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(AppIcons.close),
              title: Text(a.linkEventNone),
              onTap: () => Navigator.pop(ctx, <String, dynamic>{}),
            ),
            for (final e in events)
              ListTile(
                leading: const Icon(AppIcons.events),
                title: Text('${e['title'] ?? ''}'),
                subtitle: Text([
                  if (parseLocal(e['start_datetime']) != null) formatDate(parseLocal(e['start_datetime'])!),
                  '${e['location'] ?? ''}',
                ].where((x) => x.isNotEmpty).join(' · ')),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    _set(() => _d.linkedEvent = chosen.isEmpty ? null : chosen);
  }

  // ---------------------------------------------------------------- submit

  String _issueText(AnnouncementIssue i, AnnounceStrings a) => switch (i) {
        AnnouncementIssue.titleRequired => a.errTitleRequired,
        AnnouncementIssue.titleTooLong => a.errTitleTooLong.fill([kAnnouncementTitleMax]),
        AnnouncementIssue.bodyTooLong => a.errBodyTooLong.fill([kAnnouncementBodyMax]),
        AnnouncementIssue.categoryNotAllowed => a.errCategory,
        AnnouncementIssue.tooManyImages => a.errImages.fill([kAnnouncementExtraImagesMax]),
        AnnouncementIssue.tooManyActions => a.errActions.fill([kActionLinksMax]),
        AnnouncementIssue.badAction => a.errActionBadUrl,
        AnnouncementIssue.featureBeforePublish => a.errFeatureBeforePublish,
      };

  String? _actionError(ActionLinkIssue? i, AnnounceStrings a) => switch (i) {
        null => null,
        ActionLinkIssue.emptyLabel => a.errActionEmptyLabel,
        ActionLinkIssue.labelTooLong => a.errActionLabelTooLong.fill([kActionLabelMax]),
        ActionLinkIssue.emptyUrl => a.errActionEmptyUrl,
        ActionLinkIssue.notHttps => a.errActionNotHttps,
        ActionLinkIssue.unknownRoute => a.errActionUnknownRoute,
        ActionLinkIssue.badUrl => a.errActionBadUrl,
      };

  Future<void> _submit(AnnouncePermission p) async {
    if (_saving) return;
    _sync();
    final issues = _d.validate(_categoriesFor(p));
    if (issues.isNotEmpty) {
      setState(() {
        _showErrors = true;
        _preview = false;
      });
      final a = context.announceL10nRead;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_issueText(issues.first, a))));
      return;
    }
    if (!await ensureCanWrite(context, ModScope.post) || !mounted) return;
    final a = context.announceL10nRead;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final id = await AnnouncementService.save(_d, editId: widget.editPost?['id'] as String?);
      if (!mounted) return;
      if (_isEdit) {
        completeEdit(context, message: a.updated);
      } else {
        final later = _d.publishAt != null && _d.publishAt!.isAfter(DateTime.now());
        completePublish(context, '/post/$id',
            message: later ? a.scheduled.fill([formatDate(_d.publishAt!)]) : a.published);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(describeWriteError(context, e)),
          action: SnackBarAction(
            label: context.l10nRead.tryAgain,
            onPressed: () {
              if (mounted) _submit(p);
            },
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Categories for the chosen speaker: admins speaking as themselves get
  /// everything they're allowed; a club gets club / event / general.
  List<String> _categoriesFor(AnnouncePermission p) {
    if (_d.clubId != null) {
      return p.categories.where(kClubAnnouncementCategories.contains).toList();
    }
    return p.isAdmin ? p.categories : const [];
  }

  void _togglePreview() => setState(() {
        _sync();
        _preview = !_preview;
      });

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnnouncePermission>(
      future: _permission,
      builder: (context, snap) {
        if (!snap.hasData && !snap.hasError) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final p = snap.data ?? AnnouncePermission.none;
        if (!p.allowed) return _NotAllowed(error: snap.hasError);

        // Defaults: first club (or self for admins), first allowed category.
        if (!_isEdit && _d.clubId == null && !p.isAdmin && p.clubs.isNotEmpty) {
          _d.clubId = p.clubs.first.clubId;
        }
        final cats = _categoriesFor(p);
        if (_d.category == null || !cats.contains(_d.category)) {
          _d.category = cats.isNotEmpty ? cats.first : null;
        }
        return _scaffold(context, p, cats);
      },
    );
  }

  Widget _scaffold(BuildContext context, AnnouncePermission p, List<String> cats) {
    final a = context.announceL10n;
    final s = context.l10n;
    final later = _d.publishAt != null && _d.publishAt!.isAfter(DateTime.now());

    final submit = Padding(
      padding: const EdgeInsets.only(right: KSpace.m),
      child: FilledButton(
        onPressed: _saving ? null : () => _submit(p),
        child: _saving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
            : Text(_isEdit ? a.saveChanges : (later ? a.schedule : a.publish)),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => appBack(context),
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: s.close,
            icon: const Icon(AppIcons.close),
            onPressed: () => appBack(context),
          ),
          title: Text(_isEdit ? a.editAnnouncement : a.newAnnouncement),
          actions: [
            // Icon only on phones, so the app bar never overflows.
            if (Responsive.isCompact(context))
              IconButton(
                tooltip: _preview ? a.backToEdit : a.preview,
                onPressed: _togglePreview,
                icon: Icon(_preview ? AppIcons.edit : AppIcons.visible),
              )
            else
              TextButton.icon(
                onPressed: _togglePreview,
                icon: Icon(_preview ? AppIcons.edit : AppIcons.visible, size: 18),
                label: Text(_preview ? a.backToEdit : a.preview),
              ),
            submit,
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
            child: _preview ? _previewView(p) : _form(context, p, cats),
          ),
        ),
      ),
    );
  }

  Widget _previewView(AnnouncePermission p) {
    final club = p.clubs.where((c) => c.clubId == _d.clubId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(KSpace.l),
      children: [
        AnnouncementView(
          preview: true,
          data: AnnouncementData(
            title: _d.title,
            body: _d.body,
            category: _d.category,
            authorName: club?.label ?? AppStrings.appName,
            authorAvatar: club?.avatarUrl,
            cover: _d.cover.firstOrNull,
            images: _d.images,
            actions: _d.actions.where((l) => validateActionLink(l.label, l.url) == null).toList(),
            linkedEvent: _d.linkedEvent,
            publishAt: _d.publishAt ?? DateTime.now(),
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, AnnouncePermission p, List<String> cats) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = context.announceL10n;
    final title = _title.text.trim();

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: KSpace.xl, bottom: KSpace.s),
          child: Text(t, style: theme.textTheme.titleSmall),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, KSpace.xxl),
      children: [
        // Speaker: the club (officers), or the app itself for admins.
        if (p.clubs.isNotEmpty) ...[
          label(a.postAs),
          Wrap(
            spacing: KSpace.s,
            runSpacing: KSpace.s,
            children: [
              if (p.isAdmin)
                ChoiceChip(
                  avatar: const Icon(AppIcons.official, size: 18),
                  label: const Text(AppStrings.appName),
                  selected: _d.clubId == null,
                  onSelected: _isEdit ? null : (_) => _set(() => _d.clubId = null),
                ),
              for (final c in p.clubs)
                ChoiceChip(
                  avatar: const Icon(AppIcons.people, size: 18),
                  label: Text(c.label),
                  selected: _d.clubId == c.clubId,
                  onSelected: _isEdit ? null : (_) => _set(() => _d.clubId = c.clubId),
                ),
            ],
          ),
        ],

        // Category
        label(a.category),
        Wrap(
          spacing: KSpace.s,
          runSpacing: KSpace.s,
          children: [
            for (final c in cats)
              ChoiceChip(
                label: Text(a.categoryLabel(c)),
                selected: _d.category == c,
                onSelected: (_) => _set(() => _d.category = c),
              ),
          ],
        ),

        // Title + body
        label(a.title),
        TextField(
          controller: _title,
          maxLength: kAnnouncementTitleMax,
          textInputAction: TextInputAction.next,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: a.titleHint,
            errorText: _showErrors && title.isEmpty ? a.errTitleRequired : null,
          ),
        ),
        label(a.body),
        TextField(
          controller: _body,
          minLines: 6,
          maxLines: 20,
          maxLength: kAnnouncementBodyMax,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(hintText: a.bodyHint, helperText: a.formattingHelp, helperMaxLines: 2),
        ),

        // Cover
        label(a.cover),
        Semantics(
          button: true,
          label: a.coverHint,
          child: ClipRRect(
            borderRadius: KRadius.card,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Material(
                color: scheme.surfaceContainerHigh,
                child: InkWell(
                  onTap: _pickCover,
                  child: _d.cover.isEmpty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(AppIcons.photo, color: scheme.primary, size: 32),
                            const SizedBox(height: KSpace.s),
                            Text(a.coverHint, style: TextStyle(color: scheme.primary)),
                          ]),
                        )
                      : Stack(fit: StackFit.expand, children: [
                          AnnouncementImage(_d.cover.first),
                          Positioned(
                            top: KSpace.s,
                            right: KSpace.s,
                            child: IconButton.filledTonal(
                              tooltip: context.l10n.removePhoto,
                              icon: const Icon(AppIcons.close, size: 18),
                              onPressed: () => _set(() => _d.cover.clear()),
                            ),
                          ),
                        ]),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: KSpace.xs),
          child: Text(a.coverGuide,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),

        // Extra photos
        label(a.extraImages.fill([_d.images.length, kAnnouncementExtraImagesMax])),
        MediaPickerGrid(
          items: _d.images,
          onChanged: () => _set(() {
            if (_d.images.length > kAnnouncementExtraImagesMax) {
              _d.images.removeRange(kAnnouncementExtraImagesMax, _d.images.length);
            }
          }),
        ),

        // Action buttons
        label(a.actions),
        for (var i = 0; i < _actions.length; i++) _actionEditor(i, a),
        if (_actions.length < kActionLinksMax)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _set(() => _actions.add(_ActionRow())),
              icon: const Icon(AppIcons.create, size: 18),
              label: Text(a.addAction),
            ),
          ),

        // Linked event
        label(a.linkEvent),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AppIcons.events),
          title: Text(_d.linkedEvent?['title'] as String? ?? a.linkEventNone),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: _pickEvent,
        ),

        const Divider(height: KSpace.xl),
        // Schedule + banner
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AppIcons.clock),
          title: Text(a.publishWhen),
          subtitle: Text(_d.publishAt == null
              ? a.publishNow
              : '${formatDate(_d.publishAt!)} ${TimeOfDay.fromDateTime(_d.publishAt!).format(context)}'),
          trailing: _d.publishAt == null
              ? const Icon(AppIcons.chevronRight)
              : IconButton(
                  tooltip: a.publishNow,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => _set(() => _d.publishAt = null)),
          onTap: () async {
            final t = await _pickDateTime(_d.publishAt);
            if (t != null) _set(() => _d.publishAt = t);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(AppIcons.pin),
          title: Text(a.featureUntil),
          subtitle: Text(
            _d.featureUntil == null
                ? a.featureUntilNone
                : '${formatDate(_d.featureUntil!)} ${TimeOfDay.fromDateTime(_d.featureUntil!).format(context)}',
            style: _showErrors &&
                    _d.featureUntil != null &&
                    !_d.featureUntil!.isAfter(_d.publishAt ?? DateTime.now())
                ? TextStyle(color: scheme.error)
                : null,
          ),
          trailing: _d.featureUntil == null
              ? const Icon(AppIcons.chevronRight)
              : IconButton(
                  tooltip: a.featureUntilNone,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => _set(() => _d.featureUntil = null)),
          onTap: () async {
            final t = await _pickDateTime(_d.featureUntil ?? _d.publishAt?.add(const Duration(days: 7)));
            if (t != null) _set(() => _d.featureUntil = t);
          },
        ),
        const Divider(height: KSpace.xl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(AppIcons.comment),
          title: Text(a.commentsOn),
          subtitle: Text(a.commentsOnSub),
          value: _d.commentsEnabled,
          onChanged: (v) => _set(() => _d.commentsEnabled = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(AppIcons.home),
          title: Text(a.showInFeed),
          subtitle: Text(a.showInFeedSub),
          value: _d.showInFeed,
          onChanged: (v) => _set(() => _d.showInFeed = v),
        ),
      ],
    );
  }

  Widget _actionEditor(int i, AnnounceStrings a) {
    final row = _actions[i];
    final issue = validateActionLink(row.label.text, row.url.text);
    final show = _showErrors && issue != null;
    final labelIssue = issue == ActionLinkIssue.emptyLabel || issue == ActionLinkIssue.labelTooLong;
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(children: [
              TextField(
                controller: row.label,
                maxLength: kActionLabelMax,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  labelText: a.actionLabel,
                  errorText: show && labelIssue ? _actionError(issue, a) : null,
                ),
              ),
              TextField(
                controller: row.url,
                keyboardType: TextInputType.url,
                onChanged: (_) => _touch(),
                decoration: InputDecoration(
                  labelText: a.actionUrl,
                  hintText: a.actionUrlHint,
                  errorText: show && !labelIssue ? _actionError(issue, a) : null,
                ),
              ),
            ]),
          ),
          IconButton(
            tooltip: a.removeAction,
            icon: const Icon(AppIcons.delete),
            onPressed: () => _set(() => _actions.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }
}

class _NotAllowed extends StatelessWidget {
  final bool error;
  const _NotAllowed({required this.error});

  @override
  Widget build(BuildContext context) {
    final a = context.announceL10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.close,
          icon: const Icon(AppIcons.close),
          onPressed: () => appBack(context),
        ),
      ),
      body: BrandEmptyState(
        icon: AppIcons.announcement,
        title: error ? a.loadFailed : a.notAllowed,
      ),
    );
  }
}
