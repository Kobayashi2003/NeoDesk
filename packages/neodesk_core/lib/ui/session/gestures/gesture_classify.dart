import 'dart:ui';

/// The outcome of classifying a two-finger gesture (shared by both input pads).
enum TwoFingerKind { undecided, pinch, pan, scroll }

/// Classifies a two-finger gesture from how the two fingers have moved since it
/// began. Returns [TwoFingerKind.undecided] until there is enough movement to be
/// sure.
///
/// The key idea: don't pick "whichever threshold is crossed first" — pinching
/// always drifts the centroid, so the pan threshold tends to win and a zoom is
/// mis-read as a pan. Instead look at how the fingers move *relative to each
/// other*: a pinch moves them in opposite directions (negative dot product),
/// while a pan/scroll translates them together. It is only a pan/scroll when the
/// fingers clearly move together AND that translation outweighs the change in
/// finger spacing; otherwise it is a pinch.
TwoFingerKind classifyTwoFinger({
  required Offset startA,
  required Offset startB,
  required Offset a,
  required Offset b,
  required double startDist,
  required Offset startCentroid,
  required double zoomActivate, // spread (px) that counts as a real pinch
  required double dragSlop, // centroid travel (px) that counts as a real drag
}) {
  final spread = ((a - b).distance - startDist).abs();
  final pan = (a + b) / 2 - startCentroid;
  if (spread <= zoomActivate && pan.distance <= dragSlop) {
    return TwoFingerKind.undecided;
  }
  final da = a - startA;
  final db = b - startB;
  final together = (da.dx * db.dx + da.dy * db.dy) > 0; // same direction
  if (together && pan.distance >= spread) {
    return pan.dx.abs() >= pan.dy.abs()
        ? TwoFingerKind.pan
        : TwoFingerKind.scroll;
  }
  return TwoFingerKind.pinch;
}
