import 'dart:async';

import 'package:flutter/widgets.dart';

import 'gesture_classify.dart';
import 'gesture_map.dart';
import 'gesture_tuning.dart';

/// What the sink did with a long-press. [ignored] (the slot is bound to `none`)
/// leaves the touch untouched, so lifting still fires the ordinary tap.
enum LongPressOutcome { ignored, fired, holding }

/// Where a recognised gesture goes. The engine only *detects* gestures (which
/// [GestureSlot] fired, plus the geometry); the sink decides what to *do* — in a
/// real session that's cursor/click/scroll via the controller (mode-aware), in
/// the settings test area it's just a readout. This split lets both reuse the
/// exact same recognition logic. See DESIGN.md §4.2.
abstract class GestureSink {
  /// The first finger of a gesture touched down.
  void gestureStart() {}

  /// A discrete tap of [slot] at the gesture's anchor [at].
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
/// A touch sequence has two deadlines, both measured from the first finger's
/// touch-down:
///  1. the **long-press deadline** ([GestureTuning.longPressMs]) — everything
///     before it is the multi-finger trigger period: a finger landing then joins
///     the gesture and re-fixes [_anchor], and lifting then fires the tap for
///     the collected count. It is also the instant a one-finger long press
///     buzzes; a second finger cancels that timer, so a multi-finger gesture
///     never buzzes. A finger landing *after* it voids the tap.
///  2. the **collection window** ([GestureTuning.collectMs]), a shorter one —
///     two-finger continuous actions are withheld while it is open, so a 3rd or
///     4th finger arriving a beat later can still pre-empt a scroll or pinch.
class GestureEngine {
  GestureEngine({required this.tuning, required this.sink});

  /// Live tuning — the settings test area swaps this as sliders move.
  GestureTuning tuning;
  final GestureSink sink;

  final Map<int, _Finger> _fingers = {};
  int _maxFingers = 0;

  /// Where the finger that *completed* the gesture landed (the 2nd finger of a
  /// two-finger tap, the 3rd of a three…). Fixed when that finger lands, so it
  /// is independent of lift order and of `earlyTap` — unlike a lift point, which
  /// would make Touch mode click somewhere unpredictable.
  Offset _anchor = Offset.zero;
  DateTime _downAt = DateTime.now();
  bool _moved = false;
  bool _lpFired = false;
  bool _holding = false;
  bool _consumed = false; // a tap already fired (early-tap guards re-fire)
  bool _lateFinger = false; // landed after the long-press deadline
  bool _cancelled = false; // a pointer was cancelled: the sequence is void
  Timer? _lpTimer;

  // Two-finger state.
  TwoFingerKind _twoKind = TwoFingerKind.undecided;
  double _startDist = 0, _lastDist = 0;
  Offset _startA = Offset.zero, _startB = Offset.zero;
  Offset _startMid = Offset.zero, _lastMid = Offset.zero;
  Offset _lastCentroid = Offset.zero;
  double _travel = 0, _maxZoomDev = 0;

  int get fingerCount => _fingers.length;

  // ---- pointer events -------------------------------------------------------

  void down(int id, Offset pos) {
    final isFirst = _fingers.isEmpty;
    _fingers[id] = _Finger(pos);

    if (isFirst) {
      _reset();
      _downAt = DateTime.now();
      _maxFingers = 1;
      _anchor = pos;
      _lpTimer = Timer(tuning.longPress, _onLongPress);
      sink.gestureStart();
    } else {
      _lpTimer?.cancel();
      if (_holding) {
        sink.holdEnd(); // a held long-press escalated to multi-finger
        _holding = false;
      }
      _twoKind = TwoFingerKind.undecided;
      if (_accepting) {
        if (_fingers.length > _maxFingers) _maxFingers = _fingers.length;
        _anchor = pos;
      } else {
        _lateFinger = true;
      }
      if (_fingers.length == 2) _baselineTwo();
    }
    _lastCentroid = _centroid();
  }

