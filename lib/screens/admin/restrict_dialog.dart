import 'package:flutter/material.dart';

import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../utils/moderation_logic.dart';

class RestrictChoice {
  final Set<ModScope> scopes;
  final Duration? duration; // null = permanent
  final String reason;
  const RestrictChoice(this.scopes, this.duration, this.reason);
}

/// Scope(s) + duration + required reason. Permanent or whole-account
/// choices show a warning and turn the button red; the caller still
/// asks for a second confirmation (see [isSevereRestriction]).
Future<RestrictChoice?> showRestrictDialog(BuildContext context,
    {String? who, Set<ModScope> initialScopes = const {}}) {
  return showDialog<RestrictChoice>(
    context: context,
    builder: (_) => _RestrictDialog(who: who, initialScopes: initialScopes),
  );
}

class _RestrictDialog extends StatefulWidget {
  final String? who;
  final Set<ModScope> initialScopes;
  const _RestrictDialog({required this.who, required this.initialScopes});

  @override
  State<_RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<_RestrictDialog> {
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
    final scheme = Theme.of(context).colorScheme;
    final severe = isSevereRestriction(_scopes, _duration);

    return AlertDialog(
      title: Text(widget.who == null ? m.restrictTitle : '${m.restrictTitle}: ${widget.who}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.restrictWhat, style: Theme.of(context).textTheme.titleSmall),
              for (final s in ModScope.values)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _scopes.contains(s),
                  title: Text(m.scopeLabel(s.db)),
                  onChanged: (v) => setState(() => v == true ? _scopes.add(s) : _scopes.remove(s)),
                ),
              if (_tried && _scopes.isEmpty)
                Text(m.pickScope, style: TextStyle(color: scheme.error, fontSize: 12)),
              const SizedBox(height: 12),
              Text(m.restrictFor, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in kRestrictionDurations)
                    ChoiceChip(
                      label: Text(m.durationLabel(d)),
                      selected: _duration == d,
                      onSelected: (_) => setState(() => _duration = d),
                    ),
                ],
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
              if (severe) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(m.severeWarning,
                            style: TextStyle(color: scheme.onErrorContainer)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(m.cancel)),
        FilledButton(
          style: severe
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () {
            if (!_valid) {
              setState(() => _tried = true);
              return;
            }
            Navigator.pop(
                context, RestrictChoice({..._scopes}, _duration, _reason.text.trim()));
          },
          child: Text(m.apply),
        ),
      ],
    );
  }
}
