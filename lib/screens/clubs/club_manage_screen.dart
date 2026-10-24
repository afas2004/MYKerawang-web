import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/app_nav.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../services/post_service.dart';
import '../../utils/local_image.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

/// What the manage page can do; injected so tests run without Supabase.
class ClubManageActions {
  final Future<void> Function(ClubEdit edit) save;
  final Future<String?> Function() pickImage; // uploaded URL or null
  final Future<void> Function(String username) addOfficer;
  final Future<void> Function(String userId) removeOfficer;
  final Future<void> Function(String userId) transfer;

  /// Saves the private contact used by the club's listings. Null hides the
  /// section, so tests that only exercise the page details stay simple.
  final Future<void> Function(String? phone, String? paymentQrUrl)? saveContact;

  /// Uploads a payment QR image; defaults to [pickImage].
  final Future<String?> Function()? pickQr;

  const ClubManageActions({
    required this.save,
    required this.pickImage,
    required this.addOfficer,
    required this.removeOfficer,
    required this.transfer,
    this.saveContact,
    this.pickQr,
  });
}

class ClubEdit {
  final String name;
  final String? description, logoUrl, coverUrl, category, faculty, contactEmail;
  final Map<String, String> socials;
  const ClubEdit({
    required this.name,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.category,
    this.faculty,
    this.contactEmail,
    this.socials = const {},
  });
}

/// /c/:handle/manage — officers edit the page; the president manages
/// officers and can hand over the presidency.
class ClubManageScreen extends StatefulWidget {
  final String handle;
  const ClubManageScreen({super.key, required this.handle});

  @override
  State<ClubManageScreen> createState() => _ClubManageScreenState();
}

class _ClubManageScreenState extends State<ClubManageScreen> {
  late Future<(Club, String?, List<ClubMember>, ClubContact)?> _future = _load();

  Future<(Club, String?, List<ClubMember>, ClubContact)?> _load() async {
    final club = await ClubService.byHandle(widget.handle);
    if (club == null) return null;
    final role = await ClubService.myRole(club.id);
    final members = await ClubService.members(club.id);
    final contact = await ClubService.contact(club.id);
    return (club, role, members, contact);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<String?> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return null;
    final img = await LocalImage.fromXFile(picked);
    final urls = await PostService.uploadPhotos([img]);
    return urls.first;
  }

  /// Payment QRs must stay sharp to scan, so this keeps full quality.
  Future<String?> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 100);
    if (picked == null) return null;
    final img = await LocalImage.fromXFile(picked);
    final urls = await PostService.uploadPhotos([img]);
    return urls.first;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return FutureBuilder<(Club, String?, List<ClubMember>, ClubContact)?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: Padding(padding: const EdgeInsets.all(KSpace.l), child: KSkeleton.lines(6)),
          );
        }
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: ErrorState(onRetry: _reload));
        }
        final d = snap.data;
        if (d == null || !canManageClub(d.$2)) {
          return Scaffold(
            appBar: AppBar(),
            body: BrandEmptyState(icon: AppIcons.lock, title: d == null ? c.clubNotFound : c.notOfficer),
          );
        }
        final club = d.$1;
        return ClubManageView(
          club: club,
          myRole: d.$2!,
          myUserId: ClubService.currentUserId,
          members: d.$3,
          contact: d.$4,
          actions: ClubManageActions(
            save: (e) => ClubService.update(
              club.id,
              name: e.name,
              description: e.description,
              logoUrl: e.logoUrl,
              coverUrl: e.coverUrl,
              category: e.category,
              faculty: e.faculty,
              contactEmail: e.contactEmail,
              socials: e.socials,
            ),
            pickImage: _pickImage,
            saveContact: (phone, qr) =>
                ClubService.setContact(club.id, phone: phone, paymentQrUrl: qr),
            pickQr: _pickQr,
            addOfficer: (u) async {
              await ClubService.inviteOfficer(club.id, u);
              _reload();
            },
            removeOfficer: (id) async {
              await ClubService.removeOfficer(club.id, id);
              if (id == ClubService.currentUserId) {
                // No longer an officer: back to the club page (or up to
                // it when this page was opened cold).
                if (context.mounted) appBack(context);
              } else {
                _reload();
              }
            },
            transfer: (id) async {
              await ClubService.transferPresidency(club.id, id);
              _reload();
            },
          ),
        );
      },
    );
  }
}

/// Presentational manage page.
class ClubManageView extends StatefulWidget {
  final Club club;
  final String myRole;
  final String? myUserId;
  final List<ClubMember> members;
  final ClubManageActions actions;

  /// Private phone / payment QR for the club's listings; null hides the
  /// section.
  final ClubContact? contact;

