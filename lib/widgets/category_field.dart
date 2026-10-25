import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../services/category_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../utils/categories.dart';

/// Category entry as a **text field with suggestions** instead of a wall of
/// chips: type a few letters, pick from `content_categories`, and the chosen
/// ones show underneath as removable chips. Order is kept, because a listing's
/// first category is its primary one.
class CategoryField extends StatefulWidget {
  final String kind;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final String? hintText;
  final int max;

  const CategoryField({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.max = kMaxCategoriesPerItem,
  });

  @override
  State<CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends State<CategoryField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final Future<List<ContentCategory>> _future =
      CategoryService.forKind(widget.kind);

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _label(ContentCategory c, AppStrings s) => c.label(s);

  void _choose(ContentCategory c) {
    // RawAutocomplete writes the chosen label into the controller *after*
    // onSelected returns, so the field is cleared on the next frame.
    final take = !widget.value.contains(c.slug) && widget.value.length < widget.max;
    if (take) widget.onChanged([...widget.value, c.slug]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.clear();
      _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // `context.l10n` watches the language cubit, which is only legal during
    // build — the autocomplete calls its callbacks outside the tree, so the
    // strings are captured here and closed over instead.
    final s = context.l10n;
    return FutureBuilder<List<ContentCategory>>(
      future: _future,
      builder: (context, snap) {
        // The cache renders at once; the fetch only adds admin-created rows.
        final cats = snap.data ?? CategoryService.cached(widget.kind);
        return _field(context, s, cats);
      },
    );
  }

  Widget _field(BuildContext context, AppStrings s, List<ContentCategory> cats) {
    final scheme = Theme.of(context).colorScheme;
    String label(ContentCategory c) => _label(c, s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<ContentCategory>(
          textEditingController: _controller,
          focusNode: _focus,
          displayStringForOption: label,
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            final pool = cats.isEmpty ? <ContentCategory>[] : cats;
            if (query.isEmpty) {
              return pool.where((c) => !widget.value.contains(c.slug)).take(6);
            }
            return pool.where((c) {
              if (widget.value.contains(c.slug)) return false;
              return c.slug.toLowerCase().contains(query) ||
                  label(c).toLowerCase().contains(query);
            });
          },
          onSelected: _choose,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                hintText: widget.hintText ?? s.category,
                prefixIcon: Icon(AppIcons.search, size: 18, color: scheme.onSurfaceVariant),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: KRadius.input,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(label(list[i])),
                      onTap: () => onSelected(list[i]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.value.isNotEmpty) ...[
          const SizedBox(height: KSpace.s),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slug in widget.value)
                InputChip(
                  label: Text(CategoryService.labelOf(widget.kind, slug, s)),
                  onDeleted: () =>
                      widget.onChanged([...widget.value]..remove(slug)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
