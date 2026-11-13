import 'package:flutter/material.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/attendance_form_strings.dart';
import '../../language_cubit.dart';
import '../../services/form_service.dart';
import '../../services/my_forms_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/form_picker.dart';

/// Which form, if any, is asked after check-in.
enum AttendanceFormKind { none, own, other }

/// What "Start" was tapped with.
class AttendanceFormChoice {
  final AttendanceFormKind kind;

  /// The form picked from My forms, for [AttendanceFormKind.other].
  final String? otherId;
  final String? otherTitle;

  /// "Make a form for this event" was tapped instead of Start.
  final bool makeOwn;

  const AttendanceFormChoice(this.kind,
      {this.otherId, this.otherTitle, this.makeOwn = false});

  const AttendanceFormChoice.makeOwn()
      : kind = AttendanceFormKind.none,
        otherId = null,
        otherTitle = null,
        makeOwn = true;
}

/// The one question before the door opens: which form comes after check-in?
///
/// No form · this event's own form (when it has one) · one of my forms
/// (picked with [showFormPicker]). [canPickAny] is false on a database without
/// 20261113001100, where only the event's own form can be stored.
class AttendanceStartDialog extends StatefulWidget {
  final FormDoc? ownForm;
  final AttendanceFormKind initialKind;
  final String? initialOtherId;
  final String? initialOtherTitle;
  final bool canPickAny;

  /// Tests replace the sheet.
  final Future<MyForm?> Function(BuildContext context)? pickForm;

  const AttendanceStartDialog({
    super.key,
    this.ownForm,
    this.initialKind = AttendanceFormKind.none,
    this.initialOtherId,
    this.initialOtherTitle,
    this.canPickAny = true,
    this.pickForm,
  });

  @override
  State<AttendanceStartDialog> createState() => _AttendanceStartDialogState();
}

class _AttendanceStartDialogState extends State<AttendanceStartDialog> {
  late AttendanceFormKind _kind = _validInitial();
  late String? _otherId = widget.initialOtherId;
  late String? _otherTitle = widget.initialOtherTitle;

  AttendanceFormKind _validInitial() => switch (widget.initialKind) {
        AttendanceFormKind.own when widget.ownForm == null => AttendanceFormKind.none,
        AttendanceFormKind.other
            when !widget.canPickAny || widget.initialOtherId == null =>
          AttendanceFormKind.none,
        final k => k,
      };

  Future<void> _pick() async {
    final pick = widget.pickForm ?? (c) => showFormPicker(c, openOnly: true);
    final f = await pick(context);
    if (!mounted) return;
    if (f == null) {
      // Cancelled: keep the earlier pick, or fall back to no form.
      if (_otherId == null) setState(() => _kind = AttendanceFormKind.none);
      return;
    }
    setState(() {
      _kind = AttendanceFormKind.other;
      _otherId = f.id;
      _otherTitle = f.title;
    });
  }

  void _select(AttendanceFormKind? k) {
    if (k == null) return;
    setState(() => _kind = k);
    if (k == AttendanceFormKind.other && _otherId == null) _pick();
  }

  bool get _ready => _kind != AttendanceFormKind.other || _otherId != null;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final small = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final own = widget.ownForm;

    final tilePad = const EdgeInsets.symmetric(horizontal: KSpace.s);

    return AlertDialog(
      // Narrower margins on a phone, so a form's name is not squeezed.
      insetPadding:
          const EdgeInsets.symmetric(horizontal: KSpace.l, vertical: KSpace.xl),
      icon: const Icon(AppIcons.qrCode),
      title: Text(s.evStartTitle),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.evStartBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: KSpace.l),
            Text(s.afQuestion, style: theme.textTheme.titleSmall),
            Text(s.evAddKiHint, style: small),
            const SizedBox(height: KSpace.s),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: RadioGroup<AttendanceFormKind>(
                groupValue: _kind,
                onChanged: _select,
                child: Column(
                  children: [
                    RadioListTile<AttendanceFormKind>(
                      key: const ValueKey('af-none'),
                      value: AttendanceFormKind.none,
                      contentPadding: tilePad,
                      title: Text(s.afNone, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(s.afNoneHint, style: small),
                    ),
                    if (own != null)
                      RadioListTile<AttendanceFormKind>(
                        key: const ValueKey('af-own'),
                        value: AttendanceFormKind.own,
                        contentPadding: tilePad,
                        title: Text(s.afOwn(own.title),
                            style: const TextStyle(fontSize: 14),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ),
                    if (widget.canPickAny)
                      RadioListTile<AttendanceFormKind>(
                        key: const ValueKey('af-other'),
                        value: AttendanceFormKind.other,
                        contentPadding: tilePad,
                        title: Text(s.afPick, style: const TextStyle(fontSize: 14)),
                        subtitle: _otherTitle == null
                            ? Text(s.afPickHint, style: small)
                            : Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: KSpace.s,
                                children: [
                                  Text(_otherTitle!,
                                      key: const ValueKey('af-other-title'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: small.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600)),
                                  TextButton(
                                    key: const ValueKey('af-change'),
                                    onPressed: _pick,
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: KSpace.s),
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(s.afChange),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
            ),
            if (own == null) ...[
              const SizedBox(height: KSpace.xs),
              TextButton.icon(
                key: const ValueKey('af-make-own'),
                onPressed: () =>
                    Navigator.pop(context, const AttendanceFormChoice.makeOwn()),
                icon: const Icon(AppIcons.create, size: 18),
                label: Text(s.afMakeOwn),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          key: const ValueKey('af-start'),
          onPressed: _ready
              ? () => Navigator.pop(
                    context,
                    AttendanceFormChoice(_kind,
                        otherId: _kind == AttendanceFormKind.other ? _otherId : null,
                        otherTitle:
                            _kind == AttendanceFormKind.other ? _otherTitle : null),
                  )
              : null,
          child: Text(s.evStart),
        ),
      ],
    );
  }
}