  void move(int id, Offset pos, Offset delta) {
    final f = _fingers[id];
    if (f == null) return;
    f.pos = pos;

    if (!_moved && (pos - f.start).distance > tuning.dragSlop) {
      _moved = true;
      _lpTimer?.cancel();
    }

    if (_holding) {
      sink.holdDrag(pos, delta); // a hold only ever has one finger
      return;
    }
    // One gesture per touch sequence. Once a tap has fired — which with
    // `earlyTap` happens while later fingers are still down — or a discrete
    // long-press has, no residual finger may drive anything else.
    if (_consumed || _lpFired) return;

    switch (_fingers.length) {
      case 1:
        if (_maxFingers == 1 && _moved) {
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

  /// The platform took the pointer away (gesture arena, backgrounding). Void the
  /// whole sequence, not just this finger: the fingers still down did not agree
  /// to anything, so lifting them must not fire a tap.
  void cancel(int id) {
    _cancelled = true;
    _end(id, clickable: false);
  }

  void dispose() {
    _lpTimer?.cancel();
    if (_holding) {
      sink.holdEnd(); // else the peer's mouse button stays pressed
      _holding = false;
    }
  }

  // ---- internals ------------------------------------------------------------

  /// Spread change (as a fraction of the fingers' initial distance) that a
  /// multi-finger tap may still show before it reads as a pinch.
  static const _tapSpreadTolerance = 0.08;

  Duration get _elapsed => DateTime.now().difference(_downAt);

  /// Inside the multi-finger trigger period: the gesture still takes new fingers
  /// and a lift still fires a tap. Past it the touch is a long press (or
  /// nothing), and a finger landing then voids the tap rather than silently
  /// degrading it — a two-finger press must never fire a one-finger click.
  bool get _accepting => _elapsed < tuning.longPress;

  /// Two-finger continuous actions are still withheld, so a 3rd/4th finger can
  /// pre-empt them. Never outlives the deadline (the sliders do allow
  /// `collectMs > longPressMs`).
  bool get _collecting => _elapsed < tuning.collect && _accepting;

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
    final dMid = mid - _lastMid;

    // Accumulate even while withheld, or a fast two-finger swipe that ends
    // inside the collection window would look perfectly still to [_fireTap].
    _travel += dMid.distance;
    final spreadDev = _startDist == 0 ? 0.0 : (dist / _startDist - 1).abs();
    if (spreadDev > _maxZoomDev) _maxZoomDev = spreadDev;

    if (!_collecting) {
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
      switch (_twoKind) {
        case TwoFingerKind.pinch:
          sink.continuous(GestureSlot.twoFingerPinch,
              zoom: _lastDist == 0 ? 1.0 : dist / _lastDist, focal: mid);
        case TwoFingerKind.pan:
          sink.continuous(GestureSlot.twoFingerDragH, delta: dMid);
        case TwoFingerKind.scroll:
          sink.continuous(GestureSlot.twoFingerDragV, delta: dMid);
        case TwoFingerKind.undecided:
          break;
      }
    }
    _lastDist = dist;
    _lastMid = mid;
    _lastCentroid = mid;
  }

  void _end(int id, {required bool clickable}) {
    // Read before the lift mutates anything. A long press consumes the touch
    // whether it merely fired or went on to hold, so `_lpFired` covers both.
    final spent = _consumed || _cancelled || _lateFinger || _lpFired;
    _fingers.remove(id);
    _lpTimer?.cancel();
    if (_holding) {
      sink.holdEnd();
      _holding = false;
    }

    final allUp = _fingers.isEmpty;
    // Fire when every finger is up, or — with early-tap — the moment the first
    // lifts (the gesture is already decided by then). [_moved] vetoes only a
    // *one-finger* tap: fingers routinely roll past dragSlop as a multi-finger
    // tap lands, and whether that became a drag is [_fireTap]'s call.
    if (clickable &&
        !spent &&
        (_maxFingers > 1 || !_moved) &&
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

  /// Emit the tap for the collected finger count, at [_anchor]. One-finger taps
  /// always fire; a multi-finger tap must also be "clean" — little centroid
  /// travel, little spread change, never classified as a drag/pinch, and lifted
  /// before the long-press deadline. Identical in both interaction modes.
  bool _fireTap() {
    if (_maxFingers == 1) {
      sink.tap(GestureSlot.oneFingerTap, _anchor);
      return true;
    }
    if (_maxFingers > 4) return false; // a palm, not a gesture
    final clean = _travel < tuning.tapSlop &&
        _maxZoomDev < _tapSpreadTolerance &&
        _accepting &&
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
    _lateFinger = false;
    _cancelled = false;
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
  _Finger(this.start) : pos = start;

  /// Where this finger landed; [pos] is where it is now.
  final Offset start;
  Offset pos;
}
