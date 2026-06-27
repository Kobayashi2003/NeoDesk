import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import 'key_combo.dart';

/// Add / edit / remove the shortcut combos shown on the keyboard's Fn panel.
/// Persists to [ConfigStore] via [ComboStore]; changes apply next time the
/// keyboard is opened.
class ComboSettingsPage extends StatefulWidget {
  const ComboSettingsPage({super.key, required this.config});

  final ConfigStore config;

  @override
  State<ComboSettingsPage> createState() => _ComboSettingsPageState();
}

class _ComboSettingsPageState extends State<ComboSettingsPage> {
  late List<KeyCombo> _combos = ComboStore.load(widget.config);

  static const _modOrder = ['ctrl', 'alt', 'shift', 'meta'];
  static const _modNames = {
    'ctrl': 'Ctrl',
    'alt': 'Alt',
    'shift': 'Shift',
    'meta': 'Win',
  };

  void _save() => ComboStore.save(widget.config, _combos);

  String _labelFor(Set<String> mods, String keyDisplay) => [
        for (final m in _modOrder)
          if (mods.contains(m)) _modNames[m]!,
        keyDisplay,
      ].join('+');

  void _delete(int i) {
    setState(() => _combos.removeAt(i));
    _save();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView reports newIndex as the slot *before* removal.
      if (newIndex > oldIndex) newIndex -= 1;
      _combos.insert(newIndex, _combos.removeAt(oldIndex));
    });
    _save();
  }

  void _addOrEdit([int? index]) {
    final editing = index != null ? _combos[index] : null;
    final mods = {...?editing?.mods};
    // Default the key picker to the editing combo's key, else 'C'.
    var keyDisplay = kComboKeys.entries
        .firstWhere((e) => e.value == (editing?.key ?? 'VK_C'),
            orElse: () => kComboKeys.entries.first)
        .key;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(Dimens.s16, Dimens.s16, Dimens.s16,
                MediaQuery.of(ctx).viewInsets.bottom + Dimens.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(editing == null ? 'New shortcut' : 'Edit shortcut'),
                    style: AppTypography.title),
                const SizedBox(height: Dimens.s16),
                Text(tr('Modifiers'), style: AppTypography.caption),
                const SizedBox(height: Dimens.s8),
                Wrap(
                  spacing: Dimens.s8,
                  children: _modOrder.map((m) {
                    final on = mods.contains(m);
                    return FilterChip(
                      label: Text(_modNames[m]!),
                      selected: on,
                      onSelected: (v) => setSheet(
                          () => v ? mods.add(m) : mods.remove(m)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: Dimens.s16),
                Row(
                  children: [
                    Text(tr('Key'), style: AppTypography.caption),
                    const SizedBox(width: Dimens.s16),
                    DropdownButton<String>(
                      value: keyDisplay,
                      dropdownColor: AppColors.bgElevated2,
                      items: kComboKeys.keys
                          .map((k) => DropdownMenuItem(
                              value: k,
                              child: Text(k, style: AppTypography.body)))
                          .toList(),
                      onChanged: (v) =>
                          setSheet(() => keyDisplay = v ?? keyDisplay),
                    ),
                    const Spacer(),
                    Text(_labelFor(mods, keyDisplay),
                        style: AppTypography.body
                            .copyWith(color: AppColors.accent)),
                  ],
                ),
                const SizedBox(height: Dimens.s24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final combo = KeyCombo(
                        label: _labelFor(mods, keyDisplay),
                        mods: {...mods},
                        key: kComboKeys[keyDisplay]!,
                      );
                      setState(() {
                        if (index != null) {
                          _combos[index] = combo;
                        } else {
                          _combos.add(combo);
                        }
                      });
                      _save();
                      Navigator.pop(ctx);
                    },
                    child: Text(tr('Save')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Shortcut combos')),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _combos = ComboStore.defaults());
              _save();
            },
            child: Text(tr('Reset'),
                style: AppTypography.button.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _addOrEdit(),
        child: Icon(Icons.add, color: AppColors.textOnAccent),
      ),
      // Drag the handle to reorder; tap a row to edit. Explicit handles only
      // (no long-press-anywhere) so the row's tap-to-edit stays unambiguous.
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _combos.length,
        onReorder: _reorder,
        itemBuilder: (context, i) {
          final c = _combos[i];
          return ListTile(
            key: ObjectKey(c),
            leading: Icon(Icons.keyboard_command_key,
                color: AppColors.textSecondary),
            title: Text(c.label, style: AppTypography.body),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Dimens.s8),
                    child: Icon(Icons.drag_handle,
                        color: AppColors.textSecondary),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: AppColors.textSecondary),
                  onPressed: () => _delete(i),
                ),
              ],
            ),
            onTap: () => _addOrEdit(i),
          );
        },
      ),
    );
  }
}
