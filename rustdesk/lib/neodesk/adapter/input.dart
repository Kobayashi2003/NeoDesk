part of '../adapter.dart';

class _RustdeskInputSink implements nd.InputSink {
  InputModel get _im => gFFI.inputModel;

  MouseButtons _mb(nd.MouseButton b) => switch (b) {
        nd.MouseButton.left => MouseButtons.left,
        nd.MouseButton.right => MouseButtons.right,
        nd.MouseButton.middle => MouseButtons.wheel,
      };

  String _phase(nd.MousePhase p) => switch (p) {
        nd.MousePhase.down => 'down',
        nd.MousePhase.up => 'up',
        nd.MousePhase.move => 'move',
      };

  // View-only blocks all input. The engine guards mouse/scroll, but inputKey and
  // sessionInputString do NOT — so gate everything here for consistency.
  bool get _viewOnly => gFFI.ffiModel.viewOnly;

  @override
  Future<void> tap(nd.MouseButton button) async {
    if (_viewOnly) return;
    await _im.tap(_mb(button));
  }

  @override
  Future<void> pointerDown(nd.MouseButton button) async {
    if (_viewOnly) return;
    await _im.tapDown(_mb(button));
  }

  @override
  Future<void> pointerUp(nd.MouseButton button) async {
    if (_viewOnly) return;
    await _im.tapUp(_mb(button));
  }

  @override
  Future<void> sendMouse(nd.MousePhase phase, nd.MouseButton button) async {
    if (_viewOnly) return;
    await _im.sendMouse(_phase(phase), _mb(button));
  }

  @override
  Future<void> moveTo(double x, double y) async {
    if (_viewOnly) return;
    await _im.moveMouse(x, y);
  }

  @override
  Future<void> moveBy(double dx, double dy) async {
    if (_viewOnly) return;
    await _im.sendMobileRelativeMouseMove(dx, dy);
  }

  @override
  Future<void> scroll(int y) async {
    if (_viewOnly) return;
    await _im.scroll(y);
  }

  @override
  Future<void> key(String name, {bool? down, bool? press}) async {
    if (_viewOnly) return;
    _im.inputKey(name, down: down, press: press);
  }

  @override
  Future<void> setModifiers({
    bool? ctrl,
    bool? alt,
    bool? shift,
    bool? meta,
  }) async {
    if (ctrl != null) _im.ctrl = ctrl;
    if (alt != null) _im.alt = alt;
    if (shift != null) _im.shift = shift;
    if (meta != null) _im.command = meta;
  }

  @override
  Future<void> text(String value) async {
    if (_viewOnly) return;
    await bind.sessionInputString(sessionId: gFFI.sessionId, value: value);
  }

  @override
  Future<void> androidAction(nd.AndroidSystemAction action) async {
    if (_viewOnly) return;
    switch (action) {
      case nd.AndroidSystemAction.back:
        _im.onMobileBack();
      case nd.AndroidSystemAction.home:
        _im.onMobileHome();
      case nd.AndroidSystemAction.recents:
        await _im.onMobileApps();
      case nd.AndroidSystemAction.volumeUp:
        await _im.onMobileVolumeUp();
      case nd.AndroidSystemAction.volumeDown:
        await _im.onMobileVolumeDown();
      case nd.AndroidSystemAction.power:
        await _im.onMobilePower();
    }
  }
}
