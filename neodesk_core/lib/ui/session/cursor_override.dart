/// Injection point so the real-engine integration can drive the actual remote
/// cursor (RustDesk's `CursorModel`) instead of the demo's local virtual cursor.
///
/// RustDesk's `CursorModel` owns the cursor: it converts coordinates, tracks the
/// position, renders the real remote cursor and sends the move to the peer (and,
/// for relative moves, auto-pans the canvas at the edges). Routing through it is
/// the only way the on-screen remote cursor actually tracks.
///
/// When null, the gesture layer falls back to the FakeCore path: it does its own
/// screen<->image conversion and moves a local virtual cursor.
abstract interface class NeodeskCursorControl {
  /// Touch mode: place the cursor under the given screen point (absolute).
  /// Returns whether the cursor was actually moved — the engine refuses the move
  /// (returning false) until its display/canvas geometry is ready, so callers
  /// that must land it (e.g. centring on connect) can retry instead of assuming
  /// success.
  Future<bool> moveTo(double screenX, double screenY);

  /// Pointer mode: move the cursor by a screen-space delta (relative trackpad).
  /// The real engine also auto-pans the canvas when the cursor reaches an edge.
  void moveBy(double screenDx, double screenDy);
}

NeodeskCursorControl? neodeskCursorOverride;

/// Whether the real engine should paint the streamed remote cursor. Mirrors the
/// user's "Hide remote cursor" setting; [SessionController] sets it once at
/// session start so the per-frame cursor paint reads a cheap bool instead of an
/// FFI config lookup. Defaults to shown.
bool neodeskShowRemoteCursor = true;
