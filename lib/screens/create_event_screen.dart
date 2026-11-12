import 'package:flutter/material.dart';
import '../widgets/brand/brand.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_compressor.dart';
import '../utils/local_image.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/form_draft.dart';
import '../utils/announcement_rules.dart';
import '../l10n/announce_strings.dart';
import '../widgets/category_field.dart';
import '../widgets/form_layout.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';
import '../l10n/create_strings.dart';
import '../l10n/form_strings.dart';
import '../widgets/form_picker.dart';
import '../services/club_service.dart';
import '../services/moderation_service.dart';
import '../utils/categories.dart';
import '../widgets/post_as_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/event_timing_editor.dart';
import '../l10n/event_timing_strings.dart';
import '../utils/event_series.dart';

class CreateEventScreen extends StatefulWidget {
  final Map<String, dynamic>? eventToEdit; 

  const CreateEventScreen({super.key, this.eventToEdit});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _locationController;
  late TextEditingController _descController;
  late TextEditingController _linkController;

  /// When: once / repeats / pick dates, and when registration closes.
  late final EventTimingController _timing;
  bool _showTimingErrors = false;

  /// Where: in person / online / hybrid, and the meeting link.
  LocationMode _where = LocationMode.inPerson;
  final _onlineCtrl = TextEditingController();

  /// Editing one date of a series: how many dates it has (for the note).
  int? _seriesCount;

  bool _isLoading = false;

  /// Yourself (null) or one of your clubs: club events are official.
  PostAsOption? _hostAs;

  // UNIFIED MEDIA LIST (Stores both Strings (URLs) and Files)
  // Index 0 is ALWAYS the Cover Photo.
  final List<dynamic> _mediaItems = [];
  
  /// Stored slugs from `content_categories`; first one is the main topic.
  List<String> _categories = [];

  // Registration + merit + contacts.
  bool _meritOffered = false;
  bool _isAdminUser = false;
  String? _audience = 'uitm';
  final _capacityCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _meritNoteCtrl = TextEditingController();
  final _activityRefCtrl = TextEditingController();
  final _coOrganiserCtrl = MentionEditingController();
  final _picCtrl = TextEditingController();

  /// Buttons with links, like an announcement's (max two). Each row keeps its
  /// own controllers so editing an existing event repopulates them.
  final List<_LinkRow> _links = [];
  final Map<String, TextEditingController> _contactCtrls = {
    for (final c in const ['whatsapp', 'telegram', 'instagram', 'email', 'link'])
      c: TextEditingController(),
  };

