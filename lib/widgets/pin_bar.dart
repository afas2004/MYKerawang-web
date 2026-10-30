import 'package:flutter/material.dart';

import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/event_live.dart';
import 'brand/brand.dart';
import 'pin_controls.dart';

/// Home's pins, in their own layer under the header: one row at a time,
/// swipe between them. The first tap expands a preview, the second opens
/// the post, and the chevron folds it back. Mandatory pins have no close
/// button.
const _fg = KBand.onBand;

class PinBar extends StatefulWidget {
  final List<Map<String, dynamic>> pins;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>> onDismiss;

  const PinBar({
    super.key,
    required this.pins,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  State<PinBar> createState() => _PinBarState();
}

class _PinBarState extends State<PinBar> {
  static const _rowHeight = 48.0;
  static const _previewHeight = 92.0;
  static const _manageHeight = 124.0;

  final _pages = PageController();
  int _page = 0;
  bool _expanded = false;
  bool _canManage = false;

  @override
  void initState() {
    super.initState();
    ModerationService.myRole().then((role) {
      final can = PinActions.canPin(const {}, role);
      if (mounted && can != _canManage) setState(() => _canManage = can);
    });
  }

  @override
  void didUpdateWidget(PinBar old) {
    super.didUpdateWidget(old);
    // A pin went away: stay on a page that still exists.
    if (_page >= widget.pins.length) {
      _page = widget.pins.isEmpty ? 0 : widget.pins.length - 1;
      _expanded = false;
      if (_pages.hasClients) _pages.jumpToPage(_page);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _tap(Map<String, dynamic> post) {
    if (_expanded) {
      widget.onOpen(post);
    } else {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    final count = widget.pins.length;
    final current = widget.pins[_page.clamp(0, count - 1)];
    final s = context.l10n;
    final radius = desktop
        ? KRadius.card
        : const BorderRadius.vertical(bottom: Radius.circular(KBand.footRadius));
    final height = _expanded
        ? (_canManage ? _manageHeight : _previewHeight)
        : _rowHeight;

    Widget control(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 18, color: _fg),
          onPressed: onPressed,
        );

    final row = AnimatedContainer(
      duration: KMotion.of(context).fast,
      height: height + KSpace.xs,
      padding: const EdgeInsets.only(left: KSpace.m, right: KSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: _rowHeight, child: Center(child: _PinBadge())),
          const SizedBox(width: KSpace.s + 2),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: (i) => setState(() {
                _page = i;
                _expanded = false;
              }),
              itemBuilder: (context, i) => _PinPage(
                post: widget.pins[i],
                expanded: _expanded,
                color: _fg,
                onTap: () => _tap(widget.pins[i]),
              ),
            ),
          ),
          SizedBox(
            height: _rowHeight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (count > 1)
                Padding(
                  padding: const EdgeInsets.only(left: KSpace.s),
                  child: Text('${_page + 1}/$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _fg,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              control(
                _expanded ? AppIcons.up : AppIcons.down,
                _expanded ? s.pinCollapse : s.pinExpand,
                () => setState(() => _expanded = !_expanded),
              ),
              if (current['pin_mandatory'] != true)
                control(AppIcons.close, s.pinClose,
                    () => widget.onDismiss(current)),
            ]),
          ),
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: desktop ? Responsive.feedMaxWidth : double.infinity),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                const Positioned.fill(child: _PinGround()),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The header's rounded foot, laid over the bar, so the
                    // header keeps its shape and the bar reads as its own
                    // layer tucked beneath it.
                    if (!desktop)
                      Container(
                        height: KBand.footRadius,
                        decoration: BoxDecoration(
                          color: KBand.colorOf(context, KBand.home),
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(KBand.footRadius)),
                        ),
                      ),
                    row,
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar's own ground: a warm gradient, away from the plum header, with a
/// faint songket star. Decorative, so hidden from screen readers.
class _PinGround extends StatelessWidget {
  const _PinGround();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color tone(Color c) => dark ? Color.lerp(c, Colors.black, 0.25)! : c;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone(KPalette.jingga), tone(KPalette.merahSaga)],
        ),
      ),
      child: KPattern(
        kind: KPatternKind.star8,
        color: _fg.withValues(alpha: 0.1),
        cell: 30,
      ),
    );
  }
}

/// A gold disc with the pin, tilted, so the bar reads as a notice at a glance.
class _PinBadge extends StatelessWidget {
  const _PinBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: KTokens.of(context).accent,
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: 0.6,
        child: const Icon(AppIcons.pin, size: 16, color: KPalette.kelabuArang),
      ),
    );
  }
}

class _PinPage extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool expanded;
  final Color color;
  final VoidCallback onTap;

  const _PinPage({
    required this.post,
    required this.expanded,
    required this.color,
    required this.onTap,
  });

  String _title() {
    final title = (post['title'] as String? ?? '').trim();
    return title.isNotEmpty ? title : (post['body'] as String? ?? '').trim();
  }

  String _source(AppStrings s) {
    final club = post['club'];
    final profile = post['profiles'];
    final name = club is Map
        ? club['name']
        : profile is Map
            ? (profile['display_name'] ?? profile['username'])
            : null;
    final event = post['events'];
    return [
      if (event is Map<String, dynamic> && isEventCancelled(event)) s.cancelled,
      if (name != null) '$name',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.l10n;
    final body = (post['body'] as String? ?? '').trim();
    final source = _source(s);
    return Semantics(
      button: true,
      label: _title(),
      hint: expanded ? s.pinOpenPost : null,
      child: InkWell(
        onTap: onTap,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _PinBarState._rowHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_title(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: color, fontWeight: FontWeight.w600)),
                      if (source.isNotEmpty)
                        Text(source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: color.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                if (expanded) ...[
                  Text(body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: color)),
                  _ManageRow(post: post, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Admins only: unpin, and switch between a normal and a mandatory pin.
class _ManageRow extends StatelessWidget {
  final Map<String, dynamic> post;
  final Color color;
  const _ManageRow({required this.post, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final mandatory = post['pin_mandatory'] == true;
    final style = TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.only(right: KSpace.m),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
    );
    return FutureBuilder<String?>(
      future: ModerationService.myRole(),
      builder: (context, snap) {
        if (!PinActions.canPin(post, snap.data)) return const SizedBox.shrink();
        return Row(children: [
          TextButton(
            style: style,
            onPressed: () => PinActions.toggle(context, post, pinned: true),
            child: Text(s.mod.unpin),
          ),
          TextButton(
            style: style,
            onPressed: () => PinActions.setMandatory(context, post, !mandatory),
            child: Text(mandatory ? s.pinMakeNormal : s.pinMakeMandatory),
          ),
        ]);
      },
    );
  }
}
