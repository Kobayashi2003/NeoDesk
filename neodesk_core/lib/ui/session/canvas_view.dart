import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Immutable snapshot of the live canvas transform, plus the only correct
/// screen<->image coordinate mappings. See DESIGN.md §1 / §5.
///
/// Every gesture that needs a remote coordinate MUST go through this — never
/// assume `screen == image`. Built fresh each gesture frame from either the
/// real engine's `CanvasModel` (via [NeodeskCanvasControl]) or the FakeCore
/// demo's local transform.
@immutable
class CanvasView {
  const CanvasView({
    required this.s,
    required this.ox,
    required this.oy,
    required this.w,
    required this.h,
    required this.vw,
    required this.vh,
  });

  /// Uniform scale: image px -> screen px.
  final double s;

  /// Canvas offset: screen px of the image origin (0,0).
  final double ox;
  final double oy;

  /// Remote image native size (px).
  final double w;
  final double h;

  /// Viewport (gesture surface) size (px).
  final double vw;
  final double vh;

  bool get isValid => s > 0 && w > 0 && h > 0;

  /// Screen point -> image point, clamped to the image bounds.
  Offset screenToImage(Offset p) => Offset(
        ((p.dx - ox) / s).clamp(0.0, w),
        ((p.dy - oy) / s).clamp(0.0, h),
      );

  /// Image point -> screen point.
  Offset imageToScreen(Offset p) => Offset(ox + p.dx * s, oy + p.dy * s);

  /// Fit scale: whole image visible. Lower bound for zoom (§1.2).
  double get fitScale =>
      (w <= 0 || h <= 0 || vw <= 0 || vh <= 0) ? 1.0 : math.min(vw / w, vh / h);

  /// Clamp a candidate offset so the image always fills (or is centred in) the
  /// viewport and can't be flung off-screen (§1.4). Returns the clamped offset
  /// for the given [scale].
  Offset clampOffset(double nox, double noy, double scale) {
    final iw = w * scale;
    final ih = h * scale;
    double cx;
    if (iw <= vw) {
      cx = (vw - iw) / 2; // centre when narrower than viewport
    } else {
      cx = nox.clamp(vw - iw, 0.0);
    }
    double cy;
    if (ih <= vh) {
      cy = (vh - ih) / 2;
    } else {
      cy = noy.clamp(vh - ih, 0.0);
    }
    return Offset(cx, cy);
  }
}
