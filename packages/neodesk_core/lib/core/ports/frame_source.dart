import '../types/display_info.dart';

/// Source of decoded remote frames + view geometry for the rendering layer.
///
/// Abstracts RustDesk's `ImageModel` / `CanvasModel` / `TextureModel`
/// (`flutter/lib/models/model.dart`). The actual pixel transport (RGBA buffer
/// or GPU texture) stays inside the adapter — this port only surfaces what a
/// painter/Texture widget needs to draw and place the image.
///
/// NOTE: This is RustDesk's performance-critical path. The redesign should
/// REUSE the implementation behind this port verbatim and only build new
/// chrome/gestures around it.
abstract interface class FrameSource {
  /// Geometry of the currently active remote display.
  DisplayGeometry get displayGeometry;

  /// Current local view transform (pan/zoom) of the remote image.
  Stream<CanvasTransform> get transform;

  /// Fires whenever a new frame has been committed and the canvas should
  /// repaint. (Wraps the `notifyListeners()` cadence of ImageModel.)
  Stream<void> get onFrame;

  /// True once the first image has arrived (mirrors
  /// `ffiModel.waitForFirstImage` flipping to false).
  bool get hasFirstFrame;
}
