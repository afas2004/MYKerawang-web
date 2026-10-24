import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../services/category_service.dart';
import '../utils/categories.dart';

/// Multi-select chips over `content_categories`.
///
/// Order is the user's tap order, which matters for listings: the first
/// slug becomes the primary category (`listings.category`).
class CategoryPicker extends StatefulWidget {
  final String kind;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final int max;

  const CategoryPicker({
    super.key,
    required this.kind,
    required this.value,
    required this.onChanged,
    this.max = kMaxCategoriesPerItem,
  });

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  late final Future<List<ContentCategory>> _future =
      CategoryService.forKind(widget.kind);

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return FutureBuilder<List<ContentCategory>>(
      future: _future,
      builder: (context, snap) {
        // Cached/seeded rows render immediately; the fetch only adds
        // admin-created ones.
        final cats = snap.data ?? CategoryService.cached(widget.kind);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats)
              FilterChip(
                label: Text(c.label(s)),
                selected: widget.value.contains(c.slug),
                onSelected: (on) {
                  final next = [...widget.value];
                  if (on) {
                    if (next.length >= widget.max) return;
                    next.add(c.slug);
                  } else {
                    next.remove(c.slug);
                  }
                  widget.onChanged(next);
                },
              ),
          ],
        );
      },
    );
  }
}
