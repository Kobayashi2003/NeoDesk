import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gesture_classify.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'gesture_map.dart';
import 'gesture_tuning.dart';
import '../session_controller.dart';

/// Raw-pointer gesture state machine for **Touch** (absolute, "tap where you
/// touch") mode. Like [PointerPad] it uses a [Listener] so gestures resolve
/// through an explicit state machine with no recognizer-arena delays.
///
/// | Gesture                       | Action                              |
/// |-------------------------------|-------------------------------------|
/// | 1-finger tap                  | left click at the point             |
/// | 1-finger drag                 | move the cursor (no button)         |
/// | 1-finger long-press → drag    | hold the mapped button + drag       |
/// | 2-finger tap                  | mapped action (right click)         |
/// | 2-finger horizontal drag      | pan the canvas                      |
/// | 2-finger vertical drag        | wheel scroll                        |
/// | 2-finger pinch                | zoom                                |
/// | 3-finger drag                 | pan the canvas (free)               |
/// | 3-finger tap                  | show toolbar                        |
/// | 4-finger tap                  | toggle keyboard                     |
///
/// A two-finger drag is classified once (pinch vs horizontal-pan vs
/// vertical-scroll) by whichever dominates, with tolerance — it needn't be
/// perfectly axis-aligned. See DESIGN.md §4.2.
class TouchPad extends StatefulWidget {
  const TouchPad({super.key, required this.controller});

  final SessionController controller;

  @override
  State<TouchPad> createState() => _TouchPadState();
}

class _TouchPadState extends State<TouchPad> {
  static const double _dragSlop = 12;
  static const double _tapSlop = 16;
  static const double _zoomActivate = 24; // spread change (px) ⇒ pinch/zoom

  final Map<int, _Finger> _fingers = {};
  int _maxFingers = 0;
  DateTime _gestureStart = DateTime.now();

  // One-finger state.
  bool _moved = false;
  bool _lpFired = false;
  bool _lpHolding = false;
  MouseButton _lpButton = MouseButton.left;
  Timer? _longPressTimer;

  // Multi-finger state.
  int _twoClass = 0; // 0 = unclassified, 1 = zoom, 2 = pan, 3 = scroll
  // When the 2nd finger landed — two-finger actions are withheld for a short
  // settle window so a quickly-following 3rd/4th finger pre-empts them.
  DateTime _twoStart = DateTime.now();
  double _startDist = 0;
  double _lastDist = 0;
  Offset _startCentroid = Offset.zero;
  // Each finger's position when the two-finger gesture began, so we can tell a
  // pinch (fingers move oppositely) from a pan/scroll (fingers move together).
  Offset _startA = Offset.zero;
  Offset _startB = Offset.zero;
  Offset _lastCentroid = Offset.zero;
  double _scrollAccum = 0;
  double _travel = 0;
  double _maxZoomDev = 0;

  SessionController get _c => widget.controller;
  InputSink get _input => _c.input;

  GestureAction _slot(GestureSlot slot) => _c.gestureMap.action(_c.mode, slot);

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

