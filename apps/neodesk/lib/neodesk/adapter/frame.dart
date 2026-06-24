part of '../adapter.dart';

class _RustdeskFrameSource implements nd.FrameSource {
  _RustdeskFrameSource() {
    gFFI.canvasModel.addListener(_onCanvas);
    gFFI.imageModel.addListener(_onImage);
  }

  final _transform = StreamController<nd.CanvasTransform>.broadcast();
  final _onFrame = StreamController<void>.broadcast();

  void _onCanvas() {
    final c = gFFI.canvasModel;
    if (!_transform.isClosed) {
      _transform.add(nd.CanvasTransform(
          offsetX: c.x, offsetY: c.y, scale: c.scale));
    }
  }

  void _onImage() {
    if (!_onFrame.isClosed) _onFrame.add(null);
  }

  @override
  nd.DisplayGeometry get displayGeometry => nd.DisplayGeometry(
        width: gFFI.canvasModel.getDisplayWidth(),
        height: gFFI.canvasModel.getDisplayHeight(),
      );

  @override
  Stream<nd.CanvasTransform> get transform => _transform.stream;

  @override
  Stream<void> get onFrame => _onFrame.stream;

  @override
  bool get hasFirstFrame => !gFFI.ffiModel.waitForFirstImage.value;
}

