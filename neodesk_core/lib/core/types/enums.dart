/// Enumerations mirrored from RustDesk's core, kept UI-agnostic.
library;

/// Connection kind. Mirrors RustDesk `ConnType`
/// (`flutter/lib/models/model.dart`). Only the subset a mobile client needs.
enum ConnKind {
  remoteControl, // ConnType.defaultConn
  fileTransfer, // ConnType.fileTransfer
  viewCamera, // ConnType.viewCamera
  portForward, // ConnType.portForward
  terminal, // ConnType.terminal
}

/// Connection lifecycle phases surfaced to the UI. Derived from RustDesk state
/// in `FfiModel` (pi.isSet, waitForFirstImage, closed, ...).
enum SessionPhase {
  idle,
  connecting,
  authenticating,
  waitingFirstImage,
  connected,
  closed,
  error,
}

/// Pointer buttons. Mirrors RustDesk `MouseButtons` constants
/// (`flutter/lib/models/input_model.dart`).
enum MouseButton { left, right, middle }

/// Mouse event phase passed to [InputSink.sendMouse].
/// Mirrors the string `type` argument ("down"/"up"/"move") used by
/// `InputModel.sendMouse(String type, MouseButtons button)`.
enum MousePhase { down, up, move }

/// Hardware/system buttons available when the controlled peer is Android.
/// Mirrors `InputModel.onMobileBack/Home/Apps/VolumeUp/VolumeDown/Power`.
enum AndroidSystemAction { back, home, recents, volumeUp, volumeDown, power }
