import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/image_compressor.dart'; // Ensure you have this file from previous steps
import '../utils/local_image.dart';
import '../widgets/image_crop_dialog.dart';
import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';
import 'profile_cubit.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController(); // <--- NEW
  final _bioCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isSaving = false;
  String? _originalUsername;

  /// Snapshot of the loaded profile, used to detect unsaved edits.
  Map<String, dynamic> _loaded = {};
  
  // Images
  LocalImage? _avatarFile;
  LocalImage? _qrFile;
  String? _currentAvatarUrl;
  String? _currentQrUrl;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client.from('profiles').select().eq('id', user.id).single();
      
      setState(() {
        _loaded = {
          'display_name': data['display_name'] ?? '',
          'username': data['username'] ?? '',
          'bio': data['bio'] ?? '',
          'website': data['website'] ?? '',
          'phone_number': data['phone_number'] ?? '',
        };
        _nameCtrl.text = data['display_name'] ?? '';
        _usernameCtrl.text = data['username'] ?? ''; // <--- NEW
        _bioCtrl.text = data['bio'] ?? '';
        _websiteCtrl.text = data['website'] ?? '';
        _phoneCtrl.text = data['phone_number'] ?? '';
        
        _currentAvatarUrl = data['avatar_url'];
        _currentQrUrl = data['payment_qr_url'];
        
        _originalUsername = data['username']; // Keep track for uniqueness check
        
      });
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  Future<void> _pickImage(bool isAvatar) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: kPhotoMaxDimension, maxHeight: kPhotoMaxDimension, imageQuality: kPhotoQuality);
    if (picked == null) return;

    var img = await LocalImage.fromXFile(picked);

    // Avatars go through a crop popup so the user chooses the visible area
    // instead of the app blind-cropping the centre.
    if (isAvatar && mounted) {
      final cropped = await ImageCropDialog.show(context, img.bytes);
      if (cropped == null) return; // cancelled
      img = LocalImage(picked, cropped);
    }

    setState(() {
      if (isAvatar) {
        _avatarFile = img;
      } else {
        _qrFile = img;
      }
    });
  }

  // --- VALIDATION HELPER ---
  Future<bool> _isUsernameTaken(String username) async {
    if (username == _originalUsername?.toLowerCase()) return false; // No change = Safe
    final me = Supabase.instance.client.auth.currentUser?.id;

    final result = await Supabase.instance.client
        .from('profiles')
        .select('id')
        .eq('username', username)
        .neq('id', me ?? '')
        .maybeSingle();
        
    return result != null;
  }

  /// A rename frees the old handle and orphans old @mentions, so it is
  /// never auto-saved — only here, after an explicit confirmation.
  Future<bool> _confirmUsernameChange(String from, String to) async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.social.usernameChangeTitle),
        content: Text(s.social.usernameChangeBody.fill([from, to])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.social.usernameChangeConfirm)),
        ],
      ),
    );
    return ok ?? false;
  }

  String? _validateUsername(String? value) {
    final s = context.l10nRead;
    if (value == null || value.isEmpty) return s.usernameRequired;
    if (value.length < 3) return s.usernameMin;
    // Regex: Only letters, numbers, underscore
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) return s.usernameChars;
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final s = context.l10nRead;
    final scheme = Theme.of(context).colorScheme;

    setState(() => _isSaving = true);
    final user = Supabase.instance.client.auth.currentUser;
    final supabase = Supabase.instance.client;

    try {
      final newUsername = _usernameCtrl.text.trim().toLowerCase();

      // 1. Check Username Uniqueness
      if (await _isUsernameTaken(newUsername)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.usernameTaken.fill([newUsername]), style: TextStyle(color: scheme.onError)), backgroundColor: scheme.error),
          );
          setState(() => _isSaving = false);
        }
        return;
      }

      final oldUsername = _originalUsername;
      final renaming = oldUsername != null &&
          oldUsername.isNotEmpty &&
          oldUsername.toLowerCase() != newUsername;
      if (renaming && !await _confirmUsernameChange(oldUsername, newUsername)) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      String? newAvatarUrl = _currentAvatarUrl;
      String? newQrUrl = _currentQrUrl;

      // 2. Upload Images (With Compression)
      if (_avatarFile != null) {
        // Compress bytes (skipped automatically on web), then upload
        final bytesToUpload = await ImageCompressor.compressBytes(_avatarFile!.bytes);
        final path = 'avatars/${user!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('images').uploadBinary(
              path,
              bytesToUpload,
              fileOptions: FileOptions(contentType: imageContentType(bytesToUpload)),
            );
        newAvatarUrl = supabase.storage.from('images').getPublicUrl(path);
      }

      if (_qrFile != null) {
        final bytesToUpload = await ImageCompressor.compressBytes(_qrFile!.bytes);
        final uniquePath = 'qrs/${user!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supabase.storage.from('images').uploadBinary(
              uniquePath,
              bytesToUpload,
              fileOptions: FileOptions(contentType: imageContentType(bytesToUpload)),
            );
        newQrUrl = supabase.storage.from('images').getPublicUrl(uniquePath);
      }

      // 3. Update Database
      await supabase.from('profiles').update({
        'display_name': _nameCtrl.text.trim(),
        'username': newUsername, // <--- NEW
        'bio': _bioCtrl.text.trim(),
        'phone_number': _phoneCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'avatar_url': newAvatarUrl,
        'payment_qr_url': newQrUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user!.id);
      _originalUsername = newUsername;

      if (mounted) {
        // Composer avatar / name elsewhere read from the cubit.
        context.read<ProfileCubit>().loadProfile();
        Navigator.pop(context, true); 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.profileUpdated)));
      }
    } on PostgrestException catch (e) {
      // Unique index on username: someone took it between check and save.
      final msg = e.code == '23505'
          ? s.usernameTaken.fill([_usernameCtrl.text.trim().toLowerCase()])
          : s.errorWithDetail.fill([e.message]);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: TextStyle(color: scheme.onError)), backgroundColor: scheme.error));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]), style: TextStyle(color: scheme.onError)), backgroundColor: scheme.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// True when the form differs from what was loaded (10.6).
  bool get _isDirty =>
      _avatarFile != null ||
      _qrFile != null ||
      _nameCtrl.text.trim() != (_loaded['display_name'] ?? '') ||
      _usernameCtrl.text.trim() != (_loaded['username'] ?? '') ||
      _bioCtrl.text.trim() != (_loaded['bio'] ?? '') ||
      _websiteCtrl.text.trim() != (_loaded['website'] ?? '') ||
      _phoneCtrl.text.trim() != (_loaded['phone_number'] ?? '');

  // ---- Auto-save -----------------------------------------------------
  // Each text field except the username saves itself ~1s after typing
  // stops, showing a small spinner/tick in its suffix. The username and
  // images are committed by the bottom button (see [_save]).
  final Map<String, Timer?> _debounce = {};
  final Map<String, String> _fieldState = {}; // 'saving' | 'saved'

  void _autoSave(String column, String value) {
    _debounce[column]?.cancel();
    _debounce[column] = Timer(const Duration(milliseconds: 900), () async {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      if (mounted) setState(() => _fieldState[column] = 'saving');
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({column: value.trim()}).eq('id', user.id);
        _loaded[column] = value.trim();
        if (mounted) {
          setState(() => _fieldState[column] = 'saved');
          context.read<ProfileCubit>().loadProfile();
        }
      } catch (_) {
        if (mounted) setState(() => _fieldState.remove(column));
      }
    });
  }

  /// Small status marker shown at the end of a field.
  Widget? _statusIcon(String column) {
    final scheme = Theme.of(context).colorScheme;
    switch (_fieldState[column]) {
      case 'saving':
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case 'saved':
        return Icon(Icons.check_circle, size: 18, color: scheme.primary);
      default:
        return null;
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final s = context.l10nRead;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.discardChangesTitle),
        content: Text(s.unsavedChanges),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.keepEditing)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.discard,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.l10n;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: appBarConstrained(
        context,
        title: Text(context.l10n.editProfile),
      ),
      body: PageBody(child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- AVATAR ---
            Center(
              child: InkWell(
                onTap: () => _pickImage(true),
                borderRadius: BorderRadius.circular(50),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _avatarFile != null
                        ? MemoryImage(_avatarFile!.bytes)
                        : (_currentAvatarUrl != null ? NetworkImage(_currentAvatarUrl!) : null) as ImageProvider?,
                      child: _avatarFile == null && _currentAvatarUrl == null
                        ? const Icon(Icons.camera_alt, size: 30)
                        : null,
                    ),
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(Icons.edit,
                          size: 14, color: theme.colorScheme.onPrimary),
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => _pickImage(true),
                child: Text(context.l10n.changePhoto),
              ),
            ),
            const SizedBox(height: 16),

            // --- USERNAME & NAME ---
            TextFormField(
              controller: _usernameCtrl,
              decoration: _inputDeco(s.username).copyWith(
                helperText: s.social.usernameSavedOnSave,
                prefixText: "@ ",
              ),
              validator: _validateUsername,
              // Not auto-saved: refreshes the dirty state only.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: _inputDeco(s.displayName)
                  .copyWith(suffixIcon: _statusIcon('display_name')),
              validator: (v) => v!.isEmpty ? s.required : null,
              onChanged: (v) => _autoSave('display_name', v),
            ),
            const SizedBox(height: 16),

            // --- BIO ---
            TextFormField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration:
                  _inputDeco(s.bio).copyWith(suffixIcon: _statusIcon('bio')),
              maxLength: 150,
              onChanged: (v) => _autoSave('bio', v),
            ),
            const SizedBox(height: 16),

            
            // --- CONTACT INFO ---
            const Divider(),
            const SizedBox(height: 16),
            Text(s.contactDetails, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: s.phoneNumber,
                hintText: s.phoneHint,
                prefixText: '+60 ', // Visual cue
                suffixIcon: _statusIcon('phone_number'),
              ),
              // 1. Show Number Pad only
              keyboardType: TextInputType.phone,

              // 2. BLOCK letters/symbols completely
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly, // Only allows 0-9
                LengthLimitingTextInputFormatter(11),   // Limit length (optional)
              ],
              // Optional, but needed before selling (create_listing).
              validator: (val) {
                if (val == null || val.isEmpty) return null;
                if (val.length < 9) return s.phoneInvalid;
                return null;
              },
              onChanged: (v) {
                if (v.isEmpty || v.length >= 9) _autoSave('phone_number', v);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _websiteCtrl,
              decoration: _inputDeco(s.website)
                  .copyWith(suffixIcon: _statusIcon('website')),
              onChanged: (v) => _autoSave('website', v),
            ),
            const SizedBox(height: 24),

            // --- DUITNOW QR ---
            Text(s.duitnowForSelling, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(s.duitnowHelp,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            // Square, centred — a QR isn't a banner (H4/10.2)
            Center(
              child: InkWell(
                onTap: () => _pickImage(false),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest,
                    image: _qrFile != null
                        ? DecorationImage(image: MemoryImage(_qrFile!.bytes), fit: BoxFit.contain)
                        : (_currentQrUrl != null ? DecorationImage(image: NetworkImage(_currentQrUrl!), fit: BoxFit.contain) : null),
                  ),
                  child: (_qrFile == null && _currentQrUrl == null)
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2, size: 44, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 6),
                            Text(s.tapToUploadQr,
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        )
                      : null,
                ),
              ),
            ),
            // Always offer a way to change an existing QR
            if (_qrFile != null || _currentQrUrl != null)
              Center(
                child: TextButton.icon(
                  onPressed: () => _pickImage(false),
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(s.changeQr),
                ),
              ),
            const SizedBox(height: 32),

            // Text fields save themselves; this commits picked images and
            // gives an explicit "I'm done" action.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_isSaving ? s.saving : s.saveChanges),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      )),
    ),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
