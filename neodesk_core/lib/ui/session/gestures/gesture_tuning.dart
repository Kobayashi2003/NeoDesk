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