  static String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  /// Old rows carry `tags` (capitalised, free text); new rows carry
  /// `categories` (lowercase slugs). Read whichever is there.
  static List<String> _categoriesFrom(Map<String, dynamic>? row) {
    if (row == null) return [];
    final raw = row['categories'];
    if (raw is List && raw.isNotEmpty) {
      return raw.whereType<String>().map((e) => e.toLowerCase()).toList();
    }
    final tags = row['tags'];
    if (tags is List) {
      return tags.whereType<String>().map((e) => e.toLowerCase()).toList();
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    final event = widget.eventToEdit;
    
    _titleController = TextEditingController(text: event?['title'] ?? '');
    _locationController = TextEditingController(text: event?['location'] ?? '');
    _descController = MentionEditingController(text: event?['description'] ?? '');
    _linkController = TextEditingController(text: event?['registration_link'] ?? '');
    
    if (event != null) {
      final start = DateTime.parse(event['start_datetime']).toLocal();
      final end = event['end_datetime'] != null
          ? DateTime.parse(event['end_datetime']).toLocal()
          : start.add(const Duration(hours: 2));
      final seriesId = event['series_id'] as String?;
      // The form shows the rule the viewer's page reads back from the row.
      _timing = EventTimingController(
        start: start,
        end: end,
        locked: seriesId != null,
        close: closeRuleOf(event),
        closeAt: DateTime.tryParse('${event['join_deadline'] ?? ''}')?.toLocal(),
      );
      if (seriesId != null) _loadSeriesCount(seriesId);
      _where = LocationMode.of(event['location_mode']);
      _onlineCtrl.text = event['online_url'] ?? '';
      _categories = _categoriesFrom(event);
      _capacityCtrl.text = event['capacity']?.toString() ?? '';
      _feeCtrl.text = event['fee']?.toString() ?? '';
      _audience = (event['audience'] as String?) ?? 'uitm';
      _meritOffered = event['merit_offered'] == true;
      _meritNoteCtrl.text = event['merit_note'] ?? '';
      _activityRefCtrl.text = event['activity_ref'] ?? '';
      _coOrganiserCtrl.text = event['co_organiser'] ?? '';
      _picCtrl.text = event['pic'] ?? '';
      for (final link in ActionLink.listFrom(event['action_links'])) {
        _links.add(_LinkRow()..set(link.label, link.url));
      }
      _loadContacts(event['id'] as String);

      // LOAD EXISTING MEDIA
      // 1. Cover
      if (event['image_url'] != null) {
        _mediaItems.add(event['image_url']);
      }
      // 2. Gallery
      if (event['gallery_urls'] != null) {
        _mediaItems.addAll(List<String>.from(event['gallery_urls']));
      }
    } else {
      final now = DateTime.now();
      // On the hour, so the weekly times start tidy.
      final start = DateTime(now.year, now.month, now.day, now.hour + 1);
      _timing = EventTimingController(start: start, end: start.add(const Duration(hours: 2)));
    }

    // Leaving with unsaved input asks first (router onExit).
    _initialSnapshot = _snapshot();
    FormGuard.register(() => !_isLoading && _snapshot() != _initialSnapshot);
    if (event == null) _restoreDraft();
    _loadIsAdmin();
  }

  Future<void> _loadIsAdmin() async {
    try {
      final admin = await ModerationService.isAdmin();
      if (mounted && admin) setState(() => _isAdminUser = true);
    } catch (_) {
      // Merit simply stays hidden if the check fails.
    }
  }

  Future<void> _loadSeriesCount(String seriesId) async {
    try {
      final rows = await Supabase.instance.client
          .from('events')
          .select('id')
          .eq('series_id', seriesId);
      if (mounted) setState(() => _seriesCount = rows.length);
    } catch (_) {
      // Only the note's number; editing works without it.
    }
  }

  Future<void> _loadContacts(String eventId) async {
    try {
      final c = await Supabase.instance.client
          .from('event_contacts')
          .select()
          .eq('event_id', eventId)
          .maybeSingle();
      if (c == null || !mounted) return;
      setState(() {
        for (final k in _contactCtrls.keys) {
          final v = c[k];
          if (v is String) _contactCtrls[k]!.text = v;
        }
      });
    } catch (_) {
      // Contacts are optional; a failed read must not block editing.
    }
  }

  /// The same contacts on every listed event (each date of a series is its
  /// own event, so each gets its own contacts row).
  Future<void> _saveContacts(List<String> eventIds) async {
    final values = {
      for (final e in _contactCtrls.entries) e.key: _nullIfEmpty(e.value.text),
    };
    if (eventIds.isEmpty || values.values.every((v) => v == null)) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await Supabase.instance.client.from('event_contacts').upsert([
      for (final id in eventIds) {'event_id': id, ...values, 'updated_at': now},
    ], onConflict: 'event_id');
  }

  /// New events autosave their text (see FormDraft): a reload while the
  /// camera / photo picker is open doesn't lose it.
  final _draft = FormDraft('create_event');

  Map<String, dynamic> _draftData() => {
        'title': _titleController.text,
        'location': _locationController.text,
        'description': _descController.text,
        'link': _linkController.text,
        'categories': _categories,
      };

  Future<void> _restoreDraft() async {
    final d = await _draft.load();
    // Only into an untouched form.
    if (d == null || !mounted || _snapshot() != _initialSnapshot) return;
    setState(() {
      _titleController.text = d['title'] ?? '';
      _locationController.text = d['location'] ?? '';
      _descController.text = d['description'] ?? '';
      _linkController.text = d['link'] ?? '';
      final cats = d['categories'];
      if (cats is List) {
        _categories = cats.whereType<String>().toList();
      } else {
        final tags = d['tags'];
        if (tags is List) _categories = tags.whereType<String>().toList();
      }
    });
    _showDraftRestored();
  }

  void _showDraftRestored() {
    final s = context.l10nRead;
    showToast(s.draftRestored, actionLabel: s.discard, onAction: () {
          if (!mounted) return;
          setState(() {
            _titleController.clear();
            _locationController.clear();
            _descController.clear();
            _linkController.clear();
            _categories = [];
          });
          _draft.clear();
        });
  }

  late final String _initialSnapshot;

  /// Everything the user can change, to tell whether leaving loses input.
  String _snapshot() => [
        _titleController.text,
        _locationController.text,
        _descController.text,
        _linkController.text,
        _timing.snapshot(),
        _where.db,
        _onlineCtrl.text,
        _categories.join(','),
        _mediaItems.length,
        _mediaItems.map((m) => m is String ? m : identityHashCode(m)).join(','),
      ].join('|');

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    _linkController.dispose();
    _picCtrl.dispose();
    _onlineCtrl.dispose();
    _timing.dispose();
    for (final l in _links) {
      l.dispose();
    }
    FormGuard.clear();
    // Leaving on purpose (publish / discard / close) drops the draft; a
    // page reload never gets here, so the draft survives that.
    _draft.clear();
    super.dispose();
  }

