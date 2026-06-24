import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import 'gesture_map.dart';
import 'interaction_ui_mode.dart';

/// Lets the user remap discrete gestures → actions, per mode, persisting the
/// [GestureMap] to [ConfigStore] as JSON. See DESIGN.md.
///
/// Changes apply to the next session opened.
class GestureSettingsPage extends StatefulWidget {
  const GestureSettingsPage({super.key, required this.config});

  final ConfigStore config;

  @override
  State<GestureSettingsPage> createState() => _GestureSettingsPageState();
}

class _GestureSettingsPageState extends State<GestureSettingsPage> {
  static const _editableModes = [
    InteractionUiMode.touch,
    InteractionUiMode.pointer,
  ];

  late GestureMap _map;

  @override
  void initState() {
    super.initState();
    _map = GestureMap.fromJson(widget.config.get(GestureMap.storageKey));
  }

  void _save() => widget.config.set(GestureMap.storageKey, _map.toJson());

  void _pickAction(InteractionUiMode mode, GestureSlot slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Dimens.s16),
                child: Text(slot.label, style: AppTypography.title),
              ),
              ...GestureAction.values
                  .where((a) =>
                      a == GestureAction.none ||
                      a.isContinuous == slot.isContinuous)
                  .map((a) {
              final selected = _map.action(mode, slot) == a;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                title: Text(a.label, style: AppTypography.body),
                onTap: () {
                  setState(() => _map.set(mode, slot, a));
                  _save();
                  Navigator.pop(ctx);
                },
              );
              }),
              const SizedBox(height: Dimens.s8),
            ],
          ),
        ),
      ),
    );
  }

  void _resetDefaults() {
    setState(() => _map = GestureMap.defaults());
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize gestures'),
        actions: [
          TextButton(
            onPressed: _resetDefaults,
            child: Text('Reset',
                style: AppTypography.button.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final mode in _editableModes) ...[
            _group(mode.label),
            for (final slot in GestureMap.editableSlots)
              ListTile(
                leading:
                    const Icon(Icons.gesture, color: AppColors.textSecondary),
                title: Text(slot.label, style: AppTypography.body),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_map.action(mode, slot).label,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.accent)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textDisabled, size: 20),
                  ],
                ),
                onTap: () => _pickAction(mode, slot),
              ),
          ],
          const SizedBox(height: Dimens.s24),
        ],
      ),
    );
  }

  Widget _group(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.pageInset, Dimens.s24, Dimens.pageInset, Dimens.s8),
        child: Text(title,
            style: AppTypography.caption.copyWith(
                color: AppColors.accent, fontWeight: FontWeight.w700)),
      );
}
