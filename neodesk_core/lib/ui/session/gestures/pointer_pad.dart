import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'gesture_classify.dart';
import 'gesture_map.dart';
import 'gesture_tuning.dart';
import '../session_controller.dart';

/// Raw-pointer gesture state machine for **Pointer** (trackpad) mode.
///
/// Uses a [Listener] instead of [GestureDetector] so gestures are disambiguated
/// by an explicit, predictable state machine — no recognizer-arena delays (the
/// single-tap-waits-for-double-tap lag) and exact control of the trigger
/// conditions. Finger count is the primary discriminator; movement / hold time
/// resolve the rest:
///
/// | Gesture                | Trigger                                   | Action        |
/// |------------------------|-------------------------------------------|---------------|
/// | Move cursor            | 1 finger, moved > slop                    | absolute move |
/// | Left click             | 1 finger, down→up, no move, not held       | tap(left)     |
/// | Double click           | two quick left clicks (natural)            | tap(left) ×2  |
/// | Left drag (grab)       | 1 finger long-press (≥hold), then move      | hold-left drag|
/// | Right click            | 2 fingers, down→up, no move/scroll/zoom     | tap(right)    |
/// | Scroll                 | 2 fingers, vertical drag                   | wheel         |
/// | Zoom (+pan)            | 2 fingers, distance change (pinch)         | view zoom     |
/// | Show toolbar           | 3 fingers, tap                             | flash chrome  |
///
/// Clicks fire immediately (responsive); a double-tap is simply two quick
/// clicks, which the remote OS interprets as a double-click.
class PointerPad extends StatefulWidget {
  const PointerPad({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PointerPad> createState() => _PointerPadState();
}

class _PointerPadState extends State<PointerPad> {
  static const double _moveSlop = 10; // px before a touch counts as movement
  static const double _zoomActivate = 24; // spread change (px) ⇒ pinch/zoom

  final Map<int, _Finger> _fingers = {};
  int _maxFingers = 0;
  bool _moved = false;
  bool _holding = false; // long-press grab active (holding _holdButton)
  MouseButton _holdButton = MouseButton.left;
  bool _lpFired = false; // long-press fired a non-button action
  bool _dragArmed = false; // edge auto-pan armed for a one-finger move
  Timer? _longPressTimer;

  // Two-finger gesture state. Classified once into pinch / horizontal-pan /
  // vertical-scroll by whichever dominates.
  bool _twoClassified = false;
  int _twoMode = 0; // 1 = scroll, 2 = zoom, 3 = pan
  double _startDist = 0;
  double _lastDist = 0;
  Offset _startMid = Offset.zero;
  Offset _lastMid = Offset.zero;
  // When the 2nd finger landed — two-finger actions are withheld for a short
  // settle window so a quickly-following 3rd/4th finger pre-empts them.
  DateTime _twoStart = DateTime.now();
  // Each finger's start position, to tell a pinch (fingers move oppositely) from
  // a pan/scroll (fingers move together).
  Offset _startP0 = Offset.zero;
  Offset _startP1 = Offset.zero;
  double _scrollAccum = 0;

  // 3+ fingers are tap-only; track centroid movement to reject a drag as a tap.
  Offset _lastCentroid = Offset.zero;
  bool _multiMoved = false;

  SessionController get _c => widget.controller;
  InputSink get _input => _c.input;

  GestureAction _slot(GestureSlot slot) => _c.gestureMap.action(_c.mode, slot);

  Offset _centroid() {
    if (_fingers.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final f in _fingers.values) {
      sum += f.pos;
    }
    return sum / _fingers.length.toDouble();
  }

  MouseButton? _buttonOf(GestureAction a) => switch (a) {
        GestureAction.leftClick => MouseButton.left,
        GestureAction.rightClick => MouseButton.right,
        GestureAction.middleClick => MouseButton.middle,
        _ => null,
      };

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    _fingers[e.pointer] = _Finger(e.localPosition);
    if (_fingers.length > _maxFingers) _maxFingers = _fingers.length;

    if (_fingers.length == 1) {
      _moved = false;
      _lpFired = false;
      _longPressTimer = Timer(kLongPressDuration, _onLongPress);
    } else {
      _longPressTimer?.cancel();
      if (_dragArmed) {
        _dragArmed = false;
        _c.endPointerDrag(); // a one-finger move escalated to multi-finger
      }
      if (_fingers.length == 2) {
        _twoClassified = false;
        _twoMode = 0;
        _scrollAccum = 0;
        _twoStart = DateTime.now();
        final p = _fingers.values.toList();
        _startDist = _lastDist = (p[0].pos - p[1].pos).distance;
        _startMid = _lastMid = (p[0].pos + p[1].pos) / 2;
        _startP0 = p[0].pos;
        _startP1 = p[1].pos;
      }
      _lastCentroid = _centroid();
    }
  }

  void _onLongPress() {
    if (_fingers.length != 1 || _moved || _holding) return;
    final action = _slot(GestureSlot.oneFingerLongPress);
    final button = _buttonOf(action);
    if (button != null) {
      _holdButton = button;
      _holding = true;
      _input.pointerDown(button); // grab: held while dragging, released on lift
    } else {
      _lpFired = true;
      _c.performGesture(action);
    }
    HapticFeedback.selectionClick();
  }

  void _onMove(PointerMoveEvent e) {
    final f = _fingers[e.pointer];
    if (f == null) return;
    f.pos = e.localPosition;
    if (!_moved && (e.localPosition - f.down).distance > _moveSlop) {
      _moved = true;
      _longPressTimer?.cancel();
    }

    if (_fingers.length == 1) {
      if (_lpFired) return; // long-press did a discrete action
      if (!_moved) return;
      // One-finger drag → its bound action (default: move cursor; a long-press
      // grab, if active, holds the button so move-cursor becomes a drag).
      _applyContinuous(_slot(GestureSlot.oneFingerDrag), delta: e.delta);
    } else if (_fingers.length == 2) {
      _handleTwoFinger();
    } else {
      // 3+ fingers are tap-only: track centroid travel to reject a drag as a tap.
      final c = _centroid();
      if ((c - _lastCentroid).distance > _moveSlop) _multiMoved = true;
      _lastCentroid = c;
    }
  }

  /// Applies a continuous (per-frame) action bound to a drag/pinch trigger.
  void _applyContinuous(GestureAction a,
      {Offset delta = Offset.zero, double zoom = 1.0, Offset? focal}) {
    switch (a) {
      case GestureAction.moveCursor:
        if (!_dragArmed) {
          _dragArmed = true;
          _c.beginPointerDrag(); // edge auto-pan
        }
        _c.moveCursorBy(delta);
      case GestureAction.panCanvas:
        _c.transformCanvas(pan: delta);
      case GestureAction.zoomCanvas:
        if (focal != null) _c.transformCanvas(zoom: zoom, focal: focal);
      case GestureAction.scrollWheel:
        _accumScroll(delta.dy);
      default:
        break;
    }
  }

  void _accumScroll(double dy) {
    _scrollAccum += dy;
    final step = _c.scrollStep;
    while (_scrollAccum.abs() >= step) {
      _input.scroll(_c.wheelDir(_scrollAccum > 0 ? -1 : 1));
      _scrollAccum += _scrollAccum > 0 ? -step : step;
    }
  }

  void _handleTwoFinger() {
    final p = _fingers.values.toList();
    if (p.length < 2) return;
    final dist = (p[0].pos - p[1].pos).distance;
    final mid = (p[0].pos + p[1].pos) / 2;
    final dMid = mid - _lastMid;

    // Settle window: track positions but apply nothing yet, so a 3rd/4th finger
    // landing a beat later isn't pre-empted by a transient two-finger zoom/pan.
    if (DateTime.now().difference(_twoStart) < kMultiTouchSettle) {
      _lastDist = dist;
      _lastMid = mid;
      return;
    }

    // Classify once via the shared relative-motion classifier (pinch = fingers
    // move oppositely; pan/scroll = together). Stops a pinch's centroid drift
    // being read as a pan.
    if (!_twoClassified) {
      final kind = classifyTwoFinger(
        startA: _startP0,
        startB: _startP1,
        a: p[0].pos,
        b: p[1].pos,
        startDist: _startDist,
        startCentroid: _startMid,
        zoomActivate: _zoomActivate,
        dragSlop: _moveSlop,
      );
      switch (kind) {
        case TwoFingerKind.undecided:
          break;
        case TwoFingerKind.pinch:
          _twoMode = 2;
          _twoClassified = true;
        case TwoFingerKind.pan:
          _twoMode = 3;
          _twoClassified = true;
        case TwoFingerKind.scroll:
          _twoMode = 1;
          _twoClassified = true;
      }
    }

    switch (_twoMode) {
      case 2: // pinch
        _applyContinuous(_slot(GestureSlot.twoFingerPinch),
            zoom: _lastDist == 0 ? 1.0 : dist / _lastDist, focal: mid);
      case 3: // horizontal drag
        _applyContinuous(_slot(GestureSlot.twoFingerDragH), delta: dMid);
      case 1: // vertical drag
        _applyContinuous(_slot(GestureSlot.twoFingerDragV), delta: dMid);
    }
    _lastDist = dist;
    _lastMid = mid;
  }

  void _onUp(PointerUpEvent e) => _endFinger(e.pointer, clickable: true);

  void _onCancel(PointerCancelEvent e) =>
      _endFinger(e.pointer, clickable: false);

  void _endFinger(int pointer, {required bool clickable}) {
    final wasHolding = _holding;
    final wasLpFired = _lpFired;
    _fingers.remove(pointer);
    _longPressTimer?.cancel();
    if (_fingers.isNotEmpty) {
      _lastCentroid = _centroid();
      return;
    }

    // Last finger lifted — wrap up the gesture.
    if (_holding) {
      _input.pointerUp(_holdButton);
      _holding = false;
    }
    if (_dragArmed) {
      _dragArmed = false;
      _c.endPointerDrag();
    }

    // A discrete tap: no movement, no canvas gesture, not a held grab, and not
    // the tail of a long-press action. Routed through the gesture map.
    if (clickable &&
        !_moved &&
        !_multiMoved &&
        !wasHolding &&
        !wasLpFired &&
        !_twoClassified) {
      if (_maxFingers == 1) {
        _c.performGesture(_slot(GestureSlot.oneFingerTap));
      } else if (_maxFingers == 2) {
        _c.performGesture(_slot(GestureSlot.twoFingerTap));
      } else if (_maxFingers == 3) {
        _c.performGesture(_slot(GestureSlot.threeFingerTap));
      } else if (_maxFingers >= 4) {
        _c.performGesture(_slot(GestureSlot.fourFingerTap));
      }
    }

    _maxFingers = 0;
    _moved = false;
    _lpFired = false;
    _multiMoved = false;
    _twoClassified = false;
    _twoMode = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: const SizedBox.expand(),
    );
  }
}

class _Finger {
  _Finger(this.down) : pos = down;
  final Offset down;
  Offset pos;
}