  // --- SUBMIT LOGIC (SMART SORTING) ---
  Future<void> _submit() async {
    setState(() => _showTimingErrors = true);
    if (!_formKey.currentState!.validate()) return;
    final s = context.l10nRead;
    // The same checks the editor shows inline, so nothing half-valid is
    // published.
    final issue = _timing.issue;
    if (issue != SessionsIssue.none) {
      showToast(issueText(s, issue));
      return;
    }
    if (_timing.closeAfterStart) {
      showToast(s.rcAfterStart);
      return;
    }
    // A photo is optional: an event without a cover still has a date block and
    // every list renders it. (It used to be required, which made a seeded or
    // quickly-created event impossible to open and re-save.)
    if (_categories.isEmpty) {
      showToast(s.categoryRequired);
      return;
    }
    if (!await ensureCanWrite(context, ModScope.events) || !mounted) return;

    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    final supabase = Supabase.instance.client;

    try {
      String? finalCoverUrl;
      List<String> finalGalleryUrls = [];

      // Loop through all items and process them
      for (int i = 0; i < _mediaItems.length; i++) {
        final item = _mediaItems[i];
        String url;

        if (item is LocalImage) {
          // It's a new image: Compress -> Upload (bytes — works on web and mobile)
          final compressed = await ImageCompressor.compressBytes(item.bytes);
          final path = 'events/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          await supabase.storage.from('images').uploadBinary(
                path,
                compressed,
                fileOptions: FileOptions(contentType: imageContentType(compressed)),
              );
          url = supabase.storage.from('images').getPublicUrl(path);
        } else {
          // It's already a URL
          url = item as String;
        }

        // Assign first item to Cover, rest to Gallery
        if (i == 0) {
          finalCoverUrl = url;
        } else {
          finalGalleryUrls.add(url);
        }
      }

      // Everything except the dates, shared by every date of a series.
      final data = {
        'title': _titleController.text,
        // An online event has no venue; '' rather than null, as before.
        'location': _where.hasPlace ? _locationController.text : '',
        'location_mode': _where.db,
        'online_url': _where.hasLink ? _nullIfEmpty(_onlineCtrl.text) : null,
        'description': _descController.text,
        'registration_link': _linkController.text.isEmpty ? null : _linkController.text,
        'image_url': finalCoverUrl,      // Index 0
        'gallery_urls': finalGalleryUrls, // Index 1+
        // The Public switch was removed: new events are public, and an
        // edit leaves whatever is_public an existing event already has.
        if (widget.eventToEdit == null) 'is_public': true,
        'categories': _categories,
        'organizer_id': user!.id,
        'capacity': int.tryParse(_capacityCtrl.text.trim()),
        'fee': double.tryParse(_feeCtrl.text.trim()),
        'audience': _audience,
        'merit_offered': _meritOffered,
        'merit_note': _nullIfEmpty(_meritNoteCtrl.text),
        'activity_ref': _nullIfEmpty(_activityRefCtrl.text),
        'co_organiser': _nullIfEmpty(_coOrganiserCtrl.text),
        'pic': _nullIfEmpty(_picCtrl.text),
        // Attendance is no longer a setting: the organiser takes it from the
        // event page, so every new event has the door available.
        if (widget.eventToEdit == null) 'attendance_enabled': true,
        'action_links': [
          for (final l in _links)
            if (l.label.text.trim().isNotEmpty && l.url.text.trim().isNotEmpty)
              {'label': l.label.text.trim(), 'url': l.url.text.trim()},
        ],
      };

      // One date's row: the shared fields plus its own times and deadline.
      Map<String, dynamic> rowFor(SessionSlot slot) => {
            ...data,
            'start_datetime': slot.start.toUtc().toIso8601String(),
            'end_datetime': slot.end.toUtc().toIso8601String(),
            'join_deadline': _timing.deadlineAt(slot.start)?.toUtc().toIso8601String(),
          };
      final slots = _timing.sessions;

      if (widget.eventToEdit != null) {
        final edited = widget.eventToEdit!;
        final id = edited['id'] as String;
        final seriesId = edited['series_id'] as String?;
        // Later dates of the same series, if any, can take the same changes.
        final later = seriesId == null
            ? const <Map<String, dynamic>>[]
            : List<Map<String, dynamic>>.from(await supabase
                .from('events')
                .select('id, start_datetime')
                .eq('series_id', seriesId)
                .gt('start_datetime', edited['start_datetime'])
                .order('start_datetime'));
        var applyLater = false;
        if (later.isNotEmpty) {
          if (!mounted) return;
          final choice = await _askApplyLater(later.length);
          if (choice == null) return; // dismissed: nothing saved
          applyLater = choice;
        }

        final slot = slots.single;
        await supabase.from('events').update(rowFor(slot)).eq('id', id);
        if (applyLater) {
          final deadline = _timing.deadlineAt(slot.start);
          for (final other in later) {
            final otherStart = DateTime.parse(other['start_datetime']).toLocal();
            await supabase.from('events').update({
              ...data,
              'join_deadline': shiftedDeadline(
                editedStart: slot.start,
                editedDeadline: deadline,
                otherStart: otherStart,
              )?.toUtc().toIso8601String(),
            }).eq('id', other['id']);
          }
        }
        await _saveContacts([id, if (applyLater) for (final o in later) o['id'] as String]);
        // Back to the event page, which refreshes.
        if (mounted) completeEdit(context, message: s.eventUpdated);
      } else {
        final host = _hostAs ?? const PostAsOption.self('');
        Map<String, dynamic> newEvent;
        if (!_timing.isSeries) {
          final insert = host.applyTo(rowFor(slots.single), hasAnonymous: false);
          newEvent = await supabase.from('events').insert(insert).select().single();
          await _saveContacts([newEvent['id'] as String]);
        } else {
          // The series first, then every date in one insert: either all
          // dates are published or none are.
          final series = await supabase
              .from('event_series')
              .insert({
                'organizer_id': user.id,
                'repeat_rule': repeatRule(_timing.mode,
                    weekdays: _timing.weekdays, everyWeeks: _timing.everyWeeks),
              })
              .select('id')
              .single();
          final seriesId = series['id'] as String;
          List<Map<String, dynamic>> created;
          try {
            created = List<Map<String, dynamic>>.from(await supabase
                .from('events')
                .insert([
                  for (final slot in slots)
                    host.applyTo({...rowFor(slot), 'series_id': seriesId}, hasAnonymous: false),
                ])
                .select());
          } catch (_) {
            // Don't leave an empty series behind.
            try {
              await supabase.from('event_series').delete().eq('id', seriesId);
            } catch (_) {}
            rethrow;
          }
          created.sort((a, b) => '${a['start_datetime']}'.compareTo('${b['start_datetime']}'));
          newEvent = created.first;
          await _saveContacts([for (final e in created) e['id'] as String]);
        }
        // People mentioned in the description *or* in the cooperation line are
        // told about the event (once, pointing at the first date); club names
        // there are plain text on purpose.
        await _processMentions(
          '${_descController.text} ${_coOrganiserCtrl.text}',
          newEvent['id'],
        );
        // The form is replaced by the new event's page, so back from
        // there returns to where the user started, not to this form.
        if (mounted) {
          completePublish(context, '/event/${newEvent['id']}',
              extra: newEvent, message: s.eventPublished);
        }
      }

    } catch (e) {
      if (mounted) {
        showToast('$e'.contains('EVENT:series_full')
            ? context.l10nRead.errSeriesFull
            : describeWriteError(context, e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Editing one date of a series that has later dates: apply the changes
  /// to this date only (false) or to this and later dates (true). Null
  /// when dismissed.
  Future<bool?> _askApplyLater(int laterCount) {
    final s = context.l10nRead;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.applyTo),
        content: Text(s.applyLaterNote),
        actions: [
          TextButton(
            key: const ValueKey('apply-this-only'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.onlyThisDate),
          ),
          FilledButton(
            key: const ValueKey('apply-later'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('${s.thisAndLater} (${laterCount + 1})'),
          ),
        ],
      ),
    );
  }

  // 1. HELPER FUNCTION
  Future<void> _processMentions(String text, String eventId) async {
    final regex = RegExp(r"\@(\w+)");
    final matches = regex.allMatches(text);
    final usernames = matches.map((m) => m.group(1)).toSet().toList();

    if (usernames.isEmpty) return;

    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser!.id;

    final users = await supabase
        .from('profiles')
        .select('id, username')
        .inFilter('username', usernames);

    // Read by the recipient, so written in the canonical language.
    const n = AppStrings.en;
    for (var user in users) {
      if (user['id'] == myId) continue;

      await supabase.from('notifications').insert({
        'user_id': user['id'],
        'actor_id': myId,
        'type': 'mention', // We use the same type
        'title': n.notifMentionEventTitle,
        'body': n.notifMentionEventBody,
        'data': {'event_id': eventId}, // Link to the Event ID
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eventToEdit == null) _draft.save(_draftData());
    final theme = Theme.of(context);
    final isEditing = widget.eventToEdit != null;
    final s = context.l10n;

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppCloseButton(),
          title: Text(isEditing ? s.editEvent : s.createEvent)),
      body: FormPageBody(
        child: Form(
          key: _formKey,
          // Errors show as soon as a field is touched, not only on submit.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                title: s.sectionPhotos,
                icon: AppIcons.photo,
                children: [
                  // Shared with the listing form
                  // The picker returns after an await (camera / file dialog);
                  // the form may be gone by then.
                  MediaPickerGrid(
                      items: _mediaItems,
                      onChanged: () {
                        if (mounted) setState(() {});
                      }),
                ],
              ),
              FormSection(
                title: s.sectionDetails,
                icon: AppIcons.edit,
                children: [
                  if (!isEditing) ...[
                    PostAsSelector(
                      selfLabel: s.create.yourself,
                      label: s.create.hostedBy,
                      value: _hostAs,
                      onChanged: (o) => setState(() => _hostAs = o),
                    ),
                    if (_hostAs?.isClub ?? false) ...[
                      const SizedBox(height: KSpace.s),
                      Row(
                        children: [
                          Icon(AppIcons.official, size: 16, color: theme.colorScheme.tertiary),
                          const SizedBox(width: KSpace.xs),
                          Expanded(
                            child: Text(s.create.clubEventNote,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: KSpace.l),
                  ],
                  _label(s.eventTitle, topPad: 0),
                  _input(_titleController, s.eventTitleHint, validator: _required(s.title)),
                  _label(s.description),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: KRadius.input,
                    ),
                    child: MentionInput(
                      controller: _descController,
                      hintText: s.eventDescHint,
                      isMultiLine: true,
                      suggestClubs: true,
                    ),
                  ),
                  // Same light markup the announcement composer documents:
                  // the event page renders the description with it.
                  const SizedBox(height: KSpace.xs),
                  Text(
                    context.announceL10n.formattingHelp,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  _label(s.eventPic),
                  _input(_picCtrl, s.eventPicHint),
                ],
              ),
              FormSection(
                title: s.category,
                icon: AppIcons.filter,
                children: [
                  CategoryField(
                    kind: 'event',
                    value: _categories,
                    onChanged: (v) => setState(() => _categories = v),
                    hintText: s.eventCategoryHint,
                  ),
                  const SizedBox(height: KSpace.xs),
                  Text(
                    s.categoryPickHint.fill(['$kMaxCategoriesPerItem']),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              FormSection(
                title: s.eventButtons,
                icon: AppIcons.link,
                children: [
                  Text(
                    s.eventButtonsHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  for (var i = 0; i < _links.length; i++) _linkEditor(i),
                  if (_links.length < kActionLinksMax)
                    Wrap(
                      spacing: KSpace.s,
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _links.add(_LinkRow())),
                          icon: const Icon(AppIcons.create, size: 18),
                          label: Text(s.eventAddButton),
                        ),
                        // A form becomes an ordinary button: "Fill in form" → /f/:id.
                        AttachFormButton(
                          onPicked: (f) => setState(() =>
                              _links.add(_LinkRow()..set(s.formLinkLabel, f.path))),
                        ),
                      ],
                    ),
                ],
              ),
              FormSection(
                title: s.sectionWhenWhere,
                icon: AppIcons.calendar,
                children: [
                  if (_timing.locked && _seriesCount != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(AppIcons.repeat, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: KSpace.xs),
                        Expanded(
                          child: Text(s.seriesEditBanner(_seriesCount!),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                    const SizedBox(height: KSpace.m),
                  ],
                  EventTimingEditor(controller: _timing, showErrors: _showTimingErrors),
                  _label(s.lmWhere),
                  SegmentedButton<LocationMode>(
                    key: const ValueKey('location-mode'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: LocationMode.inPerson, label: Text(s.lmInPerson)),
                      ButtonSegment(value: LocationMode.online, label: Text(s.lmOnline)),
                      ButtonSegment(value: LocationMode.hybrid, label: Text(s.lmHybrid)),
                    ],
                    selected: {_where},
                    onSelectionChanged: (v) => setState(() => _where = v.first),
                  ),
                  if (_where.hasPlace) ...[
                    _label(s.location),
                    _input(_locationController, s.locationHint, validator: _required(s.location)),
                  ],
                  if (_where.hasLink) ...[
                    _label(s.meetingLink),
                    _input(
                      _onlineCtrl,
                      'https://meet.google.com/…',
                      icon: AppIcons.online,
                      keyboard: TextInputType.url,
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) return s.meetingLinkRequired;
                        return validateHttpsUrl(text) == null
                            ? null
                            : context.announceL10nRead.errActionNotHttps;
                      },
                    ),
                  ],
                  _label(s.registrationLinkOptional),
                  // The registration link is launched from the event page, so
                  // it has to be an https URL — not `javascript:`.
                  _input(
                    _linkController,
                    "https://forms.gle/...",
                    icon: AppIcons.link,
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      return validateHttpsUrl(text) == null
                          ? null
                          : context.announceL10nRead.errActionNotHttps;
                    },
                  ),
                ],
              ),
              FormSection(
                title: s.evRegistration,
                icon: AppIcons.ticket,
                children: [
                  RegistrationCloseField(controller: _timing),
                  const SizedBox(height: KSpace.m),
                  LayoutBuilder(builder: (context, c) {
                    final capacity = _input(_capacityCtrl, s.evCapacity,
                        icon: AppIcons.person,
                        helper: s.evCapacityHint,
                        keyboard: TextInputType.number);
                    final fee = _input(_feeCtrl, s.evFee,
                        icon: AppIcons.market,
                        helper: s.evFeeHint,
                        keyboard: TextInputType.number);
                    if (c.maxWidth < 420) {
                      return Column(children: [
                        capacity,
                        const SizedBox(height: 12),
                        fee,
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: capacity),
                        const SizedBox(width: 12),
                        Expanded(child: fee),
                      ],
                    );
                  }),
                  _label(s.evAudience),
                  DropdownButtonFormField<String>(
                    initialValue: _audience,
                    decoration: _emptyDeco(),
                    items: [
                      for (final a in const ['uitm', 'kolej', 'klab', 'awam'])
                        DropdownMenuItem(
                            value: a, child: Text(s.evAudienceLabel(a))),
                    ],
                    onChanged: (v) => setState(() => _audience = v),
                  ),
                  if (_hostAs?.isClub == true || _isAdminUser) ...[
                    const SizedBox(height: KSpace.s),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _meritOffered,
                      onChanged: (v) => setState(() => _meritOffered = v),
                      title: Text(s.evMerit),
                      subtitle: Text(s.evMeritHint,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    if (_meritOffered) ...[
                      _input(_meritNoteCtrl, s.evMeritNote,
                          icon: AppIcons.verified),
                      const SizedBox(height: 12),
                      _input(_activityRefCtrl, s.evActivityRef,
                          icon: AppIcons.link),
                    ],
                  ],
                  const SizedBox(height: 12),
                  // "Dengan kerjasama": usually a club, sometimes a person.
                  // Typing suggests both — clubs insert a club mention,
                  // "@[handle]" (a chip on the event page), people "@username".
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: KRadius.input,
                    ),
                    child: MentionInput(
                      controller: _coOrganiserCtrl,
                      hintText: s.evCoOrganiserHint,
                      suggestClubs: true,
                    ),
                  ),
                ],
              ),
              FormSection(
                title: s.evContacts,
                icon: AppIcons.email,
                children: [
                  Text(s.evContactHint,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: KSpace.s),
                  _channelField(_contactCtrls['whatsapp']!, 'WhatsApp',
                      AppIcons.phone, TextInputType.phone),
                  _channelField(_contactCtrls['telegram']!, 'Telegram',
                      AppIcons.send),
                  _channelField(_contactCtrls['instagram']!, 'Instagram',
                      AppIcons.camera),
                  _channelField(_contactCtrls['email']!, 'Email',
                      AppIcons.email, TextInputType.emailAddress),
                  _channelField(_contactCtrls['link']!, 'Link', AppIcons.link),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PublishBar(
        busy: _isLoading,
        editing: isEditing,
        label: isEditing ? s.saveChanges : s.publish,
        busyLabel: s.saving,
        onPressed: _submit,
      ),
    );
  }

  // --- FORM HELPERS (Input) ---
  Widget _label(String text, {double topPad = 16}) => Padding(
    padding: EdgeInsets.only(bottom: 8, top: topPad),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))
  );

  /// One contact channel: its icon, then the field. The channel is the label,
  /// so the section reads as a list of actions rather than five anonymous
  /// boxes.
  Widget _channelField(TextEditingController c, String label, IconData icon,
      [TextInputType? keyboard]) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: KRadius.input,
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: KSpace.s),
          Expanded(child: _input(c, label, keyboard: keyboard)),
        ],
      ),
    );
  }

  /// One button row (label + url), validated exactly like an announcement's
  /// action button — the same rules and the same error copy.
  Widget _linkEditor(int i) {
    final row = _links[i];
    final a = context.announceL10n;
    final issue = validateActionLink(row.label.text, row.url.text);
    final labelIssue =
        issue == ActionLinkIssue.emptyLabel || issue == ActionLinkIssue.labelTooLong;
    final show = row.touched;

    String? messageFor(ActionLinkIssue? issue) => switch (issue) {
          ActionLinkIssue.emptyLabel => a.errActionEmptyLabel,
          ActionLinkIssue.labelTooLong => a.errActionLabelTooLong.fill([kActionLabelMax]),
          ActionLinkIssue.emptyUrl => a.errActionEmptyUrl,
          ActionLinkIssue.notHttps => a.errActionNotHttps,
          ActionLinkIssue.unknownRoute => a.errActionUnknownRoute,
          ActionLinkIssue.badUrl => a.errActionBadUrl,
          null => null,
        };

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.label,
              onChanged: (_) => setState(() => row.touched = true),
              decoration: _inputDeco(a.actionLabel, Theme.of(context)).copyWith(
                errorText: show && labelIssue ? messageFor(issue) : null,
              ),
            ),
          ),
          const SizedBox(width: KSpace.s),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.url,
              onChanged: (_) => setState(() => row.touched = true),
              keyboardType: TextInputType.url,
              decoration: _inputDeco(a.actionUrlHint, Theme.of(context)).copyWith(
                errorText: show && !labelIssue ? messageFor(issue) : null,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.delete,
            onPressed: () => setState(() => _links.removeAt(i).dispose()),
            icon: Icon(AppIcons.delete,
                size: 18, color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }

  String? Function(String?) _required(String field) {
    final message = context.l10n.fieldRequired.fill([field]);
    return (v) => (v == null || v.trim().isEmpty) ? message : null;
  }

  Widget _input(TextEditingController c, String h, {IconData? icon, String? helper, bool readOnly = false, TextInputType? keyboard, String? Function(String?)? validator}) => TextFormField(
    controller: c,
    readOnly: readOnly,
    validator: validator,
    keyboardType: keyboard,
    decoration: _inputDeco(h, Theme.of(context), icon: icon).copyWith(helperText: helper)
  );

  InputDecoration _emptyDeco() => InputDecoration(
        border: OutlineInputBorder(
            borderRadius: KRadius.input, borderSide: BorderSide.none),
      );

  InputDecoration _inputDeco(String h, ThemeData t, {IconData? icon}) => InputDecoration(
    hintText: h,
    suffixIcon: icon != null ? Icon(icon) : null,
    filled: true,
    fillColor: t.colorScheme.surfaceContainer,
    border: OutlineInputBorder(borderRadius: KRadius.input, borderSide: BorderSide.none),
    // Visible focus ring for keyboard users on web.
    focusedBorder: OutlineInputBorder(
        borderRadius: KRadius.input,
        borderSide: BorderSide(color: t.colorScheme.primary, width: 2)),
  );
}

/// A button row's controllers. [touched] keeps the error quiet until the user
/// has actually typed in the row.
class _LinkRow {
  final TextEditingController label = TextEditingController();
  final TextEditingController url = TextEditingController();
  bool touched = false;

  void set(String labelText, String urlText) {
    label.text = labelText;
    url.text = urlText;
  }

  void dispose() {
    label.dispose();
    url.dispose();
  }
}