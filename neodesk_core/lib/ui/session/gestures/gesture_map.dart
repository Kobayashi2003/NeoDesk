import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:neodesk_core/neodesk_core.dart' show tr;

import 'interaction_ui_mode.dart';

/// What a discrete gesture does. Click-type outcomes go to the peer as mouse
/// buttons; the rest are UI/session actions. Movement, scroll and zoom are
/// mode-defined and not remappable. See DESIGN.md §4.
enum GestureAction {
  // Discrete (fired once on a tap / long-press).
  none,
  leftClick,
  rightClick,
  middleClick,
  doubleClick,
  showToolbar,
  toggleKeyboard,
  escape,
  // Continuous (applied per frame while a drag/pinch is in progress).
  moveCursor,
  panCanvas,
  zoomCanvas,
  scrollWheel,
}

extension GestureActionX on GestureAction {
  String get label => switch (this) {
        GestureAction.none => tr('None'),
        GestureAction.leftClick => tr('Left click'),
        GestureAction.rightClick => tr('Right click'),
        GestureAction.middleClick => tr('Middle click'),
        GestureAction.doubleClick => tr('Double click'),
        GestureAction.showToolbar => tr('Show toolbar'),
        GestureAction.toggleKeyboard => tr('Toggle keyboard'),
        GestureAction.escape => tr('Escape key'),
        GestureAction.moveCursor => tr('Move cursor'),
        GestureAction.panCanvas => tr('Pan view'),
        GestureAction.zoomCanvas => tr('Zoom view'),
        GestureAction.scrollWheel => tr('Scroll wheel'),
      };

  /// Continuous actions are applied each frame of a drag/pinch.
  bool get isContinuous => index >= GestureAction.moveCursor.index;
}

/// The remappable gesture triggers — the same set in both modes (a binding may be
/// `none`, but the list is unified). Three- and four-finger gestures are taps
/// only.
enum GestureSlot {
  // Ordered by finger count (then tap / long-press / drag / pinch).
  oneFingerTap,
  oneFingerLongPress,
  oneFingerDrag,
  twoFingerTap,
  twoFingerDragH,
  twoFingerDragV,
  twoFingerPinch,
  threeFingerTap,
  fourFingerTap,
}

extension GestureSlotX on GestureSlot {
  String get label => switch (this) {
        GestureSlot.oneFingerTap => tr('One-finger tap'),
        GestureSlot.oneFingerLongPress => tr('One-finger long press'),
        GestureSlot.oneFingerDrag => tr('One-finger drag'),
        GestureSlot.twoFingerTap => tr('Two-finger tap'),
        GestureSlot.twoFingerDragH => tr('Two-finger horizontal drag'),
        GestureSlot.twoFingerDragV => tr('Two-finger vertical drag'),
        GestureSlot.twoFingerPinch => tr('Two-finger pinch'),
        GestureSlot.threeFingerTap => tr('Three-finger tap'),
        GestureSlot.fourFingerTap => tr('Four-finger tap'),
      };

  /// Continuous triggers bind to continuous actions (drag/pinch); discrete to
  /// discrete actions.
  bool get isContinuous => switch (this) {
        GestureSlot.oneFingerDrag ||
        GestureSlot.twoFingerDragH ||
        GestureSlot.twoFingerDragV ||
        GestureSlot.twoFingerPinch =>
          true,
        _ => false,
      };
}

/// User-customisable gesture→action bindings, per interaction mode.
///
/// Both [InteractionUiMode.touch] and [InteractionUiMode.pointer] are
/// configurable. Persisted as JSON in `ConfigStore` (key [storageKey]) — kept
/// out of the native fast path. See DESIGN.md §4.
class GestureMap {
  GestureMap(this._m);

  static const storageKey = 'neodesk.gesturemap';

  final Map<InteractionUiMode, Map<GestureSlot, GestureAction>> _m;

  GestureAction action(InteractionUiMode mode, GestureSlot slot) =>
      _m[mode]?[slot] ?? GestureAction.none;

  void set(InteractionUiMode mode, GestureSlot slot, GestureAction a) {
    (_m[mode] ??= {})[slot] = a;
  }

  /// Remappable slots — the same unified set for both modes.
  static List<GestureSlot> get editableSlots => GestureSlot.values;

  /// Defaults shared by both modes (continuous + the unified discrete bindings).
  /// Three- and four-finger taps default to `none`.
  static const _shared = {
    GestureSlot.oneFingerTap: GestureAction.leftClick,
    // Long-press then drag holds the left button (drag/select/grab).
    GestureSlot.oneFingerLongPress: GestureAction.leftClick,
    GestureSlot.twoFingerTap: GestureAction.rightClick,
    GestureSlot.threeFingerTap: GestureAction.none,
    GestureSlot.fourFingerTap: GestureAction.none,
    GestureSlot.oneFingerDrag: GestureAction.moveCursor,
    GestureSlot.twoFingerDragH: GestureAction.panCanvas,
    GestureSlot.twoFingerDragV: GestureAction.scrollWheel,
    GestureSlot.twoFingerPinch: GestureAction.zoomCanvas,
  };

  static GestureMap defaults() => GestureMap({
        InteractionUiMode.touch: {..._shared},
        InteractionUiMode.pointer: {..._shared},
      });

  String toJson() {
    final out = <String, dynamic>{};
    _m.forEach((mode, slots) {
      out[mode.name] = {
        for (final e in slots.entries) e.key.name: e.value.name,
      };
    });
    return jsonEncode(out);
  }

  static GestureMap fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return defaults();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final base = defaults();
      decoded.forEach((modeName, slots) {
        final mode = InteractionUiMode.values
            .where((m) => m.name == modeName)
            .firstOrNull;
        if (mode == null) return;
        (slots as Map<String, dynamic>).forEach((slotName, actionName) {
          final slot =
              GestureSlot.values.where((s) => s.name == slotName).firstOrNull;
          final action = GestureAction.values
              .where((a) => a.name == actionName)
              .firstOrNull;
          if (slot != null && action != null) base.set(mode, slot, action);
        });
      });
      return base;
    } catch (e) {
      debugPrint('neodesk: invalid gesture-map config, using defaults: $e');
      return defaults();
    }
  }
}
