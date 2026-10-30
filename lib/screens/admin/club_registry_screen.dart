import 'package:flutter/material.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../services/admin_unlock.dart';
import '../../services/moderation_service.dart';
import '../../utils/app_nav.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import '../clubs/club_strings.dart';
import '../clubs/club_widgets.dart';
import 'admin_lock_screen.dart';
import 'admin_screen.dart';

/// /admin/clubs/registry — the recognised-club list registration selects
/// from. Admins add/edit entries; a claimed entry drops out of the picker.
class ClubRegistryScreen extends StatefulWidget {
  final Future<List<ClubRegistryEntry>> Function()? load;
  final Future<void> Function({
    String? id,
    required String code,
    required String name,
    String? faculty,
    String? category,
    bool active,
  })? save;
  final Future<bool> Function()? checkAdmin;

  const ClubRegistryScreen({super.key, this.load, this.save, this.checkAdmin});

  @override
  State<ClubRegistryScreen> createState() => _ClubRegistryScreenState();
}

class _ClubRegistryScreenState extends State<ClubRegistryScreen> {
  late final Future<bool> _access = _checkAccess();
  late Future<List<ClubRegistryEntry>> _future = _load();

  /// The registry is an admin surface like the console, so it asks for the same
  /// PIN and re-locks on the same idle timer. It used to check `isAdmin` only,
  /// which let anyone who knew the route edit the recognised-club list.
  Future<bool> _checkAccess() async {
    final ok = await (widget.checkAdmin ?? ModerationService.isAdmin)();
    if (ok) {
      var configured = false;
      try {
        configured = await ModerationService.adminPinConfigured();
      } catch (_) {
        // A transient failure must not lock an admin out of the registry.
        configured = false;
      }
      AdminUnlock.instance.setConfigured(configured);
    }
    return ok;
  }

  Future<List<ClubRegistryEntry>> _load() => (widget.load ?? ClubService.adminRegistry)();

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _edit(ClubRegistryEntry? entry) async {
    final c = context.l10nRead.club;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ClubRegistryDialog(
        entry: entry,
        save: widget.save ?? ClubService.saveRegistry,
      ),
    );
    if (saved == true && mounted) {
      showModSnack(context, c.registrySaved);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final m = context.l10n.mod;
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(leading: const AppBackButton(), title: Text(c.registryTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return Scaffold(
            appBar: AppBar(leading: const AppBackButton(), title: Text(c.registryTitle)),
            body: ModEmptyState(icon: ModIcons.lock, title: m.adminOnly, body: m.adminOnlyBody),
          );
        }

        return ListenableBuilder(
          listenable: AdminUnlock.instance,
          builder: (context, _) {
            if (AdminUnlock.instance.configured && !AdminUnlock.instance.unlocked) {
              return Scaffold(
                appBar: AppBar(leading: const AppBackButton(), title: Text(c.registryTitle)),
                body: AdminLockScreen(
                  unlock: AdminUnlock.instance.unlock,
                  onUnlocked: () {},
                ),
              );
            }
            return _registry(context);
          },
        );
      },
    );
  }

  Widget _registry(BuildContext context) {
    final c = context.l10n.club;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton(), title: Text(c.registryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(AppIcons.create),
        label: Text(c.addRegistryClub),
      ),
      body: Listener(
        // Idle timer: touching the list keeps the unlock alive.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AdminUnlock.instance.touch(),
        onPointerSignal: (_) => AdminUnlock.instance.touch(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 0),
              child: Text(
                c.registrySub,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: AdminAsyncList<ClubRegistryEntry>(
                future: _future,
                onRetry: _reload,
                empty: ModEmptyState(icon: AppIcons.people, title: c.registryEmpty),
                itemBuilder: (context, e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
                  child: ClubRegistryCard(entry: e, onTap: () => _edit(e)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One registry entry. Claims show the linked club's handle so an admin can
/// tell "not registered yet" from "already has a page".
class ClubRegistryCard extends StatelessWidget {
  final ClubRegistryEntry entry;
  final VoidCallback onTap;

  const ClubRegistryCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final meta = [entry.code, if ((entry.faculty ?? '').isNotEmpty) entry.faculty!].join(' · ');
    return KCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(entry.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              if (!entry.isActive)
                ClubPill(c.registryInactive,
                    background: scheme.surfaceContainerHighest, foreground: scheme.onSurfaceVariant)
              else if (entry.claimed)
                ClubPill(c.registryClaimed,
                    background: scheme.primaryContainer, foreground: scheme.onPrimaryContainer)
              else
                ClubPill(c.registryAvailable,
                    background: scheme.tertiaryContainer, foreground: scheme.onTertiaryContainer),
            ],
          ),
          const SizedBox(height: 2),
          Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          if (entry.claimed) ...[
            const SizedBox(height: KSpace.xs),
            Text('@${entry.clubHandle ?? ''} · ${c.statusLabel(entry.clubStatus)}', style: muted),
          ],
          if ((entry.category ?? '').isNotEmpty) ...[
            const SizedBox(height: KSpace.xs),
            ClubPill(c.categoryLabel(entry.category)),
          ],
        ],
      ),
    );
  }
}

/// Add/edit dialog. Pops true after a successful save.
class ClubRegistryDialog extends StatefulWidget {
  final ClubRegistryEntry? entry;
  final Future<void> Function({
    String? id,
    required String code,
    required String name,
    String? faculty,
    String? category,
    bool active,
  }) save;

  const ClubRegistryDialog({super.key, this.entry, required this.save});

  @override
  State<ClubRegistryDialog> createState() => _ClubRegistryDialogState();
}

class _ClubRegistryDialogState extends State<ClubRegistryDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.entry?.code ?? '');
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _faculty = TextEditingController(text: widget.entry?.faculty ?? '');
  late String? _category = widget.entry?.category;
  late bool _active = widget.entry?.isActive ?? true;
  bool _saving = false;
  String? _error;

  static final _codeRe = RegExp(r'^[A-Za-z0-9._/-]{2,64}$');

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _faculty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(
        id: widget.entry?.id,
        code: _code.text,
        name: _name.text,
        faculty: _faculty.text,
        category: _category,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = clubErrorText(context.l10nRead.club, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return AlertDialog(
      title: Text(widget.entry == null ? c.addRegistryClub : c.editRegistryClub),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _code,
                  maxLength: 64,
                  decoration: InputDecoration(
                    labelText: c.registryCode,
                    helperText: c.registryCodeHelp,
                    helperMaxLines: 2,
                  ),
                  validator: (v) => _codeRe.hasMatch((v ?? '').trim()) ? null : c.registryCodeInvalid,
                ),
                const SizedBox(height: KSpace.s),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: c.clubName),
                  validator: (v) => (v ?? '').trim().length < 2 ? c.nameInvalid : null,
                ),
                const SizedBox(height: KSpace.s),
                TextFormField(
                  controller: _faculty,
                  decoration: InputDecoration(labelText: c.registryFaculty),
                ),
                const SizedBox(height: KSpace.m),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: c.category),
                  items: [
                    for (final k in ClubStrings.categories)
                      DropdownMenuItem(value: k, child: Text(c.categoryLabel(k))),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.registryActive),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: KSpace.s),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(c.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(c.saveRegistry),
        ),
      ],
    );
  }
}
