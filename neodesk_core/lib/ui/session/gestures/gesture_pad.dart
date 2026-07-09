import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:neodesk_core/neodesk_core.dart';

import 'gesture_engine.dart';
import 'gesture_map.dart';
import 'interaction_ui_mode.dart';
import '../session_controller.dart';

/// The in-session input surface: a raw [Listener] feeding the shared
/// [GestureEngine], whose decisions this pad executes against the
/// [SessionController]. Works for both interaction modes — the only difference
/// (absolute cursor vs relative trackpad + edge-pan) lives in [_SessionSink].
class GesturePad extends StatefulWidget {
  const GesturePad({super.key, required this.controller});

  final SessionController controller;

  @override
  State<GesturePad> createState() => _GesturePadState();
}

class _GesturePadState extends State<GesturePad> {
  late final GestureEngine _engine = GestureEngine(
    tuning: widget.controller.gestureTuning,
    sink: _SessionSink(widget.controller),
  );

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _engine.down(e.pointer, e.localPosition),
      onPointerMove: (e) => _engine.move(e.pointer, e.localPosition, e.delta),
      onPointerUp: (e) => _engine.up(e.pointer),
      onPointerCancel: (e) => _engine.cancel(e.pointer),
      child: const SizedBox.expand(),
    );
  }
}

/// Executes recognised gestures against the session. This is where the two modes
/// diverge: Touch places the cursor absolutely ([SessionController.cursorTo]),
/// Pointer moves it relatively ([SessionController.moveCursorBy]) with edge-pan.
class _SessionSink extends GestureSink {
  _SessionSink(this._c);

  final SessionController _c;
  MouseButton _heldButton = MouseButton.left;
  double _scrollAccum = 0;
  bool _dragArmed = false;

  bool get _touch => _c.mode == InteractionUiMode.touch;
  GestureAction _action(GestureSlot s) => _c.gestureMap.action(_c.mode, s);

  MouseButton? _holdButtonOf(GestureAction a) => switch (a) {
        GestureAction.holdLeft => MouseButton.left,
        GestureAction.holdRight => MouseButton.right,
        GestureAction.holdMiddle => MouseButton.middle,
        _ => null,
      };

  /// Touch mode is absolute, so a positional action must first place the cursor
  /// at the gesture's anchor. Pointer mode acts wherever the cursor already is.
  void _placeCursor(GestureAction action, Offset anchor) {
    if (_touch && action.isPositional) _c.cursorTo(anchor);
  }

  @override
  void gestureStart() {
    // Touch mode: touching the remote dismisses the toolbar.
    if (_touch) _c.setChrome(false);
  }

  @override
  void tap(GestureSlot slot, Offset at) {
    final action = _action(slot);
    _placeCursor(action, at);
    _c.performGesture(action);
  }

  @override
  LongPressOutcome longPress(GestureSlot slot, Offset at) {
    final action = _action(slot);
    if (action == GestureAction.none) return LongPressOutcome.ignored;
    _placeCursor(action, at);
    HapticFeedback.selectionClick();
    final button = _holdButtonOf(action);
    if (button != null) {
      _heldButton = button;
      _c.input.pointerDown(button); // grab: held while dragging, released on lift
      _c.beginHoldDrag(at); // keep going if the finger reaches a screen edge
      return LongPressOutcome.holding;
    }
    _c.performGesture(action);
    return LongPressOutcome.fired;
  }

  @override
  void holdDrag(Offset absPos, Offset delta) {
    _c.updateHoldFinger(absPos);
    if (_touch) {
      _c.cursorTo(absPos);
    } else {
      _c.moveCursorBy(delta);
    }
  }

  @override
  void holdEnd() {
    _c.endHoldDrag();
    _c.input.pointerUp(_heldButton);
  }

  @override
  void continuous(GestureSlot slot,
      {Offset delta = Offset.zero,
      Offset absPos = Offset.zero,
      double zoom = 1.0,
      Offset focal = Offset.zero}) {
    switch (_action(slot)) {
      case GestureAction.moveCursor:
        _dragCursor(absPos, delta);
      case GestureAction.panCanvas:
        _c.transformCanvas(pan: delta);
      case GestureAction.panElseCursor:
        // A pan is pinned by clampOffset at fit scale, so it would be a dead
        // gesture there — move the cursor instead.
        if (_c.canPan) {
          _c.transformCanvas(pan: delta);
        } else {
          _dragCursor(absPos, delta);
        }
      case GestureAction.zoomCanvas:
        _c.transformCanvas(zoom: zoom, focal: focal);
      case GestureAction.scrollWheel:
        _accumScroll(delta.dy);
      default:
        break;
    }
  }

  /// Drag the cursor: absolutely in Touch mode, relatively (with edge auto-pan)
  /// in Pointer mode.
  void _dragCursor(Offset absPos, Offset delta) {
    if (_touch) {
      _c.cursorTo(absPos);
      return;
    }
    if (!_dragArmed) {
      _dragArmed = true;
      _c.beginPointerDrag(); // edge auto-pan (FakeCore only)
    }
    _c.moveCursorBy(delta);
  }

  @override
  void gestureEnd() {
    if (_dragArmed) {
      _dragArmed = false;
      _c.endPointerDrag();
    }
    _scrollAccum = 0;
  }

  void _accumScroll(double dy) {
    _scrollAccum += dy;
    final step = _c.scrollStep;
    while (_scrollAccum.abs() >= step) {
      _c.input.scroll(_c.wheelDir(_scrollAccum > 0 ? -1 : 1));
      _scrollAccum += _scrollAccum > 0 ? -step : step;
    }
  }
}
