import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/safe_link_strings.dart';
import '../../language_cubit.dart';
import '../../services/allowed_links.dart';
import '../../utils/safe_links.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';

/// Admin → Allowed links: the sites whose links are tappable in
/// user-written text (`allowed_link_domains`; RLS lets admins add and
/// remove). See `utils/safe_links.dart` for how links are matched.
class AllowedLinksTab extends StatefulWidget {
  /// Tests: list without a database.
  final Future<List<AllowedDomain>> Function()? load;

  const AllowedLinksTab({super.key, this.load});

  @override
  State<AllowedLinksTab> createState() => _AllowedLinksTabState();
}

class _AllowedLinksTabState extends State<AllowedLinksTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<AllowedDomain>> _future = _fetch();
  List<AllowedDomain> _last = const [];

  @override
  bool get wantKeepAlive => true;

  Future<List<AllowedDomain>> _fetch() async {
    final list = await (widget.load ?? AllowedLinks.fetchAll)();
    _last = list;
    return list;
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _add() async {
    final added = await showDialog<String>(
      context: context,
      builder: (_) => AddAllowedDomainDialog(
          existing: {for (final d in _last) d.domain}),
    );
    if (added == null || !mounted) return;
    showModSnack(context, context.l10nRead.slAdded(added));
    _reload();
  }

  Future<void> _remove(AllowedDomain d) async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.slRemoveTitle(d.domain)),
        content: Text(s.slRemoveBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            key: const ValueKey('allowed-remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(s.slRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AllowedLinks.remove(d.domain);
      if (!mounted) return;
      showModSnack(context, s.slRemoved(d.domain));
      _reload();
    } catch (e) {
      if (!mounted) return;
      showModSnack(context, modErrorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.l10n;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // Phone: full width. Desktop: a readable column.
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.slIntro,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: KSpace.s),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('allowed-add'),
                      onPressed: _add,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.slAdd),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AdminAsyncList<AllowedDomain>(
                future: _future,
                onRetry: _reload,
                empty: ModEmptyState(icon: AppIcons.link, title: s.slEmpty),
                itemBuilder: (context, d) => ListTile(
                  dense: true,
                  leading: Icon(AppIcons.link,
                      size: 18, color: theme.colorScheme.primary),
                  title: Text(d.domain),
                  subtitle: (d.note?.isNotEmpty ?? false)
                      ? Text(d.note!, style: theme.textTheme.bodySmall)
                      : null,
                  trailing: IconButton(
                    key: ValueKey('allowed-remove-${d.domain}'),
                    tooltip: s.slRemove,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _remove(d),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a domain (or a pasted link, cleaned to its host) and a note;
/// pops with the domain once it's saved.
class AddAllowedDomainDialog extends StatefulWidget {
  /// Already listed (refused as duplicates before saving).
  final Set<String> existing;

  /// Tests: saving without a database.
  final Future<void> Function(String domain, String? note)? save;

  const AddAllowedDomainDialog({super.key, required this.existing, this.save});

  @override
  State<AddAllowedDomainDialog> createState() => _AddAllowedDomainDialogState();
}

class _AddAllowedDomainDialogState extends State<AddAllowedDomainDialog> {
  final _domain = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _domain.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _domain.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Error text for [raw], or null when it can be added.
  static String? check(AppStrings s, String raw, Set<String> existing) {
    final d = normalizeDomainInput(raw);
    if (d == null) return s.slInvalid;
    if (existing.contains(d)) return s.slDuplicate(d);
    return null;
  }

  Future<void> _submit() async {
    final s = context.l10nRead;
    final err = check(s, _domain.text, widget.existing);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final d = normalizeDomainInput(_domain.text)!;
    setState(() => _saving = true);
    try {
      await (widget.save ?? (d, n) => AllowedLinks.add(d, note: n))(d, _note.text);
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (!mounted) return;
      // A unique-key clash means someone else just added it.
      final dup = '$e'.contains('23505') || '$e'.contains('duplicate');
      setState(() {
        _saving = false;
        _error = dup ? s.slDuplicate(d) : modErrorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final cleaned = normalizeDomainInput(_domain.text);
    final showCleaned = cleaned != null && cleaned != _domain.text.trim();
    return AlertDialog(
      title: Text(s.slAdd),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('allowed-domain-field'),
              controller: _domain,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: s.slFieldLabel,
                hintText: s.slFieldHint,
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            if (showCleaned && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: KSpace.xs),
                child: Text(s.slWillAdd(cleaned),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ),
            const SizedBox(height: KSpace.s),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: InputDecoration(labelText: s.slNoteLabel),
              onSubmitted: (_) => _saving ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(s.cancel)),
        FilledButton(
          key: const ValueKey('allowed-save'),
          onPressed: _saving ? null : _submit,
          child: Text(s.slAdd),
        ),
      ],
    );
  }
}