  Offset _centroid() {
    if (_fingers.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (final f in _fingers.values) {
      sum += f.pos;
    }
    return sum / _fingers.length.toDouble();
  }

  (Offset, Offset) _twoPositions() {
    final l = _fingers.values.toList();
    return (l[0].pos, l[1].pos);
  }

  // ---- pointer lifecycle ----------------------------------------------------

  void _onDown(PointerDownEvent e) {
    _fingers[e.pointer] = _Finger(e.localPosition);
    if (_fingers.length > _maxFingers) _maxFingers = _fingers.length;

    if (_fingers.length == 1) {
      _moved = false;
      _lpFired = false;
      _gestureStart = DateTime.now();
      _travel = 0;
      _maxZoomDev = 0;
      _longPressTimer = Timer(kLongPressDuration, _onLongPress);
      _c.setChrome(false);
    } else {
      _longPressTimer?.cancel();
      _releaseHold();
      _twoClass = 0;
      _scrollAccum = 0;
      if (_fingers.length == 2) {
        _twoStart = DateTime.now();
        final (a, b) = _twoPositions();
        _startDist = _lastDist = (a - b).distance;
        _startA = a;
        _startB = b;
      }
      _startCentroid = _centroid();
    }
    _lastCentroid = _centroid();
  }

  void _onLongPress() {
    if (_fingers.length != 1 || _moved || _lpHolding) return;
    _lpFired = true;
    final pos = _fingers.values.first.pos;
    _c.cursorTo(pos);
    final action = _slot(GestureSlot.oneFingerLongPress);
    final button = _buttonOf(action);
    if (button != null) {
      _lpButton = button;
      _lpHolding = true;
      _input.pointerDown(button); // released when the finger lifts
    } else {
      _c.performGesture(action);
    }
    HapticFeedback.selectionClick();
  }

  void _onMove(PointerMoveEvent e) {
    final f = _fingers[e.pointer];
    if (f == null) return;
    f.pos = e.localPosition;
    final n = _fingers.length;

    if (n == 1) {
      if (!_moved && (f.pos - f.down).distance > _dragSlop) {
        _moved = true;
        _longPressTimer?.cancel();
      }
      if (_lpHolding) {
        _c.cursorTo(f.pos); // drag the held button
      } else if (_lpFired) {
        return; // long-press did a discrete action
      } else if (_moved) {
        // Plain one-finger drag → its bound action (default: move cursor).
        _applyContinuous(_slot(GestureSlot.oneFingerDrag),
            delta: e.delta, absPos: f.pos);
      }
    } else if (n == 2) {
      _handleTwoFinger();
    } else {
      _trackMulti(); // 3+ fingers: tap-only, just track for tap rejection
    }
  }

  /// Applies a continuous (per-frame) action bound to a drag/pinch trigger.
  void _applyContinuous(GestureAction a,
      {Offset delta = Offset.zero,
      Offset? absPos,
      double zoom = 1.0,
      Offset? focal}) {
    switch (a) {
      case GestureAction.moveCursor:
        if (absPos != null) _c.cursorTo(absPos);
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

  /// Classify the two-finger gesture once, then keep applying it.
  void _handleTwoFinger() {
    final (a, b) = _twoPositions();
    final dist = (a - b).distance;
    final centroid = (a + b) / 2;

    // Settle window: track positions but apply nothing (and don't accrue travel
    // / zoom deviation) yet, so a 3rd/4th finger landing a beat later isn't
    // pre-empted by a transient two-finger zoom — and its tap still registers.
    if (DateTime.now().difference(_twoStart) < kMultiTouchSettle) {
      _lastDist = dist;
      _lastCentroid = centroid;
      return;
    }

    if (_twoClass == 0) {
      _twoClass = _classifyTwoFinger(a, b, dist, centroid);
    }

    final dCentroid = centroid - _lastCentroid;
    _travel += dCentroid.distance;
    switch (_twoClass) {
      case 1: // pinch
        final dev = _startDist == 0 ? 0.0 : (dist / _startDist - 1).abs();
        if (dev > _maxZoomDev) _maxZoomDev = dev;
        _applyContinuous(_slot(GestureSlot.twoFingerPinch),
            zoom: _lastDist == 0 ? 1.0 : dist / _lastDist, focal: centroid);
      case 2: // horizontal drag
        _applyContinuous(_slot(GestureSlot.twoFingerDragH), delta: dCentroid);
      case 3: // vertical drag
        _applyContinuous(_slot(GestureSlot.twoFingerDragV), delta: dCentroid);
    }
    _lastDist = dist;
    _lastCentroid = centroid;
  }

  /// Maps the shared classifier to this pad's mode codes (1=pinch/2=pan/3=scroll).
  int _classifyTwoFinger(Offset a, Offset b, double dist, Offset centroid) =>
      switch (classifyTwoFinger(
        startA: _startA,
        startB: _startB,
        a: a,
        b: b,
        startDist: _startDist,
        startCentroid: _startCentroid,
        zoomActivate: _zoomActivate,
        dragSlop: _dragSlop,
      )) {
        TwoFingerKind.undecided => 0,
        TwoFingerKind.pinch => 1,
        TwoFingerKind.pan => 2,
        TwoFingerKind.scroll => 3,
      };

  /// Three+ fingers are tap-only: track centroid travel so a multi-finger drag is
  /// rejected as a tap, but apply no continuous action.
  void _trackMulti() {
    final centroid = _centroid();
    _travel += (centroid - _lastCentroid).distance;
    _lastCentroid = centroid;
  }

  void _accumScroll(double dy) {
    _scrollAccum += dy;
    final step = _c.scrollStep;
    while (_scrollAccum.abs() >= step) {
      _input.scroll(_c.wheelDir(_scrollAccum > 0 ? -1 : 1));
      _scrollAccum += _scrollAccum > 0 ? -step : step;
    }
  }

  void _onUp(PointerUpEvent e) => _endFinger(e.pointer, clickable: true);

  void _onCancel(PointerCancelEvent e) =>
      _endFinger(e.pointer, clickable: false);

  void _endFinger(int pointer, {required bool clickable}) {
    final ended = _fingers[pointer];
    final wasHold = _lpHolding;
    final wasLpFired = _lpFired;
    _fingers.remove(pointer);
    _longPressTimer?.cancel();

    if (_fingers.isNotEmpty) {
      _lastCentroid = _centroid();
      if (_fingers.length == 2) {
        _twoStart = DateTime.now();
        final (a, b) = _twoPositions();
        _startDist = _lastDist = (a - b).distance;
        _startCentroid = _lastCentroid;
        _twoClass = 0;
      }
      return;
    }

    _releaseHold();

    final quick = _travel < _tapSlop &&
        _maxZoomDev < 0.08 &&
        DateTime.now().difference(_gestureStart) < kMultiTapTimeout;
    if (clickable && !_moved && !wasHold && !wasLpFired) {
      if (_maxFingers == 1) {
        _c.cursorTo(ended?.pos ?? ended?.down ?? Offset.zero);
        _c.performGesture(_slot(GestureSlot.oneFingerTap));
      } else if (_maxFingers == 2 && quick && _twoClass == 0) {
        _c.performGesture(_slot(GestureSlot.twoFingerTap));
      } else if (_maxFingers == 3 && quick) {
        _c.performGesture(_slot(GestureSlot.threeFingerTap));
      } else if (_maxFingers >= 4 && quick) {
        _c.performGesture(_slot(GestureSlot.fourFingerTap));
      }
    }
    _resetGesture();
  }

  void _resetGesture() {
    _maxFingers = 0;
    _moved = false;
    _lpFired = false;
    _twoClass = 0;
    _travel = 0;
    _maxZoomDev = 0;
    _scrollAccum = 0;
  }

  void _releaseHold() {
    if (_lpHolding) {
      _input.pointerUp(_lpButton);
      _lpHolding = false;
    }
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
