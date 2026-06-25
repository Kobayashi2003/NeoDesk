import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/ui/session/gestures/gesture_classify.dart';

void main() {
  // Shared thresholds (mirror the pads' constants).
  const zoom = 24.0;
  const slop = 10.0;

  TwoFingerKind run({
    required Offset a0,
    required Offset b0,
    required Offset a1,
    required Offset b1,
  }) =>
      classifyTwoFinger(
        startA: a0,
        startB: b0,
        a: a1,
        b: b1,
        startDist: (a0 - b0).distance,
        startCentroid: (a0 + b0) / 2,
        zoomActivate: zoom,
        dragSlop: slop,
      );

  group('classifyTwoFinger', () {
    test('no movement → undecided', () {
      expect(
        run(
            a0: const Offset(0, 0),
            b0: const Offset(100, 0),
            a1: const Offset(0, 0),
            b1: const Offset(100, 0)),
        TwoFingerKind.undecided,
      );
    });

    test('fingers spread apart → pinch', () {
      // a moves left, b moves right (opposite) → spacing grows.
      expect(
        run(
            a0: const Offset(40, 0),
            b0: const Offset(60, 0),
            a1: const Offset(0, 0),
            b1: const Offset(100, 0)),
        TwoFingerKind.pinch,
      );
    });

    test('pinch that also drifts the centroid is still a pinch', () {
      // Spread grows AND the whole thing slides right — the old "first threshold
      // wins" logic would have called this a pan; relative motion keeps it pinch.
      expect(
        run(
            a0: const Offset(40, 0),
            b0: const Offset(60, 0),
            a1: const Offset(20, 0), // a -20
            b1: const Offset(120, 0)), // b +60 → centroid drifts +20, spread +60
        TwoFingerKind.pinch,
      );
    });

    test('both fingers slide right together → pan', () {
      expect(
        run(
            a0: const Offset(0, 0),
            b0: const Offset(100, 0),
            a1: const Offset(40, 0),
            b1: const Offset(140, 0)),
        TwoFingerKind.pan,
      );
    });

    test('both fingers slide down together → scroll', () {
      expect(
        run(
            a0: const Offset(0, 0),
            b0: const Offset(100, 0),
            a1: const Offset(0, 40),
            b1: const Offset(100, 40)),
        TwoFingerKind.scroll,
      );
    });
  });
}
