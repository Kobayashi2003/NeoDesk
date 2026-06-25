import 'package:flutter/widgets.dart';

/// Live read+write access to the remote canvas transform (pan / zoom), so the
/// gesture layer can convert screen<->image coordinates correctly under any
/// zoom/pan and drive navigation. See DESIGN.md §1 / §5.
///
/// When null, the gesture layer reads/writes the demo's local
/// [SessionController.canvas] (FakeCore). The real app sets this to a control
/// backed by RustDesk's `CanvasModel` (scale/x/y + panX/panY/updateScale).
abstract interface class NeodeskCanvasControl {
  // ---- live reads (image px / screen px) ----
  /// Uniform scale, image px -> screen px (`canvasModel.scale`).
  double get scale;

  /// Screen px of the image origin (`canvasModel.x / y`).
  double get offsetX;
  double get offsetY;

  /// Remote image native size (`canvasModel.getDisplayWidth()/Height()`).
  double get imageWidth;
  double get imageHeight;

  // ---- writes ----
  /// Pan the canvas by a screen-space delta.
  void panBy(double dx, double dy);

  /// Zoom by an incremental scale ratio around [focal] (screen-space).
  void zoomBy(double scaleRatio, Offset focal);

  /// Set the absolute transform atomically: [scale] plus the screen-px image
  /// origin ([offsetX], [offsetY]). Used by Fit, which needs an exact result —
  /// composing a relative [zoomBy] then reading [scale] back assumed the engine
  /// updated synchronously and that a follow-up [panBy] wouldn't re-clamp.
  void setTransform(double scale, double offsetX, double offsetY);

  /// Re-apply the engine's view style to the current screen size (re-fit). Used
  /// on orientation change, where the new viewport needs a fresh fit.
  void refit();
}

NeodeskCanvasControl? neodeskCanvasOverride;
