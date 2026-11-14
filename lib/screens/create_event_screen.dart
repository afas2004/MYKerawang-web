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
import '../utils/google_form_import.dart';
import '../widgets/form_picker.dart';
import '../widgets/google_form_import.dart';
import '../services/club_service.dart';
import '../services/moderation_service.dart';
import '../utils/categories.dart';
import '../widgets/post_as_selector.dart';
import '../widgets/app_toast.dart';
import '../widgets/event_timing_editor.dart';
import '../l10n/event_timing_strings.dart';
import '../utils/event_series.dart';
import '../services/feature_flags.dart';
import '../widgets/form_folds.dart';
import '../widgets/page_tips.dart';
import '../widgets/info_tip.dart';
import '../l10n/page_tips_strings.dart';

class CreateEventScreen extends StatefulWidget {
  final Map<String, dynamic>? eventToEdit;

  /// Overrides the owner's layout choice (Admin's preview, tests).
  final EventFormLayout? layout;

  /// Admin's preview: the real form, but nothing is saved or published and
  /// no draft or unsaved-changes guard is touched.
  final bool preview;

  const CreateEventScreen({super.key, this.eventToEdit, this.layout, this.preview = false});

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
    if (!widget.preview) {
      FormGuard.register(() => !_isLoading && _snapshot() != _initialSnapshot);
      if (event == null) _restoreDraft();
    }
    _loadIsAdmin();
    if (event == null && !widget.preview) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askTips());
    }
  }

  /// First new event: a walk through the form, for whichever layout is on.
  Future<void> _askTips() async {
    if (!mounted) return;
    final s = context.l10nRead;
    final steps = _layout == EventFormLayout.steps;
    Future<void> Function() goStep(int i) => () async {
          if (mounted && _step != i) setState(() => _step = i);
        };
    final shown = await PageTips.maybeShow(
      context,
      'create-event',
      () => steps
          ? [
              TipStep('ce-steps-bar', s.tipCeStepsBar),
              TipStep('ce-steps-next', s.tipCeStepsNext),
              TipStep('ce-when-mode', s.tipCeStepsWhen, before: goStep(1)),
              TipStep('ce-steps-reg', s.tipCeStepsReg, before: goStep(2)),
              TipStep('ce-steps-buttons', s.tipCeButtons, before: goStep(3)),
              TipStep('ce-steps-people', s.tipCePeople),
              TipStep('ce-publish', s.tipCePublish),
            ]
          : [
              TipStep('ce-basics', s.tipCeBasics),
              TipStep('ce-when-mode', s.tipCeWhen),
              TipStep('ce-repeats', s.tipCeRepeats),
              TipStep('ce-where', s.tipCeWhere),
              TipStep('ce-folds', s.tipCeFolds),
              TipStep('ce-fold-desc', s.tipCeDesc),
              TipStep('ce-fold-reg', s.tipCeReg),
              TipStep('ce-fold-buttons', s.tipCeButtons),
              TipStep('ce-fold-people', s.tipCePeople),
              TipStep('ce-publish', s.tipCePublish),
            ],
    );
    // The tips moved through the form; start the person at the top.
    if (!shown || !mounted) return;
    if (steps) {
      if (_step != 0) setState(() => _step = 0);
    } else {
      await TipAnchor.reveal('ce-basics');
    }
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
    _openFolds.dispose();
    if (!widget.preview) FormGuard.clear();
    // Leaving on purpose (publish / discard / close) drops the draft; a
    // page reload never gets here, so the draft survives that.
    if (!widget.preview) _draft.clear();
    super.dispose();
  }

  // --- SUBMIT LOGIC (SMART SORTING) ---
  Future<void> _submit() async {
    setState(() => _showTimingErrors = true);
    if (!_validateAll()) return;
    final s = context.l10nRead;
    if (widget.preview) {
      showToast(s.previewNote);
      return;
    }
    // The same checks the editor shows inline, so nothing half-valid is
    // published.
    final issue = _timing.issue;
    if (issue != SessionsIssue.none) {
      if (_layout == EventFormLayout.steps) setState(() => _step = 1);
      showToast(issueText(s, issue));
      return;
    }
    if (_timing.closeAfterStart) {
      if (_layout == EventFormLayout.steps) setState(() => _step = 2);
      _openFolds.value++;
      showToast(s.rcAfterStart);
      return;
    }
    // A photo is optional: an event without a cover still has a date block and
    // every list renders it. (It used to be required, which made a seeded or
    // quickly-created event impossible to open and re-save.)
    if (_categories.isEmpty) {
      if (_layout == EventFormLayout.steps) setState(() => _step = 0);
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
                fileOptions: photoUploadOptions(compressed),
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

  // ---------------------------------------------------------------------
  // Layout. The fields below are built once and arranged two ways (owner's
  // choice in Admin → Settings): one page with the optional parts folded,
  // or four steps. Same fields, same checks, same save.
  // ---------------------------------------------------------------------

  EventFormLayout get _layout => widget.layout ?? _layoutAtOpen;

  /// Read once when the page opens: a switch in Admin applies from the next
  /// visit, never mid-form.
  final EventFormLayout _layoutAtOpen = FeatureFlags.eventLayout;

  /// Steps layout: the step shown, and one form per step so Next can check
  /// just that step.
  int _step = 0;
  final List<GlobalKey<FormState>> _stepKeys = List.generate(4, (_) => GlobalKey<FormState>());

  /// Folded layout: opens every fold when publishing finds a problem.
  final ValueNotifier<int> _openFolds = ValueNotifier(0);

  /// Everything a fold summary reads, so summaries refresh while typing.
  late final Listenable _summaryInputs = Listenable.merge([
    _descController,
    _capacityCtrl,
    _feeCtrl,
    _picCtrl,
    _coOrganiserCtrl,
    _meritNoteCtrl,
    _timing,
    ..._contactCtrls.values,
  ]);

  /// Checks every field. On failure the steps layout jumps to the first
  /// step with a problem, and the folded layout opens its folds.
  bool _validateAll() {
    if (_layout == EventFormLayout.folded) {
      final ok = _formKey.currentState!.validate();
      if (!ok) _openFolds.value++;
      return ok;
    }
    for (var i = 0; i < _stepKeys.length; i++) {
      if (!(_stepKeys[i].currentState?.validate() ?? true)) {
        setState(() => _step = i);
        return false;
      }
    }
    return true;
  }

  /// Steps layout: what must be right before leaving step [i].
  bool _stepReady(int i) {
    final s = context.l10nRead;
    if (!(_stepKeys[i].currentState?.validate() ?? true)) return false;
    if (i == 0 && _categories.isEmpty) {
      showToast(s.categoryRequired);
      return false;
    }
    if (i == 1 && _timing.issue != SessionsIssue.none) {
      setState(() => _showTimingErrors = true);
      showToast(issueText(s, _timing.issue));
      return false;
    }
    if (i == 2 && _timing.closeAfterStart) {
      showToast(s.rcAfterStart);
      return false;
    }
    return true;
  }

  // ---- the parts --------------------------------------------------------

  Widget _hint(String text) => Text(text,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

  List<Widget> _photosPart() => [
        // Shared with the listing form. The picker returns after an await
        // (camera / file dialog); the form may be gone by then.
        MediaPickerGrid(
            items: _mediaItems,
            onChanged: () {
              if (mounted) setState(() {});
            }),
      ];

  List<Widget> _hostAndTitlePart() {
    final s = context.l10n;
    final theme = Theme.of(context);
    final isEditing = widget.eventToEdit != null;
    return [
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
              Expanded(child: _hint(s.create.clubEventNote)),
            ],
          ),
        ],
        const SizedBox(height: KSpace.l),
      ],
      _label(s.eventTitle, topPad: 0, info: s.infoTitle),
      _input(_titleController, s.eventTitleHint, validator: _required(s.title)),
    ];
  }

  List<Widget> _categoryPart() {
    final s = context.l10n;
    return [
      _label(s.category, info: s.infoCategory),
      CategoryField(
        kind: 'event',
        value: _categories,
        onChanged: (v) => setState(() => _categories = v),
        hintText: s.eventCategoryHint,
      ),
      const SizedBox(height: KSpace.xs),
      _hint(s.categoryPickHint.fill(['$kMaxCategoriesPerItem'])),
    ];
  }

  List<Widget> _descriptionPart({bool label = true}) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return [
      if (label) _label(s.description, info: s.infoDescription),
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
      // Same light markup the announcement composer documents: the event
      // page renders the description with it.
      const SizedBox(height: KSpace.xs),
      _hint(context.announceL10n.formattingHelp),
    ];
  }

  List<Widget> _whenPart() {
    final s = context.l10n;
    final theme = Theme.of(context);
    return [
      if (_timing.locked && _seriesCount != null) ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.repeat, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: KSpace.xs),
            Expanded(child: _hint(s.seriesEditBanner(_seriesCount!))),
          ],
        ),
        const SizedBox(height: KSpace.m),
      ],
      EventTimingEditor(controller: _timing, showErrors: _showTimingErrors),
    ];
  }

  List<Widget> _wherePart() => [
        TipAnchor(
          id: 'ce-where',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _whereFields(),
          ),
        ),
      ];

  List<Widget> _whereFields() {
    final s = context.l10n;
    return [
      _label(s.lmWhere, info: s.infoWhere),
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
        _label(s.location, info: s.infoLocation),
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
    ];
  }

  List<Widget> _registrationPart() {
    final s = context.l10n;
    return [
      RegistrationCloseField(controller: _timing),
      const SizedBox(height: KSpace.m),
      LayoutBuilder(builder: (context, c) {
        final capacity = _input(_capacityCtrl, s.evCapacity,
            icon: AppIcons.person, helper: s.evCapacityHint, keyboard: TextInputType.number);
        final fee = _input(_feeCtrl, s.evFee,
            icon: AppIcons.market, helper: s.evFeeHint, keyboard: TextInputType.number);
        if (c.maxWidth < 420) {
          return Column(children: [capacity, const SizedBox(height: 12), fee]);
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
      _label(s.evAudience, info: s.infoAudience),
      DropdownButtonFormField<String>(
        initialValue: _audience,
        decoration: _emptyDeco(),
        items: [
          for (final a in const ['uitm', 'kolej', 'klab', 'awam'])
            DropdownMenuItem(value: a, child: Text(s.evAudienceLabel(a))),
        ],
        onChanged: (v) => setState(() => _audience = v),
      ),
    ];
  }

  bool get _canOfferMerit => _hostAs?.isClub == true || _isAdminUser;

  List<Widget> _meritPart() {
    final s = context.l10n;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _meritOffered,
        onChanged: (v) => setState(() => _meritOffered = v),
        title: Text(s.evMerit),
        subtitle: _hint(s.evMeritHint),
      ),
      if (_meritOffered) ...[
        _input(_meritNoteCtrl, s.evMeritNote, icon: AppIcons.verified),
        const SizedBox(height: 12),
        _input(_activityRefCtrl, s.evActivityRef, icon: AppIcons.link),
      ],
    ];
  }

  List<Widget> _buttonsPart() {
    final s = context.l10n;
    // The old single "Registration link" field: Buttons do the same job, so
    // only an event that already has one still shows it.
    final hasOldLink = widget.eventToEdit != null &&
        '${widget.eventToEdit!['registration_link'] ?? ''}'.trim().isNotEmpty;
    return [
      Row(
        children: [
          Expanded(child: _hint(s.eventButtonsHint)),
          InfoTip(s.infoButtons),
        ],
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
              onPicked: (f) =>
                  setState(() => _links.add(_LinkRow()..set(s.formLinkLabel, f.path))),
            ),
          ],
        ),
      // A Google Form link in the description or a button: offer to make it
      // an in-app form. The button that pointed at it then points here.
      GoogleFormSuggestion(
        sources: [_descController, for (final l in _links) l.url, _linkController],
        onImported: (f) => setState(() {
          final row = _links.where((l) => findGoogleFormUrl(l.url.text) != null).firstOrNull;
          if (row != null) {
            row.set(s.formLinkLabel, f.path);
          } else if (_links.length < kActionLinksMax) {
            _links.add(_LinkRow()..set(s.formLinkLabel, f.path));
          }
        }),
      ),
      if (hasOldLink) ...[
        _label(s.registrationLinkOptional),
        // Launched from the event page, so https only — not `javascript:`.
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
    ];
  }

  List<Widget> _peoplePart() {
    final s = context.l10n;
    final theme = Theme.of(context);
    return [
      _label(s.eventPic, topPad: 0, info: s.infoPic),
      _input(_picCtrl, s.eventPicHint),
      _label(s.evCoOrganiser, info: s.infoCoOrganiser),
      // "Dengan kerjasama": usually a club, sometimes a person. Typing
      // suggests both — clubs insert "@[handle]" (a chip on the event page),
      // people "@username".
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
      _label(s.evContacts, info: s.infoContacts),
      _hint(s.evContactHint),
      const SizedBox(height: KSpace.s),
      _channelField(_contactCtrls['whatsapp']!, 'WhatsApp', AppIcons.phone, TextInputType.phone),
      _channelField(_contactCtrls['telegram']!, 'Telegram', AppIcons.send),
      _channelField(_contactCtrls['instagram']!, 'Instagram', AppIcons.camera),
      _channelField(_contactCtrls['email']!, 'Email', AppIcons.email, TextInputType.emailAddress),
      _channelField(_contactCtrls['link']!, 'Link', AppIcons.link),
    ];
  }

  // ---- fold summaries ---------------------------------------------------

  String _descriptionSummary() {
    final s = context.l10nRead;
    final d = _descController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return d.isEmpty ? s.foldEmpty : d;
  }

  String _registrationSummary() {
    final s = context.l10nRead;
    final close = switch (_timing.close) {
      CloseRule.atStart => s.rcAtStart,
      CloseRule.setTime => s.rcSetTime,
      CloseRule.never => s.rcNever,
    };
    final cap = int.tryParse(_capacityCtrl.text.trim());
    final fee = double.tryParse(_feeCtrl.text.trim());
    return [
      '${s.rcLabel}: $close',
      cap == null ? s.foldNoLimit : s.foldPlaces(cap),
      fee == null || fee <= 0 ? s.evFeeFree : 'RM ${_feeCtrl.text.trim()}',
      s.evAudienceLabel(_audience ?? 'uitm'),
    ].join(' · ');
  }

  String _buttonsSummary() {
    final s = context.l10nRead;
    final n = _links.where((l) => l.label.text.trim().isNotEmpty).length;
    return n == 0 ? s.foldNone : s.foldButtons(n);
  }

  String _peopleSummary() {
    final s = context.l10nRead;
    final set = [
      if (_picCtrl.text.trim().isNotEmpty) s.eventPic,
      if (_coOrganiserCtrl.text.trim().isNotEmpty) s.evCoOrganiser,
      for (final e in _contactCtrls.entries)
        if (e.value.text.trim().isNotEmpty) _channelName(e.key),
    ];
    return set.isEmpty ? s.foldNone : set.join(', ');
  }

  static String _channelName(String key) => switch (key) {
        'whatsapp' => 'WhatsApp',
        'telegram' => 'Telegram',
        'instagram' => 'Instagram',
        'email' => 'Email',
        _ => 'Link',
      };

  String _meritSummary() {
    final s = context.l10nRead;
    if (!_meritOffered) return s.foldOff;
    final note = _meritNoteCtrl.text.trim();
    return note.isEmpty ? s.foldOn : note;
  }

  // ---- the two arrangements ---------------------------------------------

  Widget _foldedLayout() {
    final s = context.l10n;
    return Form(
      key: _formKey,
      // Errors show as soon as a field is touched, not only on submit.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TipAnchor(
            id: 'ce-basics',
            child: FormSection(
              title: s.stepBasics,
              icon: AppIcons.edit,
              info: s.infoPhotos,
              children: [
                ..._photosPart(),
                const SizedBox(height: KSpace.l),
                ..._hostAndTitlePart(),
                ..._categoryPart(),
              ],
            ),
          ),
          FormSection(
            title: s.sectionWhenWhere,
            icon: AppIcons.calendar,
            children: [..._whenPart(), ..._wherePart()],
          ),
          TipAnchor(
            id: 'ce-folds',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          TipAnchor(id: 'ce-fold-desc', child: FoldSection(
            key: const ValueKey('fold-description'),
            title: s.description,
            icon: AppIcons.edit,
            summary: _descriptionSummary,
            listenTo: _summaryInputs,
            openSignal: _openFolds,
            children: _descriptionPart(label: false),
          )),
          TipAnchor(id: 'ce-fold-reg', child: FoldSection(
            key: const ValueKey('fold-registration'),
            title: s.evRegistration,
            icon: AppIcons.ticket,
            summary: _registrationSummary,
            listenTo: _summaryInputs,
            openSignal: _openFolds,
            children: _registrationPart(),
          )),
          if (_canOfferMerit)
            FoldSection(
              key: const ValueKey('fold-merit'),
              title: s.evMerit,
              icon: AppIcons.verified,
              summary: _meritSummary,
              listenTo: _summaryInputs,
              openSignal: _openFolds,
              children: _meritPart(),
            ),
          TipAnchor(id: 'ce-fold-buttons', child: FoldSection(
            key: const ValueKey('fold-buttons'),
            title: s.foldButtonsTitle,
            icon: AppIcons.link,
            summary: _buttonsSummary,
            listenTo: _summaryInputs,
            openSignal: _openFolds,
            children: _buttonsPart(),
          )),
          TipAnchor(id: 'ce-fold-people', child: FoldSection(
            key: const ValueKey('fold-people'),
            title: s.foldPeopleTitle,
            icon: AppIcons.email,
            summary: _peopleSummary,
            listenTo: _summaryInputs,
            openSignal: _openFolds,
            children: _peoplePart(),
          )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _stepNames(AppStrings s) =>
      [s.stepBasics, s.sectionWhenWhere, s.evRegistration, s.stepExtras];

  Widget _stepsLayout() {
    final s = context.l10n;
    final steps = <List<Widget>>[
      [
        ..._photosPart(),
        const SizedBox(height: KSpace.l),
        ..._hostAndTitlePart(),
        ..._categoryPart(),
        ..._descriptionPart(),
      ],
      [..._whenPart(), ..._wherePart()],
      [
        TipAnchor(
          id: 'ce-steps-reg',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _registrationPart(),
          ),
        ),
        if (_canOfferMerit) ...[const SizedBox(height: KSpace.m), ..._meritPart()],
      ],
      [
        TipAnchor(
          id: 'ce-steps-buttons',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_label(s.foldButtonsTitle, topPad: 0), ..._buttonsPart()],
          ),
        ),
        const SizedBox(height: KSpace.l),
        TipAnchor(
          id: 'ce-steps-people',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _peoplePart(),
          ),
        ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TipAnchor(id: 'ce-steps-bar', child: StepProgress(
          steps: _stepNames(s),
          current: _step,
          // Going back is always fine; going forward checks the steps between.
          onTap: (i) {
            if (i <= _step) return setState(() => _step = i);
            for (var k = _step; k < i; k++) {
              if (!_stepReady(k)) return setState(() => _step = k);
            }
            setState(() => _step = i);
          },
        )),
        const SizedBox(height: KSpace.l),
        for (var i = 0; i < steps.length; i++)
          // Every step stays mounted, so nothing typed is lost moving around
          // and publishing can check them all.
          Visibility(
            key: ValueKey('step-$i'),
            visible: i == _step,
            maintainState: true,
            child: Form(
              key: _stepKeys[i],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: steps[i],
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepsBar() {
    final s = context.l10n;
    final last = _step == _stepKeys.length - 1;
    if (last) {
      return TipAnchor(id: 'ce-publish', child: PublishBar(
        busy: _isLoading,
        editing: widget.eventToEdit != null,
        label: widget.eventToEdit != null ? s.saveChanges : s.publish,
        busyLabel: s.saving,
        onPressed: _submit,
      ));
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Row(
              children: [
                if (_step > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('step-back'),
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: Text(s.stepBack),
                    ),
                  ),
                  const SizedBox(width: KSpace.m),
                ],
                Expanded(
                  child: TipAnchor(id: 'ce-steps-next', child: FilledButton(
                    key: const ValueKey('step-next'),
                    onPressed: () {
                      if (_stepReady(_step)) setState(() => _step++);
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: Text(s.stepNext),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eventToEdit == null && !widget.preview) _draft.save(_draftData());
    final isEditing = widget.eventToEdit != null;
    final s = context.l10n;
    final steps = _layout == EventFormLayout.steps;

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: widget.preview
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(AppIcons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : const AppCloseButton(),
          title: Text(widget.preview
              ? '${s.previewTitle} · ${isEditing ? s.editEvent : s.createEvent}'
              : (isEditing ? s.editEvent : s.createEvent))),
      body: FormPageBody(child: steps ? _stepsLayout() : _foldedLayout()),
      bottomNavigationBar: steps
          ? _stepsBar()
          : TipAnchor(
              id: 'ce-publish',
              child: PublishBar(
                busy: _isLoading,
                editing: isEditing,
                label: isEditing ? s.saveChanges : s.publish,
                busyLabel: s.saving,
                onPressed: _submit,
              ),
            ),
    );
  }

  // --- FORM HELPERS (Input) ---
  Widget _label(String text, {double topPad = 16, String? info}) => Padding(
    // With an (i) the row is taller; trim the padding so labels line up.
    padding: EdgeInsets.only(bottom: info == null ? 8 : 0, top: info == null ? topPad : (topPad - 8).clamp(0, 16)),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: LabelWithInfo(text,
          info: info,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
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