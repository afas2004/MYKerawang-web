import 'package:flutter/material.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/category_service.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';

/// Admin editor for `content_categories`.
///
/// Categories are data, not code: an admin can add a topic, rename it,
/// reorder it, or hide it. Deleting is refused while content still uses
/// the slug — hiding is the safe operation.
class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab>
    with AutomaticKeepAliveClientMixin {
  String _kind = 'event';
  late Future<List<ContentCategory>> _future = CategoryService.allForAdmin(_kind);

  @override
  bool get wantKeepAlive => true;

  void _reload() =>
      setState(() => _future = CategoryService.allForAdmin(_kind));

  Future<void> _edit([ContentCategory? cat]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(kind: _kind, category: cat),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(ContentCategory cat) async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.catEdit),
        content: Text(cat.nameEn),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CategoryService.delete(cat.id, _kind);
      if (!mounted) return;
      showModSnack(context, s.catDeleted);
      _reload();
    } catch (e) {
      if (!mounted) return;
      final err = parseCategoryError(e);
      showModSnack(context, err == 'in_use' ? s.catInUse : modErrorText(context, e),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.l10n;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.s, KSpace.l, 0),
          child: Row(
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'event', label: Text(s.catEvents)),
                  ButtonSegment(value: 'listing', label: Text(s.catListings)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) {
                  setState(() => _kind = v.first);
                  _reload();
                },
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.catAdd),
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminAsyncList<ContentCategory>(
            future: _future,
            onRetry: _reload,
            empty: ModEmptyState(icon: ModIcons.inbox, title: s.catTitle),
            itemBuilder: (context, c) => ListTile(
              dense: true,
              title: Text(c.nameEn),
              subtitle: Text(
                '${c.nameMs ?? ''}${(c.nameMs?.isEmpty ?? true) ? '' : ' · '}${c.slug}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!c.active)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(s.catInactive,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  IconButton(
                    tooltip: s.catEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _edit(c),
                  ),
                  IconButton(
                    tooltip: s.delete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _delete(c),
                  ),
                ],
              ),
              onTap: () => _edit(c),
            ),
          ),
        ),
      ],
    );
  }
}

/// Map the RPC's CAT: codes to a short token the tab can branch on.
String? parseCategoryError(Object e) {
  final m = RegExp(r'CAT:([a-z_]+)').firstMatch('$e');
  return m?.group(1);
}

class _CategoryDialog extends StatefulWidget {
  final String kind;
  final ContentCategory? category;

  const _CategoryDialog({required this.kind, this.category});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _nameEn = TextEditingController(text: widget.category?.nameEn ?? '');
  late final _nameMs = TextEditingController(text: widget.category?.nameMs ?? '');
  late final _slug = TextEditingController(text: widget.category?.slug ?? '');
  late bool _active = widget.category?.active ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameMs.dispose();
    _slug.dispose();
    super.dispose();
  }

  String _slugify(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .replaceAll(RegExp(r'-{2,}'), '-');

  Future<void> _save() async {
    final s = context.l10nRead;
    final slug = _slug.text.trim().isEmpty ? _slugify(_nameEn.text) : _slug.text.trim();
    if (_nameEn.text.trim().length < 2 || slug.isEmpty) {
      setState(() => _error = s.catLastOne);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await CategoryService.save(
        id: widget.category?.id,
        kind: widget.kind,
        slug: slug,
        nameEn: _nameEn.text.trim(),
        nameMs: _nameMs.text.trim().isEmpty ? null : _nameMs.text.trim(),
        sort: widget.category?.sort ?? 999,
        active: _active,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = parseCategoryError(e) == 'slug_in_use'
            ? s.catInUse
            : modErrorText(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return AlertDialog(
      title: Text(widget.category == null ? s.catAdd : s.catEdit),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameEn,
              decoration: InputDecoration(
                  labelText: s.catNameEn,
                  errorText: _error != null && _nameEn.text.trim().length < 2 ? _error : null),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _nameMs,
              decoration: InputDecoration(labelText: s.catNameMs),
            ),
            TextField(
              controller: _slug,
              decoration: InputDecoration(
                  labelText: s.catSlug, hintText: s.catSlugHint),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(s.catActive),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(s.cancel)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s.save),
        ),
      ],
    );
  }
}
