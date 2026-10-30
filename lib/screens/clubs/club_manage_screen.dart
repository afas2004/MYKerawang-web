import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/app_nav.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/access_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../services/post_service.dart';
import '../../utils/local_image.dart';
import '../../utils/photo_rules.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import 'club_strings.dart';
import 'club_widgets.dart';
import '../../widgets/app_toast.dart';

/// What the manage page can do; injected so tests run without Supabase.
class ClubManageActions {
  final Future<void> Function(ClubEdit edit) save;
  final Future<String?> Function() pickImage; // uploaded URL or null
  final Future<void> Function(String username) addMember;
  final Future<void> Function(String userId) removeMember;
  final Future<void> Function(String userId, String? position) setPosition;
  final Future<void> Function(String userId, String role) setRole;
  final Future<void> Function(String requestId, bool approve) decideJoin;
  final Future<void> Function(String userId) transfer;

  /// Opens/closes the club to join requests. Null hides the switch.
  final Future<void> Function(bool open)? setRecruitment;

  /// Saves the private contact used by the club's listings. Null hides the
  /// section, so tests that only exercise the page details stay simple.
  final Future<void> Function(String? phone, String? paymentQrUrl)? saveContact;

  /// Uploads a payment QR image; defaults to [pickImage].
  final Future<String?> Function()? pickQr;

  const ClubManageActions({
    required this.save,
    required this.pickImage,
    required this.addMember,
    required this.removeMember,
    required this.setPosition,
    required this.setRole,
    required this.decideJoin,
    required this.transfer,
    this.setRecruitment,
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
  late Future<(Club, String?, List<ClubMember>, ClubContact, List<Map<String, dynamic>>)?> _future = _load();

  Future<(Club, String?, List<ClubMember>, ClubContact, List<Map<String, dynamic>>)?> _load() async {
    final club = await ClubService.byHandle(widget.handle);
    if (club == null) return null;
    final role = await ClubService.myRole(club.id);
    final members = await ClubService.members(club.id);
    final contact = await ClubService.contact(club.id);
    final requests =
        canManageClub(role) ? await ClubService.joinRequests(club.id) : const <Map<String, dynamic>>[];
    return (club, role, members, contact, requests);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<String?> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return null;
    final img = await LocalImage.fromXFile(picked);
    if (!_acceptPhoto(img)) return null;
    final urls = await PostService.uploadPhotos([img]);
    return urls.first;
  }

  /// Payment QRs must stay sharp to scan, so this keeps full quality.
  Future<String?> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 100);
    if (picked == null) return null;
    final img = await LocalImage.fromXFile(picked);
    if (!_acceptPhoto(img)) return null;
    final urls = await PostService.uploadPhotos([img]);
    return urls.first;
  }

