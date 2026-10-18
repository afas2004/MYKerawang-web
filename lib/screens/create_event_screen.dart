import 'package:flutter/material.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_compressor.dart';
import '../utils/local_image.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';
import '../widgets/media_picker_grid.dart';

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

  // UNIFIED MEDIA LIST (Stores both Strings (URLs) and Files)
  // Index 0 is ALWAYS the Cover Photo.
  final List<dynamic> _mediaItems = [];
  
  List<String> _selectedTags = [];

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
if (event['tags'] != null) {
        _selectedTags = List<String>.from(event['tags']);
      }

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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    _linkController.dispose();
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
'tags': _selectedTags,
        'organizer_id': user!.id,
      };

      if (widget.eventToEdit != null) {
        await supabase.from('events').update(data).eq('id', widget.eventToEdit!['id']);
      } else {
        final newEvent = await supabase.from('events').insert(data).select().single();
        await _processMentions(_descController.text, newEvent['id']);
      }
      
      if (mounted) Navigator.pop(context, true);

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
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
    final theme = Theme.of(context);
    final isEditing = widget.eventToEdit != null;
    final s = context.l10n;

    return Scaffold(
      appBar: appBarConstrained(context,
          title: Text(isEditing ? s.editEvent : s.createEvent)),
      body: PageBody(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(s.photos, topPad: 0),
              
              // --- MEDIA (shared with the listing form) ---
              MediaPickerGrid(items: _mediaItems, onChanged: () => setState(() {})),

              const SizedBox(height: 24),

              // ... REST OF THE FORM (Title, Date, etc.) ...
              _label(s.eventTitle),
              _input(_titleController, s.eventTitleHint, validator: _required(s.title)),
              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(child: _dateSelector(true)), // Helper below
                    const SizedBox(width: 12),
                    Expanded(child: _dateSelector(false)), // Helper below
                  ],
                ),
              ),

              _label(s.location, topPad: 0),
              _input(_locationController, s.locationHint, validator: _required(s.location)),

              _label(s.registrationLinkOptional),
              _input(_linkController, "https://forms.gle/...", icon: Icons.link),

              _label(s.description),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                // REPLACE TextField WITH THIS:
                child: MentionInput(
                  controller: _descController, // Your existing controller
                  hintText: s.eventDescHint,
                  isMultiLine: true,
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      )),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor, 
          border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)))
        ),
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _submit,
          icon: _isLoading 
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
              : Icon(isEditing ? Icons.check : Icons.publish),
          label: Text(_isLoading ? s.saving : (isEditing ? s.saveChanges : s.publish)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
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
          borderRadius: BorderRadius.circular(12),
          child: AbsorbPointer(
            child: _input(
              TextEditingController(text: date == null ? '' : formatEventDate(date)), s.select,
              icon: Icons.calendar_today,
              readOnly: true,
              validator: isStart ? null : (_) => (_startDate != null && _endDate != null && !_endDate!.isAfter(_startDate!))
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
  );
}