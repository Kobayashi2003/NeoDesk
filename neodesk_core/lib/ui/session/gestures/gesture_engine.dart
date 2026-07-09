import 'dart:async';

import 'package:flutter/widgets.dart';

import 'gesture_classify.dart';
import 'gesture_map.dart';
import 'gesture_tuning.dart';

/// Where a recognised gesture goes. The engine only *detects* gestures (which
/// [GestureSlot] fired, plus the geometry); the sink decides what to *do* — in a
/// real session that's cursor/click/scroll via the controller (mode-aware), in
/// the settings test area it's just a readout. This split lets both reuse the
/// exact same recognition logic. See DESIGN.md §4.2.
/// What the sink did with a long-press, which decides whether the gesture is
/// consumed. [ignored] (the slot is bound to `none`) leaves the touch untouched,
/// so lifting still fires the ordinary tap.
enum LongPressOutcome { ignored, fired, holding }

abstract class GestureSink {
  /// The first finger of a gesture touched down.
  void gestureStart() {}

  /// A discrete tap of [slot] (one/two/three/fourFingerTap).
  ///
  /// [at] is the gesture's **anchor**: where the finger that *completed* the
  /// gesture landed (the 2nd finger of a two-finger tap, the 3rd of a three…).
  /// It is deliberately not the lift point — with multiple fingers, and
  /// especially with `earlyTap`, which finger lifts first is arbitrary, so a
  /// lift-derived point makes Touch mode click somewhere unpredictable.
  void tap(GestureSlot slot, Offset at);

  /// The one-finger long-press [slot] fired at the anchor [at]. Return
  /// [LongPressOutcome.holding] to begin a *held* button — then moves come via
  /// [holdDrag] and the lift via [holdEnd].
  LongPressOutcome longPress(GestureSlot slot, Offset at);

  /// While a long-press hold is active, the finger moved to [absPos] (by [delta]).
  void holdDrag(Offset absPos, Offset delta) {}

  /// The held button is released.
  void holdEnd() {}

  /// A continuous (per-frame) drag/pinch of [slot] — geometry for whichever fits.
  void continuous(GestureSlot slot,
      {Offset delta = Offset.zero,
      Offset absPos = Offset.zero,
      double zoom = 1.0,
      Offset focal = Offset.zero});

  /// The whole gesture ended (all fingers up / cancelled) — reset transient state.
  void gestureEnd() {}
}

/// Raw-pointer gesture state machine, shared by Touch and Pointer modes (the mode
/// difference — absolute vs relative cursor, edge-pan — lives entirely in the
/// [GestureSink], so this recognition logic is written once). Fed pointer events
/// by a [Listener]; emits decisions to [sink]. See DESIGN.md §4.2.
///
/// Timeline: down (count fingers, arm long-press) → move (past slop ⇒ drag; by
/// finger count ⇒ 1-finger cursor / 2-finger classify+apply / 3+ track-only) →
/// long-press timer (hold) → up (fire the tap if it was clean).
class GestureEngine {
  GestureEngine({required this.tuning, required this.sink});

  /// Live tuning — the settings test area swaps this as sliders move.
  GestureTuning tuning;
  final GestureSink sink;

  final Map<int, _Finger> _fingers = {};
  int _maxFingers = 0;

  /// Where the most recently landed finger touched down — the gesture's anchor.
  ///
  /// The *last* finger, not the first: the finger that completes a two-finger
  /// tap is the one the user is aiming with (the first is already resting), and
  /// it is fixed the moment that finger lands, so it is independent of lift
  /// order and of `earlyTap`.
  Offset _anchor = Offset.zero;
  DateTime _downAt = DateTime.now();
  bool _moved = false;
  bool _lpFired = false;
  bool _holding = false;
  bool _consumed = false; // a tap already fired (early-tap guards re-fire)
  Timer? _lpTimer;

  // Two-finger state.
  TwoFingerKind _twoKind = TwoFingerKind.undecided;
  DateTime _twoAt = DateTime.now();
  double _startDist = 0, _lastDist = 0;
  Offset _startA = Offset.zero, _startB = Offset.zero;
  Offset _startMid = Offset.zero, _lastMid = Offset.zero;
  Offset _lastCentroid = Offset.zero;
  double _travel = 0, _maxZoomDev = 0;

  int get fingerCount => _fingers.length;

  // ---- pointer events -------------------------------------------------------

  void down(int id, Offset pos) {
    _fingers[id] = _Finger(pos);
    if (_fingers.length > _maxFingers) _maxFingers = _fingers.length;
    // Every new finger re-anchors: a two-finger tap acts where the *second*
    // finger landed, a three-finger tap where the third did, and so on.
    _anchor = pos;

    if (_fingers.length == 1) {
      _moved = false;
      _lpFired = false;
      _consumed = false;
      _downAt = DateTime.now();
      _travel = 0;
      _maxZoomDev = 0;
      _lpTimer = Timer(tuning.longPress, _onLongPress);
      sink.gestureStart();
    } else {
      _lpTimer?.cancel();
      if (_holding) {
        sink.holdEnd(); // a held long-press escalated to multi-finger
        _holding = false;
      }
      _twoKind = TwoFingerKind.undecided;
      if (_fingers.length == 2) _baselineTwo();
    }
    _lastCentroid = _centroid();
  }

