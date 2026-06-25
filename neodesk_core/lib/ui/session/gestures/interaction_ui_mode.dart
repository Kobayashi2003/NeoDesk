/// The UI-level operation modes. See DESIGN.md.
///
/// A *UI* concept that does not change lib/core — each value decides which
/// `InputSink` primitives a gesture produces (absolute vs relative).
enum InteractionUiMode {
  /// Absolute positioning: the finger's landing point is where you click.
  touch,

  /// Relative trackpad: the screen is a touchpad that moves the remote pointer,
  /// with gesture-based clicks (RustDesk/Moonlight style).
  pointer,
}

extension InteractionUiModeX on InteractionUiMode {
  String get label => switch (this) {
        InteractionUiMode.touch => 'Touch',
        InteractionUiMode.pointer => 'Pointer',
      };

  String get description => switch (this) {
        InteractionUiMode.touch => 'Tap where you want to click',
        InteractionUiMode.pointer =>
          'Full-screen trackpad: drag to move the pointer, gestures to click',
      };

  /// Persistence key value.
  String get storageKey => name;

  /// The default mode when nothing is stored yet.
  static const InteractionUiMode defaultMode = InteractionUiMode.pointer;

  static InteractionUiMode fromStorage(String? v) =>
      InteractionUiMode.values.firstWhere(
        (m) => m.name == v,
        orElse: () => defaultMode,
      );
}
