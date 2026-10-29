import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/form_strings.dart';
import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../services/form_service.dart';
import '../../services/my_forms_service.dart';
import '../../utils/adaptive.dart';
import '../../utils/app_nav.dart';
import '../../utils/csv_saver.dart';
import '../../utils/feedback.dart';
import '../../utils/form_rules.dart';
import '../../utils/text_file_picker.dart';
import '../../utils/text_rules.dart';
import '../../widgets/brand/brand.dart';

/// The template gallery (`/forms/new`): where every new form starts.
///
/// Laid out the way template galleries usually are — search on top, categories
/// to narrow the grid, and a grid of same-sized cards whose picture is a
/// sketch of the form itself, so a template is recognised before its name is
/// read. "Blank form" and "Import CSV" come first: they are the two ways to
/// start without a template.
///
/// Phones: categories are a chip row and the grid is two columns. From 900 px
/// the categories move to a rail on the left and the grid takes as many
/// columns as fit at a ~220 px minimum card width.
class FormGalleryScreen extends StatefulWidget {
  const FormGalleryScreen({super.key});

  @override
  State<FormGalleryScreen> createState() => _FormGalleryScreenState();
}

const _categories = ['events', 'signups', 'feedback', 'orders', 'campus', 'academic'];

IconData _categoryIcon(String? c) => switch (c) {
  'events' => AppIcons.events,
  'signups' => AppIcons.people,
  'feedback' => AppIcons.comment,
  'orders' => AppIcons.bag,
  'campus' => AppIcons.location,
  'academic' => AppIcons.compose,
  _ => AppIcons.grid,
};

/// A category's colour, adjusted for the theme (the same palette that tints
/// profile banners, so it holds up in dark mode).
Color _categoryColor(BuildContext context, String category) =>
    KPalette.onTheme(KPalette.forKey('form-$category'), Theme.of(context).brightness);

