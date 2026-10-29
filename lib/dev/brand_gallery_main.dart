// A standalone page of every brand piece with sample data, for checking the
// identity at every screen size and theme without signing in. Not part of
// the app: build it on its own.
//
//   flutter build web -t lib/dev/brand_gallery_main.dart -o build/gallery
//
// The app's real screens use the same widgets.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../language_cubit.dart';
import '../screens/clubs/club_directory_screen.dart' show ClubCard;
import '../screens/clubs/club_widgets.dart';
import '../screens/events_screen.dart' show EventCard;
import '../screens/marketplace_screen.dart' show MarketCard, PriceTag;
import '../services/club_service.dart';
import '../theme/app_themes.dart';
import '../widgets/brand/brand.dart';
import '../widgets/error_state.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/universal_card.dart';

void main() => runApp(const BrandGallery());

class BrandGallery extends StatefulWidget {
  const BrandGallery({super.key});

  @override
  State<BrandGallery> createState() => _BrandGalleryState();
}

class _BrandGalleryState extends State<BrandGallery> {
  AppTheme _theme = AppTheme.kampus;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MYKerawang brand gallery',
        theme: buildAppTheme(_theme),
        builder: (context, child) => KGround(child: child!),
        home: _Page(theme: _theme, onTheme: (t) => setState(() => _theme = t)),
      ),
    );
  }
}

const _clubs = [
  Club(id: '1', handle: 'kebudayaan', name: 'Kelab Kebudayaan', category: 'arts', isVerified: true),
  Club(id: '2', handle: 'robotik', name: 'Kelab Robotik', category: 'tech'),
  Club(id: '3', handle: 'persatuan-silat', name: 'Persatuan Silat', category: 'sports'),
  Club(id: '4', handle: 'debat-uitm', name: 'Kelab Debat', category: 'academic'),
  Club(id: '5', handle: 'usahawan', name: 'Kelab Keusahawanan', category: 'business'),
  Club(id: '6', handle: 'sukarelawan', name: 'Sukarelawan Siswa', category: 'volunteer'),
  Club(id: '7', handle: 'lensa', name: 'Kelab Fotografi Lensa Kampus Yang Namanya Panjang', category: 'other'),
];

