import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/app_nav.dart';

import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

typedef RegisterClub = Future<Map<String, dynamic>> Function({
  required String registryId,
  required String officialEmail,
  required String position,
  List<Map<String, String>> council,
  String? note,
});

typedef LoadRegistry = Future<List<ClubRegistryEntry>> Function();

/// Council rows are typed as "Name - Position" per line. Blank lines are
/// ignored; at most [maxCouncil] rows survive.
const int maxCouncil = 10;

List<Map<String, String>> parseCouncil(String raw) {
  final out = <Map<String, String>>[];
  for (final line in raw.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final parts = t.split(RegExp(r'\s+[-–—]\s+|\s*\|\s*|\t+'));
    final name = parts.first.trim();
    if (name.isEmpty) continue;
    final position = parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    out.add({'name': name, 'position': position});
  }
  return out;
}

/// /clubs/register — claim a recognised club from the admin registry.
/// The caller becomes the club's first manager of a PENDING page; an admin
/// approves it. Name and ID are selected, never typed.
class ClubRegisterScreen extends StatefulWidget {
  final RegisterClub register;
  final LoadRegistry loadRegistry;

  const ClubRegisterScreen({
    super.key,
    this.register = ClubService.register,
    this.loadRegistry = ClubService.registryOpen,
  });

  @override
  State<ClubRegisterScreen> createState() => _ClubRegisterScreenState();
}

class _ClubRegisterScreenState extends State<ClubRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _council = TextEditingController();
  late Future<List<ClubRegistryEntry>> _entries = widget.loadRegistry();
  String? _entryId;
  String _position = 'president';
  bool _sending = false;
  String? _done; // derived handle once sent

  @override
  void dispose() {
    _email.dispose();
    _council.dispose();
    super.dispose();
  }

  ClubRegistryEntry? _entry(List<ClubRegistryEntry> entries) {
    for (final e in entries) {
      if (e.id == _entryId) return e;
    }
    return null;
  }

  Future<void> _submit(List<ClubRegistryEntry> entries) async {
    if (!_form.currentState!.validate()) return;
    final entry = _entry(entries);
    if (entry == null) return;
    final c = context.l10nRead.club;
    setState(() => _sending = true);
    try {
      final result = await widget.register(
        registryId: entry.id,
        officialEmail: _email.text.trim(),
        position: _position,
        council: parseCouncil(_council.text),
      );
      if (mounted) setState(() => _done = '${result['handle'] ?? ''}');
    } catch (e) {
      if (!mounted) return;
      showClubSnack(context, clubErrorText(c, e), error: true);
      // The entry was claimed or removed while the form was open.
      if (clubErrorCode(e) == 'registry_claimed' || clubErrorCode(e) == 'registry_not_found') {
        setState(() {
          _entryId = null;
          _entries = widget.loadRegistry();
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return Scaffold(
      appBar: AppBar(title: Text(c.registerClub)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<List<ClubRegistryEntry>>(
            future: _entries,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Padding(padding: const EdgeInsets.all(KSpace.l), child: KSkeleton.lines(5));
              }
              if (snap.hasError) {
                return ErrorState(onRetry: () => setState(() {
                      _entries = widget.loadRegistry();
                    }));
              }
              final entries = snap.data ?? const [];
              return AnimatedSwitcher(
                duration: KMotion.of(context).medium,
                child: _done != null
                    ? _sent(context, entries)
                    : entries.isEmpty
                        ? _noClubs(context, entries)
                        : _formView(context, entries),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sent(BuildContext context, List<ClubRegistryEntry> entries) {
    final c = context.l10n.club;
    final entry = _entry(entries);
    return BrandEmptyState(
      key: const ValueKey('sent'),
      illo: AppIllo.welcome,
      title: c.requestSent,
      message: c.requestSentBody.fill([entry?.name ?? '']),
      actionLabel: c.viewPage,
      onAction: () => completePublish(context, '/c/$_done'),
    );
  }

  Widget _noClubs(BuildContext context, List<ClubRegistryEntry> entries) {
    final c = context.l10n.club;
    return BrandEmptyState(
      key: const ValueKey('empty'),
      illo: AppIllo.noResults,
      title: c.noRegistryClubs,
      message: c.noRegistryClubsBody,
      actionLabel: c.directoryTitle,
      onAction: () => context.push('/clubs'),
    );
  }

  Widget _formView(BuildContext context, List<ClubRegistryEntry> entries) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final entry = _entry(entries);
    return Form(
      key: _form,
      child: ListView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.all(KSpace.l),
        children: [
          Text(c.registerIntro,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: KSpace.xl),
          DropdownButtonFormField<String>(
            initialValue: _entryId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.chooseClub,
              prefixIcon: const Icon(AppIcons.people),
            ),
            items: [
              for (final e in entries)
                DropdownMenuItem(
                  value: e.id,
                  child: Text('${e.name} · ${e.code}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _entryId = v),
            validator: (v) => v == null ? c.chooseClubRequired : null,
          ),
          if (entry != null) ...[
            const SizedBox(height: KSpace.m),
            KCard(
              padding: const EdgeInsets.all(KSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text([entry.code, if ((entry.faculty ?? '').isNotEmpty) entry.faculty!].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if ((entry.category ?? '').isNotEmpty) ...[
                    const SizedBox(height: KSpace.xs),
                    ClubPill(c.categoryLabel(entry.category)),
                  ],
                  const SizedBox(height: KSpace.xs),
                  Text(c.pageAddress.fill(['/c/${registryHandlePreview(entry.code, entry.name)}']),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
          const SizedBox(height: KSpace.m),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: c.officialEmail,
              helperText: c.officialEmailHelp,
              helperMaxLines: 2,
              prefixIcon: const Icon(AppIcons.email),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : c.emailInvalid;
            },
          ),
          const SizedBox(height: KSpace.m),
          DropdownButtonFormField<String>(
            initialValue: _position,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: c.position,
              prefixIcon: const Icon(AppIcons.person),
            ),
            items: [
              for (final k in clubPositions)
                DropdownMenuItem(value: k, child: Text(c.positionLabel(k))),
            ],
            onChanged: (v) => setState(() => _position = v ?? 'president'),
          ),
          const SizedBox(height: KSpace.m),
          TextFormField(
            controller: _council,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: c.council,
              helperText: c.councilHelp,
              helperMaxLines: 3,
              alignLabelWithHint: true,
            ),
            validator: (_) => parseCouncil(_council.text).length > maxCouncil ? c.councilTooLong : null,
          ),
          const SizedBox(height: KSpace.xl),
          FilledButton(
            onPressed: _sending ? null : () => _submit(entries),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(c.submitRequest),
          ),
        ],
      ),
    );
  }
}
