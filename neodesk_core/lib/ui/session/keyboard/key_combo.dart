import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:neodesk_core/neodesk_core.dart';

/// A user-defined shortcut chord: [label] shown on the key, [mods] the modifier
/// flags to hold, and [key] the engine `VK_*` token (or single char) to press.
class KeyCombo {
  const KeyCombo({required this.label, required this.mods, required this.key});

  final String label;
  final Set<String> mods; // subset of {ctrl, alt, shift, meta}
  final String key;

  bool get ctrl => mods.contains('ctrl');
  bool get alt => mods.contains('alt');
  bool get shift => mods.contains('shift');
  bool get meta => mods.contains('meta');

  Map<String, dynamic> toJson() =>
      {'label': label, 'mods': mods.toList(), 'key': key};

  static KeyCombo? fromJson(Map<String, dynamic> j) {
    final label = j['label'], key = j['key'];
    if (label is! String || key is! String) return null;
    final mods = (j['mods'] as List?)?.whereType<String>().toSet() ?? {};
    return KeyCombo(label: label, mods: mods, key: key);
  }
}

/// Loads/saves the shortcut combo list to [ConfigStore]; falls back to a sensible
/// default set. Kept out of the native fast path (JSON in config).
abstract final class ComboStore {
  static List<KeyCombo> load(ConfigStore cfg) {
    final raw = cfg.get(ConfigKeys.combos);
    if (raw.isEmpty) return defaults();
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(KeyCombo.fromJson)
          .whereType<KeyCombo>()
          .toList();
      return list.isEmpty ? defaults() : list;
    } catch (e) {
      debugPrint('neodesk: invalid combos config, using defaults: $e');
      return defaults();
    }
  }

  static void save(ConfigStore cfg, List<KeyCombo> combos) =>
      cfg.set(ConfigKeys.combos, jsonEncode(combos.map((c) => c.toJson()).toList()));

  // Returns a fresh growable list each call so callers can add/remove/edit
  // entries in place — never a const (unmodifiable) list.
  static List<KeyCombo> defaults() => [
        const KeyCombo(label: 'Ctrl+C', mods: {'ctrl'}, key: 'VK_C'),
        const KeyCombo(label: 'Ctrl+V', mods: {'ctrl'}, key: 'VK_V'),
        const KeyCombo(label: 'Ctrl+X', mods: {'ctrl'}, key: 'VK_X'),
        const KeyCombo(label: 'Ctrl+Z', mods: {'ctrl'}, key: 'VK_Z'),
        const KeyCombo(label: 'Ctrl+A', mods: {'ctrl'}, key: 'VK_A'),
        const KeyCombo(label: 'Ctrl+S', mods: {'ctrl'}, key: 'VK_S'),
        const KeyCombo(label: 'Alt+Tab', mods: {'alt'}, key: 'VK_TAB'),
        // Note: no Ctrl+Alt+Del here — injected as regular keys it doesn't reach
        // the secure attention desktop. The More menu's dedicated action (the
        // engine's sessionCtrlAltDel) is the one that actually works.
        const KeyCombo(label: 'Win+D', mods: {'meta'}, key: 'VK_D'),
      ];
}

/// The bounded catalogue of keys the combo editor can target (display → engine
/// token). Letters/digits/F-keys plus the common editing & navigation keys.
final Map<String, String> kComboKeys = {
  for (var c = 65; c <= 90; c++) // A–Z
    String.fromCharCode(c): 'VK_${String.fromCharCode(c)}',
  for (var d = 0; d <= 9; d++) '$d': 'VK_$d',
  for (var f = 1; f <= 12; f++) 'F$f': 'VK_F$f',
  'Enter': 'VK_ENTER',
  'Tab': 'VK_TAB',
  'Esc': 'VK_ESCAPE',
  'Space': 'VK_SPACE',
  'Backspace': 'VK_BACK',
  'Delete': 'VK_DELETE',
  'Insert': 'VK_INSERT',
  'Home': 'VK_HOME',
  'End': 'VK_END',
  'PageUp': 'VK_PRIOR',
  'PageDown': 'VK_NEXT',
  'Left': 'VK_LEFT',
  'Up': 'VK_UP',
  'Down': 'VK_DOWN',
  'Right': 'VK_RIGHT',
};