class _Page extends StatefulWidget {
  final AppTheme theme;
  final ValueChanged<AppTheme> onTheme;
  const _Page({required this.theme, required this.onTheme});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  bool _saved = false;
  bool _following = false;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    Map<String, dynamic> event(int days, String title, {bool cancelled = false}) => {
          'id': 'e$days',
          'title': title,
          'start_datetime': now.add(Duration(days: days, hours: 2)).toIso8601String(),
          'end_datetime': now.add(Duration(days: days, hours: 4)).toIso8601String(),
          'location': 'Dewan Seri Budiman, UiTM Shah Alam',
          if (cancelled) 'status': 'cancelled',
        };

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xl, KSpace.l, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: KSpace.m),
              ...children,
            ],
          ),
        );

    Widget grid(double minTile, List<Widget> tiles, {double? height, double Function(double width)? heightFor}) =>
        LayoutBuilder(builder: (context, box) {
          final cols = (box.maxWidth / minTile).floor().clamp(1, 6);
          final w = (box.maxWidth - (cols - 1) * KSpace.m) / cols;
          return Wrap(
            spacing: KSpace.m,
            runSpacing: KSpace.m,
            children: [
              for (final t in tiles) SizedBox(width: w, height: heightFor?.call(w) ?? height, child: t),
            ],
          );
        });

    return Scaffold(
      appBar: AppBar(
        title: const Text('MYKerawang brand gallery'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: KSpace.s),
            child: SegmentedButton<AppTheme>(
              segments: [
                for (final t in AppTheme.values)
                  ButtonSegment(value: t, label: Text(kThemeSpecs[t]!.displayName)),
              ],
              selected: {widget.theme},
              onSelectionChanged: (s) => widget.onTheme(s.first),
            ),
          ),
        ),
      ),
      body: LinearRefresher(
        onRefresh: () => Future.delayed(const Duration(seconds: 2)),
        child: ListView(
          children: [
            section('Header bands (kepala kain)', [
              for (final (name, tone) in [('Home', KBand.home), ('News', KBand.news), ('Market', KBand.market), ('Events', KBand.events)]) ...[
                SizedBox(
                  height: kToolbarHeight + KBand.footRadius,
                  child: KBand.appBar(context, tone: tone, title: Text(name), actions: [
                    IconButton(onPressed: () {}, icon: const Icon(AppIcons.search)),
                    IconButton(onPressed: () {}, icon: const Icon(AppIcons.notifications)),
                  ]),
                ),
                const SizedBox(height: KSpace.m),
              ],
            ]),
            section('Plain cards with author rings, photo-less items', [
              for (final (who, seed) in [('Amir Hakim', 'u-amir'), ('Nur Aisyah', 'u-aisyah'), ('Anonymous', '')]) ...[
                KCard(
                  onTap: () {},
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            width: 1.5,
                            color: seed.isEmpty
                                ? theme.colorScheme.outlineVariant
                                : KPalette.onTheme(KPalette.forKey(seed), theme.brightness)),
                      ),
                      child: const CircleAvatar(radius: 16),
                    ),
                    const SizedBox(width: KSpace.m),
                    Expanded(child: Text('$who: Ada sesiapa nak join study group Kalkulus malam ni?')),
                  ]),
                ),
                const SizedBox(height: KSpace.m),
              ],
              SizedBox(
                height: 196,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final d in [
                    {'id': 'e1', 'title': 'Malam Apresiasi KMI 2026', 'start_datetime': now.add(const Duration(days: 16)).toIso8601String()},
                    {'id': 'e2', 'title': 'Bengkel Pengurusan Kewangan', 'start_datetime': now.add(const Duration(days: 23)).toIso8601String()},
                    {'id': 'l1', 'title': 'Kipas meja (macam baru)', 'price': 35},
                    {'id': 'l2', 'title': 'Baju kurung labuh, saiz M', 'price': 45},
                  ])
                    Container(width: 220, margin: const EdgeInsets.only(right: KSpace.m, bottom: KSpace.s), child: UniversalCard(data: d, onTap: () {})),
                ]),
              ),
            ]),
            section('Hidden pages and empty states', [
              grid(300, [
                for (final i in AppIllo.values)
                  BrandEmptyState(
                    illo: i,
                    title: i.name,
                    message: 'Sample message for the ${i.name} state.',
                    actionLabel: 'Action',
                    onAction: () {},
                  ),
              ], height: 400),
              const SizedBox(height: KSpace.m),
              grid(300, [
                ErrorState(onRetry: () {}),
                ErrorState(onRetry: () {}, plain: true),
              ], height: 420),
              const SizedBox(height: KSpace.m),
              SizedBox(height: 180, child: ErrorState(onRetry: () {})),
            ]),
            section('Club covers and directory', [
              for (final c in _clubs.take(3)) ...[
                SizedBox(
                  height: 180,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      height: 140,
                      decoration: BoxDecoration(color: clubColor(c), borderRadius: KRadius.card),
                      clipBehavior: Clip.antiAlias,
                      child: ClubCover(club: c),
                    ),
                    Positioned(
                      left: KSpace.l,
                      bottom: 0,
                      child: ClubLogo(url: null, name: c.name, size: 64, color: clubColor(c)),
                    ),
                  ]),
                ),
                const SizedBox(height: KSpace.m),
              ],
              grid(280, [
                for (final c in _clubs) ClubCard(club: c, followers: 128, onTap: () {}),
              ], height: 132),
            ]),
            section('Profile banners', [
              for (final seed in ['u-aisyah', 'u-haziq', 'u-siti'])
                Padding(
                  padding: const EdgeInsets.only(bottom: KSpace.m),
                  child: ClipRRect(
                    borderRadius: KRadius.card,
                    child: SizedBox(height: 88, child: BrandCover(seed: seed, color: KPalette.forKey(seed))),
                  ),
                ),
            ]),
            section('Cards', [
              KCard(
                official: true,
                officialLabel: 'Pinned · Hal Ehwal Pelajar',
                onTap: () {},
                child: const Text('Pendaftaran kursus Sem Mac 2027 dibuka 2 Nov. Semak jadual di portal sebelum 9 Nov.'),
              ),
              const SizedBox(height: KSpace.m),
              KCard(onTap: () {}, child: const Text('A normal post: hairline, 16 px corners, nothing else.')),
              const SizedBox(height: KSpace.m),
              grid(340, [
                EventCard(event: event(3, 'Malam Kebudayaan 2026'), goingCount: 86, onTap: () {}),
                EventCard(event: event(9, 'Bengkel Arduino untuk pelajar tahun satu dan dua, sesi petang'), onTap: () {}),
                EventCard(event: event(-2, 'Larian Amal'), onTap: () {}),
              ]),
              const SizedBox(height: KSpace.m),
              grid(170, [
                for (final p in [4.5, 1250, 35, 0.5])
                  MarketCard(item: {'title': 'Nasi lemak bungkus, sambal sotong pedas', 'price': p, 'image_url': ''}, onTap: () {}),
                MarketCard(item: const {'title': 'Kalkulator saintifik', 'price': 45, 'status': 'sold', 'image_url': ''}, onTap: () {}),
              ], heightFor: (w) => MarketCard.heightFor(w, MediaQuery.textScalerOf(context))),
              const SizedBox(height: KSpace.m),
              const Wrap(spacing: KSpace.s, children: [PriceTag('RM 4.50'), PriceTag('RM 1,250.00'), PriceTag('RM 45', sold: true)]),
            ]),
            section('Buttons and motion', [
              Wrap(spacing: KSpace.s, runSpacing: KSpace.s, children: [
                FilledButton(onPressed: () {}, child: const Text('Ikut')),
                FilledButton(style: accentButtonStyle(context), onPressed: () {}, child: const Text('Sertai acara')),
                FilledButton.tonal(onPressed: () {}, child: const Text('Mengikut')),
                OutlinedButton(onPressed: () {}, child: const Text('Kongsi')),
                TextButton(onPressed: () {}, child: const Text('Lihat semua')),
                const FilledButton(onPressed: null, child: Text('Disabled')),
              ]),
              const SizedBox(height: KSpace.m),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: KSpace.m, runSpacing: KSpace.s, children: [
                IconButton(
                  tooltip: 'Save',
                  onPressed: () => setState(() => _saved = !_saved),
                  icon: KLikeBurst(
                    active: _saved,
                    child: Icon(_saved ? AppIcons.saved : AppIcons.save,
                        color: _saved ? theme.colorScheme.primary : null),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: KStampSwitcher(
                    child: _following
                        ? OutlinedButton.icon(
                            key: const ValueKey('on'),
                            onPressed: () => setState(() => _following = false),
                            icon: const Icon(AppIcons.following, size: 18),
                            label: const Text('Mengikut'))
                        : FilledButton.icon(
                            key: const ValueKey('off'),
                            onPressed: () => setState(() => _following = true),
                            icon: const Icon(AppIcons.follow, size: 18),
                            label: const Text('Ikut')),
                  ),
                ),
                TextButton(onPressed: () => setState(() => _replay++), child: const Text('Replay entrance')),
              ]),
              const SizedBox(height: KSpace.m),
              Column(
                key: ValueKey(_replay),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 4; i++)
                    KEntrance(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: KSpace.s),
                        child: KCard(child: Text('Card ${i + 1} fades up in turn')),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: KSpace.m),
              const SongketHem(height: 10),
              const SizedBox(height: KSpace.m),
              SizedBox(height: 160, child: KPattern(kind: KPatternKind.star8, color: theme.colorScheme.primary.withValues(alpha: 0.14))),
              const SizedBox(height: KSpace.xxl * 2),
            ]),
          ],
        ),
      ),
    );
  }
}
