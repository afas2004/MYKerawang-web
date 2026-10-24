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
import '../utils/formatters.dart';
import '../utils/app_nav.dart';
import '../utils/form_draft.dart';
import '../widgets/category_picker.dart';
import '../widgets/form_layout.dart';
import '../widgets/media_picker_grid.dart';
import '../widgets/restriction_gate.dart';
import '../l10n/create_strings.dart';
import '../services/club_service.dart';
import '../utils/categories.dart';
import '../widgets/post_as_selector.dart';

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
  
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = false;

  /// Yourself (null) or one of your clubs: club events are official.
  PostAsOption? _hostAs;

  // UNIFIED MEDIA LIST (Stores both Strings (URLs) and Files)
  // Index 0 is ALWAYS the Cover Photo.
  final List<dynamic> _mediaItems = [];
  
  /// Stored slugs from `content_categories`; first one is the main topic.
  List<String> _categories = [];

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
    _descController = TextEditingController(text: event?['description'] ?? '');
    _linkController = TextEditingController(text: event?['registration_link'] ?? '');
    
    if (event != null) {
      _startDate = DateTime.parse(event['start_datetime']).toLocal();
      _endDate = event['end_datetime'] != null 
          ? DateTime.parse(event['end_datetime']).toLocal() 
          : _startDate!.add(const Duration(hours: 2));
      _categories = _categoriesFrom(event);

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
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(hours: 2));
    }

    // Leaving with unsaved input asks first (router onExit).
    _initialSnapshot = _snapshot();
    FormGuard.register(() => !_isLoading && _snapshot() != _initialSnapshot);
    if (event == null) _restoreDraft();
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(s.draftRestored),
      action: SnackBarAction(
        label: s.discard,
        onPressed: () {
          if (!mounted) return;
          setState(() {
            _titleController.clear();
            _locationController.clear();
            _descController.clear();
            _linkController.clear();
            _categories = [];
          });
          _draft.clear();
        },
      ),
    ));
  }

  late final String _initialSnapshot;

  /// Everything the user can change, to tell whether leaving loses input.
  String _snapshot() => [
        _titleController.text,
        _locationController.text,
        _descController.text,
        _linkController.text,
        _startDate?.toIso8601String(),
        _endDate?.toIso8601String(),
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
    FormGuard.clear();
    // Leaving on purpose (publish / discard / close) drops the draft; a
    // page reload never gets here, so the draft survives that.
    _draft.clear();
    super.dispose();
  }

  // --- SUBMIT LOGIC (SMART SORTING) ---
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final s = context.l10nRead;
    if (_mediaItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.addPhotoRequired)));
      return;
    }
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.categoryRequired)));
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

      final data = {
        'title': _titleController.text,
        'location': _locationController.text,
        'description': _descController.text,
        'registration_link': _linkController.text.isEmpty ? null : _linkController.text,
        'start_datetime': _startDate!.toUtc().toIso8601String(),
        'end_datetime': _endDate!.toUtc().toIso8601String(),
        'image_url': finalCoverUrl,      // Index 0
        'gallery_urls': finalGalleryUrls, // Index 1+
        // The Public switch was removed: new events are public, and an
        // edit leaves whatever is_public an existing event already has.
        if (widget.eventToEdit == null) 'is_public': true,
        'categories': _categories,
        'organizer_id': user!.id,
      };

      if (widget.eventToEdit != null) {
        await supabase.from('events').update(data).eq('id', widget.eventToEdit!['id']);
        // Back to the event page, which refreshes.
        if (mounted) completeEdit(context, message: s.eventUpdated);
      } else {
        final insert = (_hostAs ?? const PostAsOption.self('')).applyTo(data, hasAnonymous: false);
        final newEvent = await supabase.from('events').insert(insert).select().single();
        await _processMentions(_descController.text, newEvent['id']);
        // The form is replaced by the new event's page, so back from
        // there returns to where the user started, not to this form.
        if (mounted) {
          completePublish(context, '/event/${newEvent['id']}',
              extra: newEvent, message: s.eventPublished);
        }
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                    ),
                  ),
                ],
              ),
              FormSection(
                title: s.category,
                icon: AppIcons.filter,
                children: [
                  CategoryPicker(
                    kind: 'event',
                    value: _categories,
                    onChanged: (v) => setState(() => _categories = v),
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
                title: s.sectionWhenWhere,
                icon: AppIcons.calendar,
                children: [
                  LayoutBuilder(builder: (context, c) {
                    // Side by side when there's room, stacked on small phones.
                    if (c.maxWidth < 420) {
                      return Column(children: [
                        _dateSelector(true),
                        const SizedBox(height: 12),
                        _dateSelector(false),
                      ]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _dateSelector(true)),
                        const SizedBox(width: 12),
                        Expanded(child: _dateSelector(false)),
                      ],
                    );
                  }),
                  _label(s.location),
                  _input(_locationController, s.locationHint, validator: _required(s.location)),
                  _label(s.registrationLinkOptional),
                  _input(_linkController, "https://forms.gle/...", icon: AppIcons.link),
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

  // --- FORM HELPERS (Date, Input) ---
  Widget _dateSelector(bool isStart) {
    final s = context.l10n;
    final date = isStart ? _startDate : _endDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(isStart ? s.starts : s.ends, topPad: 0),
        InkWell(
          onTap: () => _pickDateTime(isStart),
          borderRadius: KRadius.input,
          child: AbsorbPointer(
            child: _input(
              TextEditingController(text: date == null ? '' : formatEventDate(date)), s.select,
              icon: AppIcons.calendar,
              readOnly: true,
              validator: isStart
                  ? (_) => _startDate == null ? s.fieldRequired.fill([s.starts]) : null
                  : (_) => (_startDate != null && _endDate != null && !_endDate!.isAfter(_startDate!))
                      ? s.mustBeAfterStart
                      : null,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDateTime(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? now);
    
    final d = await showDatePicker(
      context: context, 
      firstDate: now.subtract(const Duration(days: 365)), 
      lastDate: now.add(const Duration(days: 365)), 
      initialDate: initial
    );
    if (d == null) return;
    
    if (mounted) {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
      if (t == null) return;
      
      setState(() {
        final res = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        if (isStart) {
          _startDate = res;
          if (_endDate == null || _endDate!.isBefore(res)) _endDate = res.add(const Duration(hours: 2));
        } else {
          _endDate = res;
        }
      });
    }
  }

  Widget _label(String text, {double topPad = 16}) => Padding(
    padding: EdgeInsets.only(bottom: 8, top: topPad),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))
  );

  String? Function(String?) _required(String field) {
    final message = context.l10n.fieldRequired.fill([field]);
    return (v) => (v == null || v.trim().isEmpty) ? message : null;
  }

  Widget _input(TextEditingController c, String h, {IconData? icon, bool readOnly = false, String? Function(String?)? validator}) => TextFormField(
    controller: c, 
    readOnly: readOnly,
    validator: validator,
    decoration: _inputDeco(h, Theme.of(context), icon: icon)
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