import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../l10n/licenses_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../widgets/brand/brand.dart';

/// Settings → Open-source credits.
///
/// Flutter's own `showLicensePage` lists every package alphabetically with
/// its raw licence text, no search and no explanation — which buries the few
/// credits that legally have to be visible (the CC BY 4.0 artwork registered
/// in services/art_credits.dart) among a hundred-odd packages.
///
/// This page answers "what am I looking at": a sentence of plain language,
/// the attribution-required artwork and fonts first, then the packages
/// grouped by licence so the bulk can be skimmed or skipped, and a filter
/// over both.

/// One credited thing: a package, a font or an artwork.
class _Credit {
  final String name;

  /// Licence family ("MIT", "Apache 2.0", …), used to group and label.
  final String family;

  /// Full licence text, as the registry supplied it.
  final String text;

  const _Credit(this.name, this.family, this.text);
}

class _Credits {
  /// Artwork and fonts: shown first, because their licences ask for credit.
  final List<_Credit> art;

  /// Packages by licence family, biggest family first.
  final Map<String, List<_Credit>> libraries;

  final int libraryCount;

  const _Credits(this.art, this.libraries, this.libraryCount);
}

/// pub package names are lowercase with underscores. Everything else in the
/// registry was added by hand (see `registerArtCredits`) and has a readable
/// name, which is how the two lists are told apart without a second source.
final _pubName = RegExp(r'^[a-z0-9_]+$');

/// Best-effort licence family from the text itself — the registry does not
/// say which licence an entry is. Order matters: the broad phrases last.
String _familyOf(String text) {
  final t = text.toLowerCase();
  if (t.contains('apache license')) return 'Apache 2.0';
  if (t.contains('mozilla public license')) return 'MPL 2.0';
  if (t.contains('creative commons') || t.contains('cc by')) return 'Creative Commons';
  if (t.contains('open font license')) return 'Open Font License';
  if (t.contains('redistribution and use in source and binary forms')) return 'BSD';
  if (t.contains('permission to use, copy, modify, and/or distribute')) return 'ISC';
  if (t.contains('mit license') ||
      t.contains('permission is hereby granted, free of charge')) {
    return 'MIT';
  }
  if (t.contains('zlib')) return 'zlib';
  return 'Other';
}

Future<_Credits> _loadCredits() async {
  // One name can appear in several entries, so collect texts per name.
  final texts = <String, List<String>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs
        .map((p) => p.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    for (final name in entry.packages) {
      (texts[name] ??= <String>[]).add(text);
    }
  }

  final art = <_Credit>[];
  final libs = <_Credit>[];
  texts.forEach((name, parts) {
    final text = parts.join('\n\n- - -\n\n');
    final credit = _Credit(name, _familyOf(text), text);
    (_pubName.hasMatch(name) ? libs : art).add(credit);
  });

  int byName(_Credit a, _Credit b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  art.sort(byName);
  libs.sort(byName);

  final grouped = <String, List<_Credit>>{};
  for (final c in libs) {
    (grouped[c.family] ??= <_Credit>[]).add(c);
  }
  // Biggest family first: it is the one a reader can most safely skip.
  final families = grouped.keys.toList()
    ..sort((a, b) {
      final size = grouped[b]!.length.compareTo(grouped[a]!.length);
      return size != 0 ? size : a.compareTo(b);
    });

  return _Credits(art, {for (final f in families) f: grouped[f]!}, libs.length);
}

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  late final Future<_Credits> _future = _loadCredits();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(_Credit c) =>
      _query.isEmpty || c.name.toLowerCase().contains(_query);

  void _open(_Credit credit) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LicenseDetail(credit: credit),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppBackButton(), title: Text(s.licTitle)),
      body: PageBody(
        child: FutureBuilder<_Credits>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(KSpace.l),
                  child: Text(s.licLoadFailed, textAlign: TextAlign.center),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snap.data!;
            final art = data.art.where(_matches).toList();
            final groups = <String, List<_Credit>>{
              for (final e in data.libraries.entries)
                if (e.value.any(_matches))
                  e.key: e.value.where(_matches).toList(),
            };

            return ListView(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, 96),
              children: [
                Text(
                  s.licIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: KSpace.l),
                TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: s.licFilterHint,
                    prefixIcon: const Icon(AppIcons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: s.clearSearch,
                            icon: const Icon(AppIcons.close),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: const OutlineInputBorder(borderRadius: KRadius.input),
                  ),
                ),
                const SizedBox(height: KSpace.l),

                if (art.isEmpty && groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: KSpace.xl),
                    child: BrandEmptyState(
                      icon: AppIcons.search,
                      title: s.licNoneTitle,
                      message: s.licNoneBody,
                      compact: true,
                    ),
                  )
                else ...[
                  if (art.isNotEmpty) ...[
                    SectionHeader(title: s.licArt, padding: EdgeInsets.zero),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: KSpace.s),
                      child: Text(s.licArtNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    for (final c in art)
                      _CreditTile(credit: c, onTap: () => _open(c)),
                    const SizedBox(height: KSpace.xl),
                  ],
                  SectionHeader(
                      title: '${s.licLibraries} · ${data.libraryCount}',
                      padding: EdgeInsets.zero),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: KSpace.s),
                    child: Text(s.licLibrariesNote,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  for (final e in groups.entries)
                    KCard(
                      padding: EdgeInsets.zero,
                      child: Theme(
                        // The default divider on an ExpansionTile fights the
                        // card's own border.
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          // Filtering is a deliberate search: show the hits.
                          initiallyExpanded: _query.isNotEmpty,
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: KSpace.l, vertical: KSpace.xs),
                          childrenPadding:
                              const EdgeInsets.only(bottom: KSpace.s),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(e.key,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          subtitle: Text(s.licItems(e.value.length),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          children: [
                            for (final c in e.value)
                              ListTile(
                                dense: true,
                                title: Text(c.name),
                                trailing: const Icon(AppIcons.chevronRight,
                                    size: 18),
                                onTap: () => _open(c),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A named credit (artwork, font) as its own card, since these are the ones
/// the page exists to make visible.
class _CreditTile extends StatelessWidget {
  final _Credit credit;
  final VoidCallback onTap;

  const _CreditTile({required this.credit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: KCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
            horizontal: KSpace.l, vertical: KSpace.m),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(credit.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(credit.family,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(AppIcons.chevronRight, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The full licence text for one credit.
class _LicenseDetail extends StatelessWidget {
  final _Credit credit;

  const _LicenseDetail({required this.credit});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppBackButton(), title: Text(credit.name)),
      body: PageBody(
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, 96),
            children: [
              Text(credit.family,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 2),
              Text(s.licFullText,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: KSpace.l),
              // Monospace: licence texts are hard-wrapped and read badly in
              // a proportional face.
              Text(
                credit.text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace', height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
