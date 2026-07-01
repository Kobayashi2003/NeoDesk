/// Injection seam so the real engine can drive the actual remote cursor
/// (RustDesk's `CursorModel`) instead of the demo's local virtual cursor.
///
/// `CursorModel` owns the cursor — converting coordinates, rendering the streamed
/// cursor, sending moves to the peer, edge-panning on relative moves — so routing
/// through it is the only way the on-screen cursor tracks. When null, the gesture
/// layer falls back to the FakeCore path (its own conversion + virtual cursor).
library;

import 'package:flutter/widgets.dart' show Offset;

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

  /// The cursor's current position in **image** coordinates, or null if the
  /// engine isn't tracking one yet. Lets the view keep the cursor on-screen as
  /// the canvas zooms (a zoom moves the cursor's *screen* position even though
  /// its image position is unchanged).
  Offset? get imagePosition;
}

NeodeskCursorControl? neodeskCursorOverride;

/// Whether the real engine should paint the streamed remote cursor. Mirrors the
/// user's "Hide remote cursor" setting; [SessionController] sets it once at
/// session start so the per-frame cursor paint reads a cheap bool instead of an
/// FFI config lookup. Defaults to shown.
bool neodeskShowRemoteCursor = true;
