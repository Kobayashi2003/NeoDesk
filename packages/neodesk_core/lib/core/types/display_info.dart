/// Geometry of the remote display / canvas.
///
/// Corresponds to the values RustDesk's `CanvasModel` + `Display`
/// (`flutter/lib/models/model.dart`) expose to the painting layer.
/// Kept as plain data so a new rendering widget can bind to it directly.
class DisplayGeometry {
  /// Native pixel size of the remote display.
  final int width;
  final int height;

  /// Top-left offset of the display inside a multi-monitor virtual desktop.
  final int x;
  final int y;

  const DisplayGeometry({
    required this.width,
    required this.height,
    this.x = 0,
    this.y = 0,
  });

  static const zero = DisplayGeometry(width: 0, height: 0);
}

/// Current view transform applied to the remote image on the local canvas.
/// Mirrors `CanvasModel.x / y / scale`.
class CanvasTransform {
  final double offsetX;
  final double offsetY;
  final double scale;

  const CanvasTransform({
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
  });
}
