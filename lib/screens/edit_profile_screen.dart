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
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../widgets/brand/brand.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
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
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('profiles')
          .select('display_name, username, bio, website, avatar_url')
          .eq('id', user.id)
          .single();

      // Phone + payment QR are private: they live in profile_contacts,
      // readable only by the owner. Separate so a failure here doesn't
      // block editing the public profile.
      Map<String, dynamic>? contact;
      try {
        contact = await supabase
            .from('profile_contacts')
            .select('phone_number, payment_qr_url')
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (e) {
        debugPrint("Error loading contact details: $e");
      }
      if (!mounted) return;

      setState(() {
        _loaded = {
          'display_name': data['display_name'] ?? '',
          'username': data['username'] ?? '',
          'bio': data['bio'] ?? '',
          'website': data['website'] ?? '',
          'phone_number': contact?['phone_number'] ?? '',
        };
        _nameCtrl.text = data['display_name'] ?? '';
        _usernameCtrl.text = data['username'] ?? ''; // <--- NEW
        _bioCtrl.text = data['bio'] ?? '';
        _websiteCtrl.text = data['website'] ?? '';
        _phoneCtrl.text = contact?['phone_number'] ?? '';
        
        _currentAvatarUrl = data['avatar_url'];
        _currentQrUrl = contact?['payment_qr_url'];
        
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
        'website': _websiteCtrl.text.trim(),
        'avatar_url': newAvatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user!.id);
      await _saveContact(user.id, {
        'phone_number': _nullIfEmpty(_phoneCtrl.text),
        'payment_qr_url': newQrUrl,
      });
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

  /// Private columns, stored in profile_contacts rather than profiles.
  static const _contactColumns = {'phone_number', 'payment_qr_url'};

  static String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  /// Upserts the user's own profile_contacts row.
  Future<void> _saveContact(String userId, Map<String, dynamic> values) =>
      Supabase.instance.client.from('profile_contacts').upsert({
        'user_id': userId,
        ...values,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

  void _autoSave(String column, String value) {
    _debounce[column]?.cancel();
    _debounce[column] = Timer(const Duration(milliseconds: 900), () async {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      if (mounted) setState(() => _fieldState[column] = 'saving');
      try {
        if (_contactColumns.contains(column)) {
          await _saveContact(user.id, {column: _nullIfEmpty(value)});
        } else {
          await Supabase.instance.client
              .from('profiles')
              .update({column: value.trim()}).eq('id', user.id);
        }
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
        return Icon(AppIcons.success, size: 18, color: scheme.primary);
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // --- PROFILE PHOTO ---
            _FormSection(
              title: s.shell.profilePhoto,
              children: [
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: s.changePhoto,
                      child: InkWell(
                        onTap: () => _pickImage(true),
                        customBorder: const CircleBorder(),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              backgroundImage: _avatarFile != null
                                ? MemoryImage(_avatarFile!.bytes)
                                : (_currentAvatarUrl != null ? NetworkImage(_currentAvatarUrl!) : null) as ImageProvider?,
                              child: _avatarFile == null && _currentAvatarUrl == null
                                ? Icon(AppIcons.camera, size: 28, color: theme.colorScheme.onPrimaryContainer)
                                : null,
                            ),
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: theme.colorScheme.primary,
                              child: Icon(AppIcons.edit,
                                  size: 14, color: theme.colorScheme.onPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: KSpace.l),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: () => _pickImage(true),
                      icon: const Icon(AppIcons.photo),
                      label: Text(s.changePhoto),
                    ),
                  ],
                ),
              ],
            ),

            // --- ABOUT YOU (public) ---
            _FormSection(
              title: s.shell.aboutYou,
              subtitle: s.shell.publicProfile,
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: _inputDeco(s.username).copyWith(
                    helperText: s.social.usernameSavedOnSave,
                    helperMaxLines: 2,
                    prefixText: "@ ",
                  ),
                  validator: _validateUsername,
                  // Not auto-saved: refreshes the dirty state only.
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: KSpace.l),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDeco(s.displayName)
                      .copyWith(suffixIcon: _statusIcon('display_name')),
                  validator: (v) => v!.isEmpty ? s.required : null,
                  onChanged: (v) => _autoSave('display_name', v),
                ),
                const SizedBox(height: KSpace.l),
                TextFormField(
                  controller: _bioCtrl,
                  maxLines: 3,
                  decoration:
                      _inputDeco(s.bio).copyWith(suffixIcon: _statusIcon('bio')),
                  maxLength: 150,
                  onChanged: (v) => _autoSave('bio', v),
                ),
                const SizedBox(height: KSpace.s),
                TextField(
                  controller: _websiteCtrl,
                  keyboardType: TextInputType.url,
                  decoration: _inputDeco(s.website)
                      .copyWith(suffixIcon: _statusIcon('website')),
                  onChanged: (v) => _autoSave('website', v),
                ),
              ],
            ),

            // --- CONTACT & PAYMENTS (private) ---
            _FormSection(
              title: s.shell.contactPayments,
              subtitle: s.shell.contactPrivate,
              icon: AppIcons.lock,
              children: [
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: _inputDeco(s.phoneNumber).copyWith(
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
                const SizedBox(height: KSpace.xl),
                Text(s.duitnowForSelling, style: theme.textTheme.titleSmall),
                Text(s.duitnowHelp,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: KSpace.m),
                // Square, centred — a QR isn't a banner (H4/10.2)
                Center(
                  child: InkWell(
                    onTap: () => _pickImage(false),
                    borderRadius: KRadius.card,
                    child: Container(
                      height: 200,
                      width: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: KRadius.card,
                        color: theme.colorScheme.surfaceContainerHighest,
                        image: _qrFile != null
                            ? DecorationImage(image: MemoryImage(_qrFile!.bytes), fit: BoxFit.contain)
                            : (_currentQrUrl != null ? DecorationImage(image: NetworkImage(_currentQrUrl!), fit: BoxFit.contain) : null),
                      ),
                      child: (_qrFile == null && _currentQrUrl == null)
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(AppIcons.qrCode, size: 44, color: theme.colorScheme.onSurfaceVariant),
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
                      icon: const Icon(AppIcons.edit, size: 16),
                      label: Text(s.changeQr),
                    ),
                  ),
              ],
            ),
          ],
        ),
      )),
      // Text fields save themselves; this commits the username and picked
      // images, and is always in reach.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 648),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.check),
                label: Text(_isSaving ? s.saving : s.saveChanges),
              ),
            ),
          ),
        ),
      ),
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

/// A titled card grouping related fields.
class _FormSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  const _FormSection({
    required this.title,
    this.subtitle,
    this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(KSpace.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: KRadius.card,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: KSpace.l),
          ...children,
        ],
      ),
    );
  }
}
