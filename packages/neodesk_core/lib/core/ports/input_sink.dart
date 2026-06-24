import '../types/enums.dart';

/// The destination for all input the user generates.
///
/// Exposes the primitive operations RustDesk's `InputModel`
/// (`flutter/lib/models/input_model.dart`) sends to the peer — but NOT the
/// gesture-to-primitive mapping: the gesture layer decides which primitives a
/// given touch produces. Implemented by the adapter (`adapter/input.dart`).
abstract interface class InputSink {
  // --- Pointer ----------------------------------------------------------
  /// Full click. Wraps `InputModel.tap(button)`.
  Future<void> tap(MouseButton button);

  /// Press without release. Wraps `InputModel.tapDown(button)`.
  Future<void> pointerDown(MouseButton button);

  /// Release. Wraps `InputModel.tapUp(button)`.
  Future<void> pointerUp(MouseButton button);

  /// Low-level phased mouse event. Wraps
  /// `InputModel.sendMouse(type, button)`.
  Future<void> sendMouse(MousePhase phase, MouseButton button);

  /// Absolute move to image coordinates. Wraps `InputModel.moveMouse(x, y)`.
  Future<void> moveTo(double x, double y);

  /// Relative move (trackpad style). Wraps
  /// `InputModel.sendMobileRelativeMouseMove(dx, dy)`.
  Future<void> moveBy(double dx, double dy);

  /// Vertical wheel. Wraps `InputModel.scroll(y)`.
  Future<void> scroll(int y);

  // --- Keyboard ---------------------------------------------------------
  /// Named key. Wraps `InputModel.inputKey(name, down:, press:)`. Names are the
  /// engine's `VK_*` tokens (e.g. `VK_ESCAPE`, `VK_LEFT`, `VK_F1`, `VK_SPACE`)
  /// or a single literal character for ordinary text.
  Future<void> key(String name, {bool? down, bool? press});

  /// Set the engine's persistent modifier flags, which it applies to every
  /// subsequent [key]. This — not separate modifier key events — is how the
  /// engine composes shortcuts (wraps `InputModel.ctrl/alt/shift/command`). Pass
  /// only the flags you want to change.
  Future<void> setModifiers({bool? ctrl, bool? alt, bool? shift, bool? meta});

  /// Commit a literal string to the peer in one shot — used for IME-composed /
  /// CJK text, where per-character key events would arrive out of order. Wraps
  /// `bind.sessionInputString`.
  Future<void> text(String value);

  // --- Android peer system buttons -------------------------------------
  /// Wraps `InputModel.onMobileBack/Home/Apps/VolumeUp/VolumeDown/Power`.
  Future<void> androidAction(AndroidSystemAction action);
}
