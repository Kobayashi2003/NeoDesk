import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:neodesk_core/neodesk_core.dart' show tr;

import 'interaction_ui_mode.dart';

/// What a gesture does. Click-type outcomes go to the peer as mouse buttons; the
/// rest are UI/session actions. Zoom is produced only by the pinch slot and is
/// **not** remappable (see [GestureMap.editableSlots]). See DESIGN.md §4.
enum GestureAction {
  // Discrete (fired once on a tap / long-press).
  none,
  leftClick,
  rightClick,
  middleClick,
  doubleClick,
  // Hold variants — only meaningful on a long-press slot: the button goes down
  // on trigger, the finger drags with it, and it releases on lift. This is what
  // "long-press drag" (select / grab / move) is; there is no separate slot.
  holdLeft,
  holdRight,
  holdMiddle,
  showToolbar,
  toggleKeyboard,
  escape,
  // Continuous (applied per frame while a drag/pinch is in progress).
  moveCursor,
  panCanvas,
  /// Pan the view, but fall back to moving the cursor while the image already
  /// fits the viewport — at fit scale `clampOffset` pins the offset, so a plain
  /// `panCanvas` would be a silent no-op.
  panElseCursor,
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
        GestureAction.holdLeft => tr('Hold left button'),
        GestureAction.holdRight => tr('Hold right button'),
        GestureAction.holdMiddle => tr('Hold middle button'),
        GestureAction.showToolbar => tr('Show toolbar'),
        GestureAction.toggleKeyboard => tr('Toggle keyboard'),
        GestureAction.escape => tr('Escape key'),
        GestureAction.moveCursor => tr('Move cursor'),
        // Both read "Pan view": they never appear in the same picker, and the
        // cursor fallback is an implementation detail, not a mode to choose.
        GestureAction.panCanvas => tr('Pan view'),
        GestureAction.panElseCursor => tr('Pan view'),
        GestureAction.zoomCanvas => tr('Zoom view'),
        GestureAction.scrollWheel => tr('Scroll wheel'),
      };

  /// Presses a button on trigger and releases it on lift (drag while held).
  bool get isHold => switch (this) {
        GestureAction.holdLeft ||
        GestureAction.holdRight ||
        GestureAction.holdMiddle =>
          true,
        _ => false,
      };

  /// Acts *at a point*, so Touch mode must place the cursor before firing it.
  /// UI actions (toolbar/keyboard/escape) have no position.
  bool get isPositional =>
      isHold ||
      switch (this) {
        GestureAction.leftClick ||
        GestureAction.rightClick ||
        GestureAction.middleClick ||
        GestureAction.doubleClick =>
          true,
        _ => false,
      };
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
  twoFingerLongPress,
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
        GestureSlot.twoFingerLongPress => tr('Two-finger long press'),
        GestureSlot.twoFingerDragH => tr('Two-finger horizontal drag'),
        GestureSlot.twoFingerDragV => tr('Two-finger vertical drag'),
        GestureSlot.twoFingerPinch => tr('Two-finger pinch'),
        GestureSlot.threeFingerTap => tr('Three-finger tap'),
        GestureSlot.fourFingerTap => tr('Four-finger tap'),
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

  /// Schema version of the persisted JSON. v2 renamed the long-press button
  /// bindings to the explicit `hold*` actions — see [_migrateLongPress].
  static const _schema = 2;

  final Map<InteractionUiMode, Map<GestureSlot, GestureAction>> _m;

  GestureAction action(InteractionUiMode mode, GestureSlot slot) =>
      _m[mode]?[slot] ?? GestureAction.none;

  /// Illegal bindings are ignored — see [allowedActions].
  void set(InteractionUiMode mode, GestureSlot slot, GestureAction a) {
    if (!allowedActions(slot).contains(a)) return;
    (_m[mode] ??= {})[slot] = a;
  }

  /// Remappable slots. [GestureSlot.twoFingerPinch] is excluded: it is the only
  /// slot that delivers `zoom`+`focal` rather than a `delta`, so binding it to
  /// anything but [GestureAction.zoomCanvas] silently does nothing.
  static List<GestureSlot> get editableSlots =>
      GestureSlot.values.where((s) => s != GestureSlot.twoFingerPinch).toList();

  /// Which actions a slot may legally take. Determined by the **geometry the
  /// slot delivers**, not by taste:
  ///  * tap slots carry a point → discrete actions;
  ///  * only a long-press can hold a button → `hold*` on that slot alone;
  ///  * [GestureSlot.oneFingerDrag] carries `delta` *and* `absPos`, so it can
  ///    drive [GestureAction.moveCursor];
  ///  * the two-finger drags carry only a centroid `delta` (no `absPos`), so
  ///    `moveCursor` there would send the cursor to the origin — forbidden;
  ///  * pinch carries `zoom`+`focal` → zoom only.
  static List<GestureAction> allowedActions(GestureSlot slot) => switch (slot) {
        GestureSlot.oneFingerLongPress ||
        GestureSlot.twoFingerLongPress =>
          const [
            GestureAction.none,
            GestureAction.holdLeft,
            GestureAction.holdRight,
            GestureAction.holdMiddle,
            ..._discrete,
          ],
        GestureSlot.oneFingerTap ||
        GestureSlot.twoFingerTap ||
        GestureSlot.threeFingerTap ||
        GestureSlot.fourFingerTap =>
          const [GestureAction.none, ..._discrete],
        // Pans via [GestureAction.panElseCursor], never bare `panCanvas`: a
        // one-finger drag must not be a dead gesture at fit scale.
        GestureSlot.oneFingerDrag => const [
            GestureAction.none,
            GestureAction.moveCursor,
            GestureAction.panElseCursor,
            GestureAction.scrollWheel,
          ],
        GestureSlot.twoFingerDragH || GestureSlot.twoFingerDragV => const [
            GestureAction.none,
            GestureAction.panCanvas,
            GestureAction.scrollWheel,
          ],
        GestureSlot.twoFingerPinch => const [GestureAction.zoomCanvas],
      };

  static const _discrete = [
    GestureAction.leftClick,
    GestureAction.rightClick,
    GestureAction.middleClick,
    GestureAction.doubleClick,
    GestureAction.showToolbar,
    GestureAction.toggleKeyboard,
    GestureAction.escape,
  ];

  /// Bindings shared by both modes.
  static const _shared = {
    GestureSlot.oneFingerTap: GestureAction.leftClick,
    // Holding the left button *is* "long-press drag" (select / grab / move).
    GestureSlot.oneFingerLongPress: GestureAction.holdLeft,
    GestureSlot.twoFingerTap: GestureAction.rightClick,
    // Two fingers mirror one: tap clicks, resting holds the same button down.
    GestureSlot.twoFingerLongPress: GestureAction.holdRight,
    GestureSlot.threeFingerTap: GestureAction.showToolbar,
    GestureSlot.fourFingerTap: GestureAction.none,
    GestureSlot.twoFingerDragV: GestureAction.scrollWheel,
    GestureSlot.twoFingerPinch: GestureAction.zoomCanvas,
  };

  /// Where the modes genuinely differ. Touch is absolute, so a one-finger drag
  /// pans the view (the cursor is placed by tapping, long-press-drag selects),
  /// leaving the horizontal two-finger drag with nothing to do. Pointer is a
  /// relative trackpad, so a one-finger drag *is* the cursor, and panning falls
  /// to the two-finger drag.
  static GestureMap defaults() => GestureMap({
        InteractionUiMode.touch: {
          ..._shared,
          GestureSlot.oneFingerDrag: GestureAction.panElseCursor,
          GestureSlot.twoFingerDragH: GestureAction.none,
        },
        InteractionUiMode.pointer: {
          ..._shared,
          GestureSlot.oneFingerDrag: GestureAction.moveCursor,
          GestureSlot.twoFingerDragH: GestureAction.panCanvas,
        },
      });

  /// The v1 defaults for the slots whose *default* changed in v2. A stored v1
  /// value equal to one of these was never chosen by the user — it is just the
  /// old default — so it must give way to the new one, or upgraders silently
  /// keep the old behaviour forever. A value that differs was a real choice and
  /// is preserved.
  static const _v1Defaults = {
    GestureSlot.oneFingerDrag: GestureAction.moveCursor,
    GestureSlot.twoFingerDragH: GestureAction.panCanvas,
    GestureSlot.threeFingerTap: GestureAction.none,
  };

  String toJson() {
    final out = <String, dynamic>{'_v': _schema};
    _m.forEach((mode, slots) {
      out[mode.name] = {
        for (final e in slots.entries) e.key.name: e.value.name,
      };
    });
    return jsonEncode(out);
  }

  /// Bring one persisted binding up to the current schema. Returns null when the
  /// stored value should be dropped in favour of the current default.
  static GestureAction? _normalise(
      int version, GestureSlot slot, GestureAction action) {
    if (version < _schema) {
      // Pre-v2 a *click* on the long-press slot actually held the button (the
      // drag was implicit); don't silently demote those users to a plain click.
      if (slot == GestureSlot.oneFingerLongPress) {
        return switch (action) {
          GestureAction.leftClick => GestureAction.holdLeft,
          GestureAction.rightClick => GestureAction.holdRight,
          GestureAction.middleClick => GestureAction.holdMiddle,
          _ => action,
        };
      }
      if (_v1Defaults[slot] == action) return null;
    }
    // 1.9.1 briefly allowed a bare `panCanvas` here, a no-op at fit scale.
    if (slot == GestureSlot.oneFingerDrag &&
        action == GestureAction.panCanvas) {
      return GestureAction.panElseCursor;
    }
    return action;
  }

  static GestureMap fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return defaults();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final version = (decoded['_v'] as num?)?.toInt() ?? 1;
      final base = defaults();
      decoded.forEach((modeName, slots) {
        final mode = InteractionUiMode.values
            .where((m) => m.name == modeName)
            .firstOrNull;
        if (mode == null) return; // skips '_v'
        (slots as Map<String, dynamic>).forEach((slotName, actionName) {
          final slot =
              GestureSlot.values.where((s) => s.name == slotName).firstOrNull;
          final stored = GestureAction.values
              .where((a) => a.name == actionName)
              .firstOrNull;
          if (slot == null || stored == null) return;
          final action = _normalise(version, slot, stored);
          if (action != null) base.set(mode, slot, action);
        });
      });
      return base;
    } catch (e) {
      debugPrint('neodesk: invalid gesture-map config, using defaults: $e');
      return defaults();
    }
  }
}