  const ClubManageView({
    super.key,
    required this.club,
    required this.myRole,
    required this.myUserId,
    required this.members,
    required this.actions,
    this.contact,
  });

  @override
  State<ClubManageView> createState() => _ClubManageViewState();
}

class _ClubManageViewState extends State<ClubManageView> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.club.name);
  late final _description = TextEditingController(text: widget.club.description ?? '');
  late final _faculty = TextEditingController(text: widget.club.faculty ?? '');
  late final _email = TextEditingController(text: widget.club.contactEmail ?? '');
  late final _instagram = TextEditingController(text: widget.club.socials['instagram'] ?? '');
  late final _tiktok = TextEditingController(text: widget.club.socials['tiktok'] ?? '');
  late final _website = TextEditingController(text: widget.club.socials['website'] ?? '');
  late final _officer = TextEditingController();
  late final _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late String? _category = widget.club.category;
  late String? _logo = widget.club.logoUrl;
  late String? _cover = widget.club.coverUrl;
  late String? _qr = widget.contact?.paymentQrUrl;
  bool _saving = false;
  bool _adding = false;
  bool _savingContact = false;

  static final _email_ = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    for (final t in [_name, _description, _faculty, _email, _instagram, _tiktok, _website, _officer, _phone]) {
      t.dispose();
    }
    super.dispose();
  }

  ClubStrings get c => context.l10nRead.club;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.actions.save(ClubEdit(
        name: _name.text.trim(),
        description: _description.text.trim(),
        logoUrl: _logo,
        coverUrl: _cover,
        category: _category,
        faculty: _faculty.text.trim(),
        contactEmail: _email.text.trim(),
        socials: buildSocials(instagram: _instagram.text, tiktok: _tiktok.text, website: _website.text),
      ));
      if (mounted) showClubSnack(context, c.saved);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick(bool logo) async {
    try {
      final url = await widget.actions.pickImage();
      if (url != null && mounted) setState(() => logo ? _logo = url : _cover = url);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  Future<void> _saveContact() async {
    final save = widget.actions.saveContact;
    if (save == null) return;
    setState(() => _savingContact = true);
    try {
      final phone = _phone.text.trim();
      await save(phone.isEmpty ? null : phone, _qr);
      if (mounted) showClubSnack(context, c.contactSaved);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Future<void> _setQr() async {
    try {
      final pick = widget.actions.pickQr ?? widget.actions.pickImage;
      final url = await pick();
      if (url != null && mounted) setState(() => _qr = url);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  Future<void> _add() async {
    final u = cleanUsername(_officer.text);
    if (u.isEmpty) return;
    setState(() => _adding = true);
    try {
      await widget.actions.addOfficer(u);
      _officer.clear();
      if (mounted) showClubSnack(context, c.officerAdded.fill(['@$u']));
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(ClubMember m) async {
    final self = m.userId == widget.myUserId;
    final ok = await confirmClubAction(
      context,
      title: self ? c.leaveTitle : c.removeOfficerTitle.fill([m.name]),
      body: self ? c.leaveBody : c.removeOfficerBody,
      confirmLabel: self ? c.leave : c.remove,
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.actions.removeOfficer(m.userId);
      if (mounted) showClubSnack(context, self ? c.left : c.officerRemoved);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  Future<void> _transfer() async {
    final officers = widget.members.where((m) => m.role == 'officer').toList();
    if (officers.isEmpty) {
      showClubSnack(context, c.noOtherOfficers);
      return;
    }
    final pick = await showDialog<ClubMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(c.transferPick),
        children: [
          for (final o in officers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o.username == null ? o.name : '${o.name}  @${o.username}'),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final ok = await confirmClubAction(context,
        title: c.transferTitle.fill([pick.name]), body: c.transferBody, confirmLabel: c.confirm, destructive: true);
    if (!ok) return;
    try {
      await widget.actions.transfer(pick.userId);
      if (mounted) showClubSnack(context, c.transferred.fill([pick.name]));
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final president = isPresident(widget.myRole);
    final officers = widget.members.where((m) => m.isOfficer).toList();

    Widget section(String title, List<Widget> children, {String? help}) => Padding(
          padding: const EdgeInsets.only(bottom: KSpace.l),
          child: KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (help != null) ...[
                  const SizedBox(height: KSpace.xs),
                  Text(help, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: KSpace.m),
                ...children,
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(c.manageTitle.fill([widget.club.name]), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(KSpace.l),
            children: [
              if (!widget.club.isActive) ...[
                ClubStatusBanner(status: widget.club.status),
                const SizedBox(height: KSpace.l),
              ],
              section(c.pageDetails, [
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ClubLogo(url: _logo, name: _name.text, size: 64),
                          const SizedBox(width: KSpace.m),
                          Expanded(
                            child: Wrap(
                              spacing: KSpace.s,
                              runSpacing: KSpace.s,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _pick(true),
                                  icon: const Icon(AppIcons.camera, size: 18),
                                  label: Text('${c.logo} · ${c.changePhoto}'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _pick(false),
                                  icon: const Icon(AppIcons.photo, size: 18),
                                  label: Text('${c.cover} · ${c.changePhoto}'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_cover != null) ...[
                        const SizedBox(height: KSpace.m),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 96,
                            child: CachedNetworkImage(imageUrl: _cover!, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const SizedBox.shrink()),
                          ),
                        ),
                      ],
                      const SizedBox(height: KSpace.l),
                      TextFormField(
                        controller: _name,
                        maxLength: 80,
                        decoration: InputDecoration(labelText: c.clubName),
                        validator: (v) => (v ?? '').trim().length < 2 ? c.nameInvalid : null,
                      ),
                      const SizedBox(height: KSpace.s),
                      TextFormField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 6,
                        maxLength: 2000,
                        decoration: InputDecoration(labelText: c.description),
                      ),
                      const SizedBox(height: KSpace.s),
                      DropdownButtonFormField<String>(
                        initialValue: ClubStrings.categories.contains(_category) ? _category : null,
                        decoration: InputDecoration(labelText: c.category),
                        items: [
                          for (final k in ClubStrings.categories)
                            DropdownMenuItem(value: k, child: Text(c.categoryLabel(k))),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      const SizedBox(height: KSpace.m),
                      TextFormField(controller: _faculty, decoration: InputDecoration(labelText: c.faculty)),
                      const SizedBox(height: KSpace.m),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: c.contactEmail, prefixIcon: const Icon(AppIcons.email)),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          return t.isEmpty || _email_.hasMatch(t) ? null : c.emailInvalid;
                        },
                      ),
                      const SizedBox(height: KSpace.m),
                      TextFormField(
                          controller: _instagram,
                          decoration: InputDecoration(labelText: c.instagram, prefixText: '@')),
                      const SizedBox(height: KSpace.m),
                      TextFormField(
                          controller: _tiktok, decoration: InputDecoration(labelText: c.tiktok, prefixText: '@')),
                      const SizedBox(height: KSpace.m),
                      TextFormField(
                          controller: _website,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(labelText: c.website, prefixIcon: const Icon(AppIcons.website))),
                      const SizedBox(height: KSpace.l),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(c.saveChanges),
                      ),
                    ],
                  ),
                ),
              ]),
              if (widget.contact != null && widget.actions.saveContact != null)
                section(c.contactForListings, help: c.contactForListingsHelp, [
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: c.phone,
                      hintText: c.phoneHint,
                      prefixIcon: const Icon(AppIcons.phone),
                    ),
                  ),
                  const SizedBox(height: KSpace.m),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_qr == null)
                        OutlinedButton.icon(
                          onPressed: _setQr,
                          icon: const Icon(AppIcons.qrCode, size: 18),
                          label: Text(c.uploadQr),
                        )
                      else ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: _qr!,
                            width: 88,
                            height: 88,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const SizedBox(width: 88, height: 88),
                          ),
                        ),
                        const SizedBox(width: KSpace.m),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _setQr,
                              icon: const Icon(AppIcons.photo, size: 18),
                              label: Text(c.replaceQr),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _qr = null),
                              child: Text(c.removeQr),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: KSpace.m),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: _savingContact ? null : _saveContact,
                      child: _savingContact
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(c.saveContact),
                    ),
                  ),
                ]),
              section(c.officers, help: c.officersHelp, [
                for (final m in officers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 56,
                    leading: ClubLogo(url: m.avatarUrl, name: m.name, size: 40),
                    title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([if (m.username != null) '@${m.username}', c.roleLabel(m.role)].join(' · ')),
                    trailing: m.role == 'president'
                        ? null
                        : (president || m.userId == widget.myUserId)
                            ? TextButton(
                                onPressed: () => _remove(m),
                                child: Text(m.userId == widget.myUserId ? c.leave : c.remove),
                              )
                            : null,
                  ),
                if (president) ...[
                  const SizedBox(height: KSpace.s),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _officer,
                          decoration: InputDecoration(labelText: c.addOfficer, hintText: c.addOfficerHint),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: KSpace.s),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: FilledButton.tonal(
                          onPressed: _adding ? null : _add,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          child: Text(c.addOfficer),
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
              if (president)
                section(c.transfer, help: c.transferHelp, [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _transfer,
                      icon: const Icon(AppIcons.forward, size: 18),
                      label: Text(c.transfer),
                    ),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
