part of '../adapter.dart';

class _RustdeskSessionFactory implements nd.RemoteSessionFactory {
  _RustdeskRemoteSession? _current;

  @override
  nd.RemoteSession create({nd.SessionId? sessionId}) {
    // Mobile uses the single global gFFI; reuse one wrapper.
    return _current ??= _RustdeskRemoteSession();
  }
}

class _RustdeskRemoteSession implements nd.RemoteSession {
  _RustdeskRemoteSession()
      : frameSource = _RustdeskFrameSource(),
        inputSink = _RustdeskInputSink();

  final _RustdeskFrameSource frameSource;
  final _RustdeskInputSink inputSink;

  final _phase = StreamController<nd.SessionPhase>.broadcast();
  final _peerInfo = StreamController<nd.PeerRuntimeInfo>.broadcast();

  final List<Worker> _workers = [];
  bool _started = false;
  bool _closed = false;
  bool _relativeEnabled = false;
  nd.SessionPhase _last = nd.SessionPhase.idle;

  FfiModel get _m => gFFI.ffiModel;

  @override
  nd.SessionId get sessionId => gFFI.sessionId.toString();

  @override
  Stream<nd.SessionPhase> get phase => _phase.stream;

  @override
  Stream<nd.PeerRuntimeInfo> get peerInfo => _peerInfo.stream;

  @override
  Future<void> connect({
    required nd.PeerId id,
    nd.ConnKind kind = nd.ConnKind.remoteControl,
    String? password,
    bool forceRelay = false,
  }) async {
    final wasStarted = _started;
    _started = true;
    _closed = false;
    _relativeEnabled = false; // re-apply relative-mouse-mode on a reconnect
    // Dispose any workers left over from a previous session that wasn't closed
    // cleanly (e.g. a forced disconnect when backgrounded, whose page popped
    // without calling close()). Otherwise they pile up and the engine session
    // stays half-open, making the first foreground connect hang.
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    _emit(nd.SessionPhase.connecting);

    // Tear down any prior engine session before starting a fresh one. A forced
    // disconnect (app backgrounded) can leave the previous session half-open on
    // the shared gFFI; without this the first foreground connect connects onto
    // that stale state and spins, while a second attempt (after more churn)
    // succeeds. Closing first guarantees a clean handshake every time.
    if (wasStarted) {
      await bind.sessionClose(sessionId: gFFI.sessionId);
    }

    // Reset the connection signals to their "connecting" baseline BEFORE start.
    // ever() only fires on a *change*, so a stale pi.isSet=true left over from a
    // previous session (same global gFFI) would mean the worker never fires and
    // we'd stay stuck on "connecting" forever — until a full exit+reconnect.
    // Forcing false here guarantees the handshake produces a false→true edge.
    _m.pi.isSet.value = false;
    _m.waitForFirstImage.value = true;

    // React to handshake / first-frame transitions.
    _workers.add(ever(_m.waitForFirstImage, (_) => _recompute()));
    _workers.add(ever(_m.pi.isSet, (_) => _recompute()));

    gFFI.ffiModel.updateEventListener(gFFI.sessionId, id);
    gFFI.start(
      id,
      isFileTransfer: kind == nd.ConnKind.fileTransfer,
      isViewCamera: kind == nd.ConnKind.viewCamera,
      isPortForward: kind == nd.ConnKind.portForward,
      isTerminal: kind == nd.ConnKind.terminal,
      password: password,
      forceRelay: forceRelay,
    );
  }

  void _recompute() {
    final nd.SessionPhase p;
    if (_closed) {
      p = nd.SessionPhase.closed;
    } else if (!_started) {
      p = nd.SessionPhase.idle;
    } else if (!_m.pi.isSet.value) {
      p = nd.SessionPhase.connecting;
    } else if (_m.waitForFirstImage.value) {
      p = nd.SessionPhase.waitingFirstImage;
    } else {
      p = nd.SessionPhase.connected;
    }
    _emit(p);
    // neodesk drives both modes with ABSOLUTE positioning (InputSink.moveTo): a
    // virtual cursor is tracked client-side and its position is sent each move.
    // So we keep relativeMouseMode OFF — that also lets the engine render the
    // real remote cursor (RustDesk hides CursorPaint while relative mode is on).
    if (p == nd.SessionPhase.connected && !_relativeEnabled) {
      gFFI.inputModel.relativeMouseMode.value = false;
      _relativeEnabled = true;
    }
    if (_m.pi.isSet.value) {
      _peerInfo.add(nd.PeerRuntimeInfo(
        platform: _m.pi.platform,
        isAndroid: _m.isPeerAndroid,
        currentDisplay: _m.pi.currentDisplay,
        displayCount: _m.pi.displaysCount.value,
      ));
    }
  }

  void _emit(nd.SessionPhase p) {
    if (p == _last) return;
    _last = p;
    if (!_phase.isClosed) _phase.add(p);
  }