  /// The same byte gate the post/event pickers use. This path had none, so a
  /// renamed file or a tiny decompression bomb went straight to the bucket.
  bool _acceptPhoto(LocalImage img) {
    final problem = checkPhoto(img.bytes);
    if (problem == null) return true;
    if (mounted) {
      showToast(photoProblemText(context.l10nRead, problem));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return FutureBuilder<(Club, String?, List<ClubMember>, ClubContact, List<Map<String, dynamic>>)?>(
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
          joinRequests: d.$5,
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
            addMember: (u) async {
              await ClubService.addMember(club.id, u);
              _reload();
            },
            removeMember: (id) async {
              await ClubService.removeMember(club.id, id);
              if (id == ClubService.currentUserId) {
                // No longer in the club: back to the club page (or up to
                // it when this page was opened cold).
                if (context.mounted) appBack(context);
              } else {
                _reload();
              }
            },
            setPosition: (id, p) async {
              await ClubService.setMemberPosition(club.id, id, p);
              _reload();
            },
            setRole: (id, role) async {
              await ClubService.setMemberRole(club.id, id, role);
              _reload();
            },
            decideJoin: (requestId, approve) async {
              await ClubService.decideJoin(requestId, approve);
              _reload();
            },
            transfer: (id) async {
              await ClubService.transferPresidency(club.id, id);
              _reload();
            },
            setRecruitment: (open) async {
              await ClubService.setRecruitment(club.id, open);
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

  /// Pending join requests (empty for non-officers / when none).
  final List<Map<String, dynamic>> joinRequests;

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
    this.joinRequests = const [],
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
  late final _member = TextEditingController();
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
    for (final t in [_name, _description, _faculty, _email, _instagram, _tiktok, _website, _member, _phone]) {
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
    final u = cleanUsername(_member.text);
    if (u.isEmpty) return;
    setState(() => _adding = true);
    try {
      await widget.actions.addMember(u);
      _member.clear();
      if (mounted) showClubSnack(context, c.memberAdded.fill(['@$u']));
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
      title: self ? c.leaveTitle : c.removeMemberTitle.fill([m.name]),
      body: self ? c.leaveBody : c.removeMemberBody,
      confirmLabel: self ? c.leave : c.remove,
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.actions.removeMember(m.userId);
      if (mounted) showClubSnack(context, self ? c.left : c.memberRemoved);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  Future<void> _setPosition(ClubMember m) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(c.changePosition),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: Text(c.noPosition)),
          for (final p in clubPositions)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text(c.positionLabel(p))),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await widget.actions.setPosition(m.userId, picked.isEmpty ? null : picked);
      if (mounted) showClubSnack(context, c.positionChanged);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  Future<void> _setRole(ClubMember m, String role) async {
    try {
      await widget.actions.setRole(m.userId, role);
      if (mounted) showClubSnack(context, c.roleChanged);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    }
  }

  final Set<String> _busyJoin = {};

  Future<void> _decideJoin(Map<String, dynamic> r, bool approve) async {
    final id = '${r['id']}';
    final user = (r['user'] as Map?) ?? const {};
    final name = '${user['display_name'] ?? user['username'] ?? ''}';
    final ok = await confirmClubAction(
      context,
      title: (approve ? c.approveJoinTitle : c.rejectJoinTitle).fill([name]),
      body: approve ? c.approveJoinBody : c.rejectJoinBody,
      confirmLabel: approve ? c.approveJoin : c.rejectJoin,
      destructive: !approve,
    );
    if (!ok) return;
    setState(() => _busyJoin.add(id));
    try {
      await widget.actions.decideJoin(id, approve);
      if (mounted) showClubSnack(context, approve ? c.joinedClub.fill([name]) : c.requestRejected);
    } catch (e) {
      if (mounted) showClubSnack(context, clubErrorText(c, e), error: true);
    } finally {
      if (mounted) setState(() => _busyJoin.remove(id));
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
    final members = widget.members;

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
              section(context.l10n.clubRecruitment, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: widget.club.recruitmentOpen,
                  onChanged: widget.actions.setRecruitment == null
                      ? null
                      : (v) => widget.actions.setRecruitment!(v),
                  title: Text(context.l10n.clubRecruitmentOpen),
                  subtitle: Text(context.l10n.clubRecruitmentHelp),
                ),
              ]),
              section(c.joinRequests, help: c.joinRequestsHelp, [
                if (widget.joinRequests.isEmpty)
                  Text(c.noJoinRequests,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                else
                  for (final r in widget.joinRequests)
                    _JoinRequestTile(
                      request: r,
                      busy: _busyJoin.contains('${r['id']}'),
                      onApprove: () => _decideJoin(r, true),
                      onReject: () => _decideJoin(r, false),
                    ),
              ]),
              section(c.members, help: c.membersHelp, [
                for (final m in members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: 56,
                    leading: ClubLogo(url: m.avatarUrl, name: m.name, size: 40),
                    title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [if (m.username != null) '@${m.username}', c.rosterLabel(m.position, m.role)].join(' · '),
                    ),
                    trailing: m.role == 'president'
                        ? null
                        : m.userId == widget.myUserId
                            ? TextButton(onPressed: () => _remove(m), child: Text(c.leave))
                            : !president
                                ? null
                                : PopupMenuButton<String>(
                                    icon: const Icon(AppIcons.more, size: 20),
                                    onSelected: (v) => switch (v) {
                                      'promote' => _setRole(m, 'officer'),
                                      'demote' => _setRole(m, 'member'),
                                      'position' => _setPosition(m),
                                      _ => _remove(m),
                                    },
                                    itemBuilder: (_) => [
                                      if (m.role == 'member')
                                        PopupMenuItem(value: 'promote', child: Text(c.makeOfficer))
                                      else
                                        PopupMenuItem(value: 'demote', child: Text(c.makeMember)),
                                      PopupMenuItem(value: 'position', child: Text(c.changePosition)),
                                      PopupMenuItem(value: 'remove', child: Text(c.remove)),
                                    ],
                                  ),
                  ),
                if (president) ...[
                  const SizedBox(height: KSpace.s),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _member,
                          decoration: InputDecoration(labelText: c.addMember, hintText: c.addMemberHint),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: KSpace.s),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: FilledButton.tonal(
                          onPressed: _adding ? null : _add,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          child: Text(c.addMember),
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

/// One pending join request, with the applicant's message and decisions.
class _JoinRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _JoinRequestTile({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = (request['user'] as Map?) ?? const {};
    final name = '${user['display_name'] ?? user['username'] ?? ''}';
    final username = user['username'] as String?;
    final avatar = user['avatar_url'] as String?;
    final message = (request['message'] as String?)?.trim();
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: Container(
        padding: const EdgeInsets.all(KSpace.m),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.surfaceContainerHighest,
                  backgroundImage: avatar == null ? null : CachedNetworkImageProvider(avatar),
                  child: avatar == null
                      ? Icon(AppIcons.person, size: 18, color: scheme.onSurfaceVariant)
                      : null,
                ),
                const SizedBox(width: KSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      if (username != null)
                        Text('@$username', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    ],
                  ),
                ),
              ],
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: KSpace.s),
              Text(message),
            ],
            const SizedBox(height: KSpace.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: busy ? null : onReject, child: Text(c.rejectJoin)),
                const SizedBox(width: KSpace.s),
                FilledButton.tonal(
                  onPressed: busy ? null : onApprove,
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(c.approveJoin),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