class _FormGalleryScreenState extends State<FormGalleryScreen> {
  final _search = TextEditingController();
  late Future<List<GalleryTemplate>> _templates = MyFormsService.instance.gallery();
  String? _category;
  List<PostAsOption> _owners = const [];
  PostAsOption? _owner;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOwners());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadOwners() async {
    final s = context.l10nRead;
    final options = await ClubService.postAsOptions(
      s.formsOwnerSelf,
    ).catchError((Object _) => <PostAsOption>[]);
    if (mounted) setState(() => _owners = options);
  }

  bool get _malay => identical(context.l10nRead, AppStrings.ms);

  // ------------------------------------------------------------------ create

  /// Makes the form, fills it ([fields] for an import), and swaps this page for
  /// its editor so back goes to wherever the gallery was opened from.
  Future<void> _create({String? slug, String? title, List<FormFieldSpec>? fields}) async {
    if (_busy) return;
    final router = GoRouter.of(context);
    final s = context.l10nRead;
    setState(() => _busy = true);
    try {
      final id = await MyFormsService.instance.create(
        title: title,
        clubId: _owner?.clubId,
        templateSlug: slug,
        lang: _malay ? 'ms' : 'en',
      );
      if (fields != null && fields.isNotEmpty) {
        final view = await FormService.instance.load(id);
        await FormService.instance.save(view.doc.copyWith(fields: fields));
      }
      if (!mounted) return;
      setState(() => _busy = false);
      router.pushReplacement('/f/$id/edit');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorWithRetry(context, e, message: s.formServerError(formErrorCode(e)));
    }
  }

  /// Dialog on wide screens, a tall bottom sheet on phones.
  Future<void> _preview(GalleryTemplate t) async {
    final height = MediaQuery.sizeOf(context).height;
    final preview = _TemplatePreview(template: t, malay: _malay);
    final Future<bool?> shown;
    if (isWide(context)) {
      shown = showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: height * 0.85),
            child: preview,
          ),
        ),
      );
    } else {
      shown = showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.88),
          child: preview,
        ),
      );
    }
    if (await shown == true) await _create(slug: t.slug);
  }

  Future<void> _importCsv() async {
    final result = await showDialog<(String, List<FormFieldSpec>)>(
      context: context,
      builder: (_) => const _CsvImportDialog(),
    );
    if (result == null) return;
    await _create(title: result.$1.isEmpty ? null : result.$1, fields: result.$2);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: Responsive.maxContentWidth,
        leading: const AppBackButton(),
        title: Text(s.formsNew),
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _busy,
            child: FutureBuilder<List<GalleryTemplate>>(
              future: _templates,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _Center(
                    icon: AppIcons.error,
                    text: s.galleryLoadFailed,
                    action: TextButton(
                      onPressed: () =>
                          setState(() => _templates = MyFormsService.instance.gallery()),
                      child: Text(s.retry),
                    ),
                  );
                }
                final all = snap.data;
                if (all == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= Responsive.desktopBreakpoint
                      ? _wide(context, all)
                      : _narrow(context, all),
                );
              },
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 3),
        ],
      ),
    );
  }

  List<GalleryTemplate> _visible(List<GalleryTemplate> all) => [
    for (final t in all)
      if ((_category == null || t.category == _category) && t.matches(_search.text)) t,
  ];

  Widget _narrow(BuildContext context, List<GalleryTemplate> all) {
    final s = context.l10n;
    final shown = _visible(all);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(KSpace.gutter, KSpace.m, KSpace.gutter, 0),
          sliver: SliverList.list(
            children: [
              _SearchField(controller: _search),
              if (_owners.length > 1) ...[
                const SizedBox(height: KSpace.s),
                _OwnerPicker(
                  options: _owners,
                  value: _owner,
                  onChanged: (o) => setState(() => _owner = o),
                ),
              ],
              const SizedBox(height: KSpace.l),
              _SectionTitle(s.galleryStartTitle),
              const SizedBox(height: KSpace.s),
              Row(
                children: [
                  Expanded(
                    child: _StartCard(
                      key: const ValueKey('start-blank'),
                      icon: AppIcons.create,
                      title: s.formStartBlank,
                      subtitle: s.formStartBlankSub,
                      onTap: () => _create(),
                    ),
                  ),
                  const SizedBox(width: KSpace.m),
                  Expanded(
                    child: _StartCard(
                      key: const ValueKey('start-csv'),
                      icon: AppIcons.upload,
                      title: s.galleryCsv,
                      subtitle: s.galleryCsvSub,
                      onTap: _importCsv,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KSpace.l),
              _SectionTitle(s.galleryTemplates),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter, vertical: KSpace.s),
              child: Row(
                children: [
                  for (final c in [null, ..._categories])
                    Padding(
                      padding: const EdgeInsets.only(right: KSpace.s),
                      child: ChoiceChip(
                        key: ValueKey('cat-${c ?? 'all'}'),
                        label: Text(c == null ? s.galleryCategory(null) : s.galleryCategory(c)),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ..._grid(context, shown, minTile: 150, padding: KSpace.gutter, describe: false),
      ],
    );
  }

  Widget _wide(BuildContext context, List<GalleryTemplate> all) {
    final s = context.l10n;
    final shown = _visible(all);
    final counts = <String?, int>{null: all.length};
    for (final t in all) {
      counts[t.category] = (counts[t.category] ?? 0) + 1;
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.maxContentWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: Responsive.sidebarWidth,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.s, KSpace.l),
                children: [
                  if (_owners.length > 1) ...[
                    _OwnerPicker(
                      options: _owners,
                      value: _owner,
                      onChanged: (o) => setState(() => _owner = o),
                    ),
                    const SizedBox(height: KSpace.l),
                  ],
                  for (final c in [null, ..._categories])
                    _RailItem(
                      key: ValueKey('cat-${c ?? 'all'}'),
                      icon: _categoryIcon(c),
                      color: c == null ? null : _categoryColor(context, c),
                      label: s.galleryCategory(c),
                      count: counts[c] ?? 0,
                      selected: _category == c,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(KSpace.xl, KSpace.l, KSpace.xl, 0),
                    sliver: SliverList.list(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: _SearchField(controller: _search),
                        ),
                        const SizedBox(height: KSpace.xl),
                        _SectionTitle(s.galleryStartTitle),
                        const SizedBox(height: KSpace.s),
                        Wrap(
                          spacing: KSpace.m,
                          runSpacing: KSpace.m,
                          children: [
                            SizedBox(
                              width: 300,
                              child: _StartCard(
                                key: const ValueKey('start-blank'),
                                icon: AppIcons.create,
                                title: s.formStartBlank,
                                subtitle: s.formStartBlankSub,
                                onTap: () => _create(),
                              ),
                            ),
                            SizedBox(
                              width: 300,
                              child: _StartCard(
                                key: const ValueKey('start-csv'),
                                icon: AppIcons.upload,
                                title: s.galleryCsv,
                                subtitle: s.galleryCsvSub,
                                onTap: _importCsv,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: KSpace.xl),
                        _SectionTitle(s.galleryCategory(_category)),
                        const SizedBox(height: KSpace.m),
                      ],
                    ),
                  ),
                  ..._grid(context, shown, minTile: 220, padding: KSpace.xl, describe: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The card grid, or the no-match message. Columns come from a minimum
  /// card width; the card height follows its width so the sketch keeps its
  /// shape at every size.
  List<Widget> _grid(
    BuildContext context,
    List<GalleryTemplate> shown, {
    required double minTile,
    required double padding,
    required bool describe,
  }) {
    final s = context.l10n;
    if (shown.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(KSpace.xl),
            child: Column(
              children: [
                Text(s.galleryNoMatch(_search.text.trim()), textAlign: TextAlign.center),
                const SizedBox(height: KSpace.s),
                TextButton(
                  onPressed: () => setState(() {
                    _search.clear();
                    _category = null;
                  }),
                  child: Text(s.galleryClearSearch),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(padding, KSpace.s, padding, KSpace.xxl),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            const gap = KSpace.m;
            final width = constraints.crossAxisExtent;
            final cols = ((width + gap) / (minTile + gap)).floor().clamp(2, 5);
            final tile = (width - gap * (cols - 1)) / cols;
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final extent = tile * 0.62 + (describe ? 112 : 78) * textScale;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: extent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TemplateCard(
                  template: shown[i],
                  malay: _malay,
                  describe: describe,
                  onTap: () => _preview(shown[i]),
                ),
                childCount: shown.length,
              ),
            );
          },
        ),
      ),
    ];
  }
}

// --------------------------------------------------------------------- pieces

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  const _SearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return TextField(
      key: const ValueKey('gallery-search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: s.gallerySearchHint,
        prefixIcon: const Icon(AppIcons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: s.galleryClearSearch,
                icon: const Icon(AppIcons.close),
                onPressed: controller.clear,
              ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );
}

class _OwnerPicker extends StatelessWidget {
  final List<PostAsOption> options;
  final PostAsOption? value;
  final ValueChanged<PostAsOption?> onChanged;

  const _OwnerPicker({required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return DropdownButtonFormField<String?>(
      key: const ValueKey('gallery-owner'),
      initialValue: value?.clubId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: s.formsOwnerLabel,
        helperText: s.formsOwnerClubHelp,
        helperMaxLines: 3,
        prefixIcon: const Icon(AppIcons.people),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o.clubId,
            child: Text(o.isClub ? o.label : s.formsOwnerSelf, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (id) => onChanged(id == null ? null : options.firstWhere((o) => o.clubId == id)),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: KRadius.pill,
        child: InkWell(
          borderRadius: KRadius.pill,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.s + 2),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color ?? scheme.onSurfaceVariant),
                const SizedBox(width: KSpace.m),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _StartCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.card,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(KSpace.m),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One template: a sketch of the form on a tinted ground, its name, (on wide
/// screens) what it is for, and how many questions it asks. The whole card is
/// the button.
class _TemplateCard extends StatelessWidget {
  final GalleryTemplate template;
  final bool malay;
  final bool describe;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.malay,
    required this.describe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final accent = _categoryColor(context, template.category);
    return Material(
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: KRadius.card,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('tpl-${template.slug}'),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1 / 0.62,
              child: _FormSketch(template: template, malay: malay, accent: accent),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.m, KSpace.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.nameIn(malay),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                    ),
                    if (describe) ...[
                      const SizedBox(height: 2),
                      Text(
                        template.descriptionIn(malay),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Icon(_categoryIcon(template.category), size: 14, color: accent),
                        const SizedBox(width: KSpace.xs),
                        Expanded(
                          child: Text(
                            s.galleryQuestions(template.questionCount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the form: a sheet with the accent header strip and the
/// first questions drawn as the controls they will be (a line for text,
/// circles for a choice, dots for a rating).
class _FormSketch extends StatelessWidget {
  final GalleryTemplate template;
  final bool malay;
  final Color accent;

  const _FormSketch({required this.template, required this.malay, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final questions = template.questions.where((q) => q.kind != 'heading').take(3).toList();
    final ink = scheme.onSurfaceVariant.withValues(alpha: 0.45);
    return ColoredBox(
      color: Color.alphaBlend(accent.withValues(alpha: 0.16), scheme.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.m, KSpace.m, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(height: 5, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(KSpace.s, KSpace.xs + 2, KSpace.s, 0),
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final q in questions) ...[
                            Text(
                              q.labelIn(malay),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 8.5, height: 1.2, color: scheme.onSurface),
                            ),
                            const SizedBox(height: 2),
                            _control(q, ink),
                            const SizedBox(height: 5),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _control(TemplateQuestion q, Color ink) {
    Widget dot({bool square = false}) => Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        border: Border.all(color: ink, width: 1),
      ),
    );
    Widget bar(double w) => Container(
      width: w,
      height: 3,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2)),
    );
    switch (q.kind) {
      case 'single_choice':
      case 'multi_choice':
        return Row(
          children: [
            for (var i = 0; i < 2; i++) ...[dot(square: q.kind == 'multi_choice'), bar(18)],
          ],
        );
      case 'rating':
        return Row(children: [for (var i = 0; i < 5; i++) dot()]);
      case 'consent':
        return Row(children: [dot(square: true), bar(30)]);
      case 'long_text':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [bar(60), const SizedBox(height: 2), bar(40)],
        );
      default:
        return Container(height: 1, width: 64, color: ink);
    }
  }
}

/// The preview a card opens: every question with its type, then "Use this
/// template". Returns true to use it.
class _TemplatePreview extends StatelessWidget {
  final GalleryTemplate template;
  final bool malay;

  const _TemplatePreview({required this.template, required this.malay});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final accent = _categoryColor(context, template.category);
    var n = 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, KSpace.m),
            children: [
              Row(
                children: [
                  Icon(_categoryIcon(template.category), size: 16, color: accent),
                  const SizedBox(width: KSpace.xs),
                  Text(
                    s.galleryCategory(template.category),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: accent),
                  ),
                ],
              ),
              const SizedBox(height: KSpace.xs),
              Text(
                template.nameIn(malay),
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: KSpace.xs),
              Text(
                template.descriptionIn(malay),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: KSpace.l),
              for (final q in template.questions)
                if (q.kind == 'heading')
                  Padding(
                    padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xs),
                    child: Text(
                      q.labelIn(malay),
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  _QuestionRow(number: ++n, question: q, malay: malay),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.all(KSpace.m),
          child: SafeArea(
            top: false,
            // Phones: one full-width button (the sheet closes by dragging).
            // Wider: the count, Cancel and Use on one line.
            child: LayoutBuilder(
              builder: (context, c) {
                final use = FilledButton(
                  key: const ValueKey('use-template'),
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: Text(s.galleryUse, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
                if (c.maxWidth < 480) return use;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.galleryQuestions(template.questionCount),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(s.cancel),
                    ),
                    const SizedBox(width: KSpace.s),
                    use,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionRow extends StatelessWidget {
  final int number;
  final TemplateQuestion question;
  final bool malay;

  const _QuestionRow({required this.number, required this.question, required this.malay});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final choices = question.choicesIn(malay);
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$number.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.labelIn(malay) + (question.required ? ' *' : ''),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    s.galleryKind(question.kind),
                    if (choices.isNotEmpty)
                      choices.take(4).join(' · ') + (choices.length > 4 ? ' …' : ''),
                  ].join(' — '),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Center extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Center({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(KSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: KSpace.m),
          Text(text, textAlign: TextAlign.center),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ CSV import

/// Paste a question list or open a .csv file; the questions are checked as
/// they arrive, and "Create form" is only offered once every line reads.
/// Returns (title, questions).
class _CsvImportDialog extends StatefulWidget {
  const _CsvImportDialog();

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  FieldPaste? _parsed;

  @override
  void initState() {
    super.initState();
    _text.addListener(
      () => setState(() {
        _parsed = _text.text.trim().isEmpty ? null : parseQuestionCsv(_text.text);
      }),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await pickTextFile();
    if (text != null && mounted) _text.text = text;
  }

  String? _status(BuildContext context) {
    final s = context.l10n;
    final p = _parsed;
    if (p == null) return null;
    if (p.problemLines.isNotEmpty) {
      return s.csvProblems(p.problemLines.join(', '));
    }
    if (p.problems.isNotEmpty) {
      final first = p.problems.first;
      return '${first.index + 1}. ${s.formIssueText(first.code)}';
    }
    if (p.fields.isEmpty) return s.formPasteEmpty;
    return s.csvReady(p.fields.length);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final p = _parsed;
    final ok = p != null && p.ok;
    final status = _status(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      key: const ValueKey('csv-dialog'),
      insetPadding: narrow
          ? const EdgeInsets.symmetric(horizontal: KSpace.gutter, vertical: KSpace.xl)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(KSpace.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.csvTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: KSpace.s),
              Text(
                s.csvHelp,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: KSpace.m),
              TextField(
                key: const ValueKey('csv-title'),
                controller: _title,
                maxLength: kFormTitleMax,
                decoration: InputDecoration(labelText: s.formsTitleLabel),
              ),
              TextField(
                key: const ValueKey('csv-text'),
                controller: _text,
                minLines: 6,
                maxLines: 12,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  hintText: s.csvHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: KSpace.s),
              Wrap(
                spacing: KSpace.s,
                children: [
                  if (canPickTextFile)
                    TextButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(AppIcons.upload, size: 18),
                      label: Text(s.csvChooseFile),
                    ),
                  TextButton.icon(
                    onPressed: () => saveCsv(kSampleQuestionCsv, 'form-questions-sample.csv'),
                    icon: const Icon(AppIcons.download, size: 18),
                    label: Text(s.csvSample),
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: KSpace.s),
                Row(
                  children: [
                    Icon(
                      ok ? AppIcons.success : AppIcons.warning,
                      size: 18,
                      color: ok ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(width: KSpace.s),
                    Expanded(
                      child: Text(
                        status,
                        key: const ValueKey('csv-status'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: KSpace.l),
              // Side by side when they fit, stacked when they don't.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: KSpace.s,
                overflowSpacing: KSpace.s,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
                  FilledButton(
                    key: const ValueKey('csv-create'),
                    onPressed: ok
                        ? () => Navigator.pop(context, (cleanLine(_title.text), p.fields))
                        : null,
                    child: Text(s.csvCreate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
