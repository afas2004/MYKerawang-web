import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/moderation_logic.dart';
import '../../widgets/moderation_ui.dart';

class RestrictChoice {
  final Set<ModScope> scopes;
  final Duration? duration; // null = permanent
  final String reason;
  const RestrictChoice(this.scopes, this.duration, this.reason);
}

/// Presets offered by the picker. null = permanent.
const kRestrictPresets = <Duration?>[
  Duration(days: 1),
  Duration(days: 7),
  Duration(days: 30),
  null,
];

/// Plain-language preview of a restriction, as the user will live it:
/// "They won't be able to post or comment. This lifts automatically on
/// 26 Oct 2026, 3:00 PM. They can still browse…". Empty scopes → hint.
List<String> restrictionPreview(
    ModerationStrings m, Set<ModScope> scopes, Duration? duration, DateTime now) {
  final u = m.ui;
  if (scopes.isEmpty) return [u.previewPick];
  final verbs = scopes.contains(ModScope.account)
      ? [u.verbAccount]
      : [
          for (final s in ModScope.values)
            if (scopes.contains(s)) u.verb(s.db),
        ];
  final list = verbs.length <= 1
      ? verbs.join()
      : '${verbs.sublist(0, verbs.length - 1).join(', ')}${u.listJoin}${verbs.last}';
  return [
    u.previewCant.fill([list]),
    duration == null ? u.previewForever : u.previewUntil.fill([formatUntil(now.add(duration))]),
    u.previewCan,
  ];
}

/// Scope(s) + duration preset + required reason, with a live preview of
/// what the user will experience. Permanent or whole-account choices
/// turn the button red; the caller confirms once more
/// ([isSevereRestriction]).
Future<RestrictChoice?> showRestrictDialog(BuildContext context,
    {String? who, Set<ModScope> initialScopes = const {}}) {
  return showDialog<RestrictChoice>(
    context: context,
    builder: (_) => RestrictDialog(who: who, initialScopes: initialScopes),
  );
}

class RestrictDialog extends StatefulWidget {
  final String? who;
  final Set<ModScope> initialScopes;
  const RestrictDialog({super.key, required this.who, required this.initialScopes});

  @override
  State<RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<RestrictDialog> {
  late final Set<ModScope> _scopes = {...widget.initialScopes};
  Duration? _duration = const Duration(days: 7);
  final _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _valid => _scopes.isNotEmpty && _reason.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final severe = isSevereRestriction(_scopes, _duration);
    final preview = restrictionPreview(m, _scopes, _duration, DateTime.now());

    return AlertDialog(
      title: Text(widget.who == null ? m.restrictTitle : '${m.restrictTitle}: ${widget.who}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.restrictWhat, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in ModScope.values)
                    FilterChip(
                      label: Text(m.scopeLabel(s.db)),
                      selected: _scopes.contains(s),
                      selectedColor: s == ModScope.account ? scheme.errorContainer : null,
                      onSelected: (v) => setState(() => v ? _scopes.add(s) : _scopes.remove(s)),
                    ),
                ],
              ),
              if (_tried && _scopes.isEmpty) ...[
                const SizedBox(height: 4),
                Text(m.pickScope, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              Text(m.restrictFor, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in kRestrictPresets)
                    ChoiceChip(
                      label: Text(m.durationLabel(d)),
                      selected: _duration == d,
                      onSelected: (_) => setState(() => _duration = d),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: severe ? scheme.errorContainer : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(ModIcons.visible,
                            size: 16, color: severe ? scheme.onErrorContainer : scheme.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(m.ui.previewTitle,
                              style: theme.textTheme.labelLarge?.copyWith(
                                  color: severe ? scheme.onErrorContainer : scheme.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    for (final line in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(line,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: severe ? scheme.onErrorContainer : scheme.onSurface)),
                      ),
                    if (severe) ...[
                      const SizedBox(height: 6),
                      Text(m.severeWarning,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                onChanged: (_) {
                  if (_tried) setState(() {});
                },
                decoration: InputDecoration(
                  labelText: m.reasonLabel,
                  helperText: m.reasonHelp,
                  helperMaxLines: 3,
                  errorText: _tried && _reason.text.trim().length < 3 ? m.reasonTooShort : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(m.cancel)),
        FilledButton(
          style: severe
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () {
            if (!_valid) {
              setState(() => _tried = true);
              return;
            }
            Navigator.pop(context, RestrictChoice({..._scopes}, _duration, _reason.text.trim()));
          },
          child: Text(m.apply),
        ),
      ],
    );
  }
}