  @override
  Future<void> switchDisplay(int index) async {
    // Switch the streamed display AND update the LOCAL display metadata
    // (pi.currentDisplay, display rect, cursor origin, canvas view-style,
    // resolution). A bare bind.sessionSwitchDisplay only does the former, so the
    // image switched while the cursor range / resolution stayed on the old
    // display. openMonitorInTheSameTab is stock RustDesk's combined helper.
    openMonitorInTheSameTab(index, gFFI, gFFI.ffiModel.pi);
  }

  @override
  Future<void> setImageQuality(String value) =>
      bind.sessionSetImageQuality(sessionId: gFFI.sessionId, value: value);

  @override
  Future<void> ctrlAltDel() => bind.sessionCtrlAltDel(sessionId: gFFI.sessionId);

  @override
  Future<void> lockScreen() => bind.sessionLockScreen(sessionId: gFFI.sessionId);

  @override
  Future<bool> getToggleOption(String key) async =>
      (await bind.sessionGetToggleOption(
              sessionId: gFFI.sessionId, arg: key)) ??
      false;

  @override
  Future<void> setToggleOption(String key, bool on) async {
    final cur = await getToggleOption(key);
    if (cur != on) {
      await bind.sessionToggleOption(sessionId: gFFI.sessionId, value: key);
    }
  }

  @override
  Future<({String current, List<String> available})> codecInfo() async {
    final current = (await bind.sessionGetOption(
            sessionId: gFFI.sessionId, arg: kOptionCodecPreference)) ??
        '';
    // auto + vp9 are always available (software); the rest depend on the peer.
    final available = <String>['auto', 'vp9'];
    try {
      final m = jsonDecode(await bind.sessionAlternativeCodecs(
          sessionId: gFFI.sessionId)) as Map;
      if (m['vp8'] == true) available.insert(1, 'vp8');
      if (m['av1'] == true) available.add('av1');
      if (m['h264'] == true) available.add('h264');
      if (m['h265'] == true) available.add('h265');
    } catch (_) {
      // Alternative codecs aren't negotiated yet — the auto/vp9 fallback is fine.
    }
    return (current: current.isEmpty ? 'auto' : current, available: available);
  }

  @override
  Future<void> setCodec(String codec) async {
    await bind.sessionPeerOption(
        sessionId: gFFI.sessionId, name: kOptionCodecPreference, value: codec);
    await bind.sessionChangePreferCodec(sessionId: gFFI.sessionId);
  }

  @override
  Future<({int width, int height, List<({int w, int h})> options})>
      resolutionInfo() async {
    final pi = gFFI.ffiModel.pi;
    final d = pi.tryGetDisplayIfNotAllDisplay();
    return (
      width: d?.width ?? 0,
      height: d?.height ?? 0,
      options: [for (final r in pi.resolutions) (w: r.width, h: r.height)],
    );
  }

  @override
  Future<void> changeResolution(int width, int height) async {
    final pi = gFFI.ffiModel.pi;
    if (pi.currentDisplay == kAllDisplayValue) return;
    await bind.sessionChangeResolution(
      sessionId: gFFI.sessionId,
      display: pi.currentDisplay,
      width: width,
      height: height,
    );
  }

  @override
  Future<int> getCustomQuality() async {
    final q = await bind.sessionGetCustomImageQuality(sessionId: gFFI.sessionId);
    return (q != null && q.isNotEmpty) ? q[0] : 50;
  }

  @override
  Future<void> setCustomQuality(int quality) => bind.sessionSetCustomImageQuality(
      sessionId: gFFI.sessionId, value: quality);

  @override
  Future<void> setCustomFps(int fps) =>
      bind.sessionSetCustomFps(sessionId: gFFI.sessionId, fps: fps);

  // Lazily bridge the shared QualityMonitorModel (a ChangeNotifier) to a stream.
  StreamController<nd.QualityStats>? _quality;
  void Function()? _qualityListener;

  @override
  Stream<nd.QualityStats> get qualityStats {
    if (_quality == null) {
      _quality = StreamController<nd.QualityStats>.broadcast();
      _qualityListener = () {
        final d = gFFI.qualityMonitorModel.data;
        if (!(_quality?.isClosed ?? true)) {
          _quality!.add(nd.QualityStats(
              fps: d.fps,
              bitrate: d.targetBitrate,
              delay: d.delay,
              codec: d.codecFormat,
              speed: d.speed));
        }
      };
      gFFI.qualityMonitorModel.addListener(_qualityListener!);
    }
    return _quality!.stream;
  }

  @override
  Future<void> close() async {
    _closed = true;
    _emit(nd.SessionPhase.closed);
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    if (_qualityListener != null) {
      gFFI.qualityMonitorModel.removeListener(_qualityListener!);
    }
    await _quality?.close();
    // Null them so a reconnect on this reused singleton rebuilds a fresh stream
    // (otherwise qualityStats would hand back the closed one).
    _quality = null;
    _qualityListener = null;
    await bind.sessionClose(sessionId: gFFI.sessionId);
  }
}
