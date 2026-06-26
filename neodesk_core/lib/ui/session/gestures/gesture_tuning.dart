/// Shared interaction-timing constants for the gesture pads.
///
/// These were duplicated as private `_longPress` consts in both pointer_pad and
/// touch_pad (so a tweak meant editing two files in lock-step). Centralised here
/// as the single source of truth for gesture timing.
library;

/// How long a finger must stay down (without moving past the drag slop) to count
/// as a long-press rather than a tap.
const Duration kLongPressDuration = Duration(milliseconds: 500);

/// Max gap between taps for them to be treated as a multi-tap (double/triple).
const Duration kMultiTapTimeout = Duration(milliseconds: 250);

/// Settle window after a 2-finger gesture begins, during which two-finger
/// continuous actions (pinch/pan/scroll) are withheld. Fingers in a 3-/4-finger
/// gesture don't all land at once, so without this the brief 2-finger phase
/// fires a zoom and blocks the intended multi-finger action. A 3rd/4th finger
/// arriving within this window pre-empts the two-finger gesture cleanly.
const Duration kMultiTouchSettle = Duration(milliseconds: 80);