  void move(int id, Offset pos, Offset delta) {
    final f = _fingers[id];
    if (f == null) return;
    f.pos = pos;

    if (!_moved && (pos - f.down).distance > tuning.dragSlop) {
      _moved = true;
      _lpTimer?.cancel();
    }

    switch (_fingers.length) {
      case 1:
        if (_holding) {
          sink.holdDrag(pos, delta);
        } else if (_lpFired || _consumed || _maxFingers > 1) {
          // One gesture per touch sequence: a fired long-press or an already
          // consumed multi-finger tap must not let a residual finger drag the
          // cursor away.
          return;
        } else if (_moved) {
          sink.continuous(GestureSlot.oneFingerDrag, delta: delta, absPos: pos);
        }
      case 2:
        _handleTwoFinger();
      default:
        // 3+ fingers are tap-only: track centroid travel to reject a drag.
        final c = _centroid();
        _travel += (c - _lastCentroid).distance;
        _lastCentroid = c;
    }
  }

  void up(int id) => _end(id, clickable: true);
  void cancel(int id) => _end(id, clickable: false);

  void dispose() => _lpTimer?.cancel();

  // ---- internals ------------------------------------------------------------

  void _onLongPress() {
    if (_fingers.length != 1 || _moved || _holding) return;
    switch (sink.longPress(GestureSlot.oneFingerLongPress, _anchor)) {
      case LongPressOutcome.ignored:
        break; // bound to `none` — leave the touch alone so the tap still fires
      case LongPressOutcome.fired:
        _lpFired = true;
      case LongPressOutcome.holding:
        _lpFired = true;
        _holding = true;
    }
  }

  void _handleTwoFinger() {
    final (a, b) = _twoPositions();
    final dist = (a - b).distance;
    final mid = (a + b) / 2;

    // Settle window: track but apply nothing yet, so a 3rd/4th finger landing a
    // beat later isn't pre-empted by a transient two-finger zoom.
    if (DateTime.now().difference(_twoAt) < tuning.settle) {
      _lastDist = dist;
      _lastMid = mid;
      _lastCentroid = mid;
      return;
    }

    if (_twoKind == TwoFingerKind.undecided) {
      _twoKind = classifyTwoFinger(
        startA: _startA,
        startB: _startB,
        a: a,
        b: b,
        startDist: _startDist,
        startCentroid: _startMid,
        zoomActivate: tuning.zoomActivate,
        dragSlop: tuning.dragSlop,
      );
    }

    final dMid = mid - _lastMid;
    _travel += dMid.distance;
    switch (_twoKind) {
      case TwoFingerKind.pinch:
        final dev = _startDist == 0 ? 0.0 : (dist / _startDist - 1).abs();
        if (dev > _maxZoomDev) _maxZoomDev = dev;
        sink.continuous(GestureSlot.twoFingerPinch,
            zoom: _lastDist == 0 ? 1.0 : dist / _lastDist, focal: mid);
      case TwoFingerKind.pan:
        sink.continuous(GestureSlot.twoFingerDragH, delta: dMid);
      case TwoFingerKind.scroll:
        sink.continuous(GestureSlot.twoFingerDragV, delta: dMid);
      case TwoFingerKind.undecided:
        break;
    }
    _lastDist = dist;
    _lastMid = mid;
    _lastCentroid = mid;
  }

  void _end(int id, {required bool clickable}) {
    final wasHold = _holding;
    final wasLp = _lpFired;
    _fingers.remove(id);
    _lpTimer?.cancel();
    if (_holding) {
      sink.holdEnd();
      _holding = false;
    }

    final allUp = _fingers.isEmpty;
    // Fire the tap when every finger is up, or — if early-tap is on — the moment
    // the first finger lifts (the gesture is already decided by then).
    if (clickable &&
        !_consumed &&
        !_moved &&
        !wasHold &&
        !wasLp &&
        (tuning.earlyTap || allUp)) {
      if (_fireTap()) _consumed = true;
    }

    if (!allUp) {
      _lastCentroid = _centroid();
      if (_fingers.length == 2) _baselineTwo(); // re-baseline on 3→2
      return;
    }
    sink.gestureEnd();
    _reset();
  }

  /// Emit the tap for the peak finger count, always at the stable [_anchor].
  /// One-finger taps always fire; multi-finger taps must be "clean" (little
  /// travel/zoom, never classified as a drag) and land inside the multi-finger
  /// window. Returns whether a tap was emitted.
  ///
  /// That window runs from the first finger's touch-down until the long-press
  /// would have fired: everything before the long press *is* the multi-finger
  /// trigger period. (A second finger cancels the long-press timer, so the two
  /// can never both happen.) It is deliberately the same rule in both modes.
  bool _fireTap() {
    if (_maxFingers == 1) {
      sink.tap(GestureSlot.oneFingerTap, _anchor);
      return true;
    }
    // 5+ fingers is a palm, not a gesture — don't fold it into the 4-finger tap.
    if (_maxFingers > 4) return false;
    final clean = _travel < tuning.tapSlop &&
        _maxZoomDev < 0.08 &&
        DateTime.now().difference(_downAt) < tuning.longPress &&
        _twoKind == TwoFingerKind.undecided;
    if (!clean) return false;
    sink.tap(
      switch (_maxFingers) {
        2 => GestureSlot.twoFingerTap,
        3 => GestureSlot.threeFingerTap,
        _ => GestureSlot.fourFingerTap,
      },
      _anchor,
    );
    return true;
  }

  void _baselineTwo() {
    _twoAt = DateTime.now();
    final (a, b) = _twoPositions();
    _startDist = _lastDist = (a - b).distance;
    _startA = a;
    _startB = b;
    _startMid = _lastMid = (a + b) / 2;
    _lastCentroid = _startMid;
    _twoKind = TwoFingerKind.undecided;
  }

  void _reset() {
    _maxFingers = 0;
    _anchor = Offset.zero;
    _moved = false;
    _lpFired = false;
    _consumed = false;
    _twoKind = TwoFingerKind.undecided;
    _travel = 0;
    _maxZoomDev = 0;
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
}

class _Finger {
  _Finger(this.down) : pos = down;
  final Offset down;
  Offset pos;
}
