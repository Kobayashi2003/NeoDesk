import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'canvas_override.dart';
import 'canvas_view.dart';
import 'cursor_override.dart';
import 'gestures/gesture_map.dart';
import 'gestures/interaction_ui_mode.dart';

/// Per-session view state. Bridges a [RemoteSession] (+ its frame/input ports)
/// to the widgets, owns UI-only state (mode, chrome, virtual cursor) and is the
/// single place that converts between screen and remote-image coordinates.
///
/// All screen<->image conversion goes through [view] (a [CanvasView] built from
/// the live transform), so taps/moves land on the correct remote pixel under any
/// zoom/pan. See DESIGN.md §1 / §5.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.core,
    required this.session,
    required this.peerId,
    required InteractionUiMode initialMode,
  }) {
    frameSource = core.frameSourceOf(session);
    input = core.inputSinkOf(session);
    mode = initialMode;
    gestureMap = GestureMap.fromJson(core.config.get(GestureMap.storageKey));
    scrollInvert = core.config.getBool(ConfigKeys.scrollInvert);
    hideCursorInTouch =
        core.config.getBool(ConfigKeys.hideCursorInTouch, defaultValue: true);
    _publishCursorVisibility();
    pointerGainBase = _readDouble(ConfigKeys.pointerGainBase, 1.4);
    pointerGainK = _readDouble(ConfigKeys.pointerGainK, 0.02);
    zoomMax = _readDouble(ConfigKeys.zoomMax, 3.0);
    scrollStep = _readDouble(ConfigKeys.scrollStep, 24);
    scrollStripVisible = core.config.getBool(ConfigKeys.scrollStrip);
    edgePanSpeed = _readEdgePanSpeed();
    currentDisplay = 0;
    _phaseSub = session.phase.listen((p) {
      phase = p;
      if (p == SessionPhase.connecting) {
        _cursorCentered = false;
        // Re-arm the one-shot centering for the new connection.
        _frameSub ??= frameSource.onFrame.listen((_) => _ensureCursorCentered());
      }
      if (p == SessionPhase.connected) {
        _everConnected = true;
        reconnecting = false;
        reconnectAttempt = 0;
        _ensureCursorCentered();
        _loadSessionToggles();
      }
      // An unexpected drop after we'd connected → auto-reconnect (vs. a
      // user-initiated close, or a never-connected initial failure).
      if ((p == SessionPhase.closed || p == SessionPhase.error) &&
          !_userClosing &&
          _everConnected) {
        _scheduleReconnect();
      }
      notifyListeners();
    });
    _peerSub = session.peerInfo.listen((info) {
      peer = info;
      notifyListeners();
    });
    // Centre the cursor once the view is actually laid out. On a cold start the
    // canvas isn't ready when `connected` fires, so retry on each frame until it
    // sticks; the listener cancels itself once centred (re-armed on reconnect).
    _frameSub = frameSource.onFrame.listen((_) => _ensureCursorCentered());
    _qualitySub = session.qualityStats.listen((q) {
      quality = q;
      if (qualityMonitorOn) notifyListeners();
    });
    _pipSub = core.pictureInPictureMode.listen((on) {
      pipActive = on;
      notifyListeners();
    });
  }

  final NeodeskCore core;
  final RemoteSession session;
  final PeerId peerId;

  late final FrameSource frameSource;
  late final InputSink input;

  SessionPhase phase = SessionPhase.idle;
  PeerRuntimeInfo? peer;
  InteractionUiMode mode = InteractionUiModeX.defaultMode;
  bool chromeVisible = true;

  /// Auxiliary vertical scroll strip (a pull-up/down bar) shown in-session.
  bool scrollStripVisible = false;

  /// The keyboard has two independent, separately-summonable surfaces: the
  /// system/ordinary keyboard (invisible IME capture) and the special-keys
  /// panel. Either or both may be shown.
  bool systemKeyboard = false;
  bool specialKeyboard = false;
  bool combosKeyboard = false;
  bool get keyboardVisible =>
      systemKeyboard || specialKeyboard || combosKeyboard;

  /// Demo-only local canvas transform for the placeholder frame. On the real
  /// engine the transform lives in `canvasModel` (read via [view]); this stays
  /// at identity there and is only mutated on the FakeCore path.
  CanvasTransform canvas = const CanvasTransform();

  /// Customisable gesture bindings (DESIGN.md §2.1 / §3.4).
  late GestureMap gestureMap;

  /// Settings mirrored from [ConfigStore].
  bool scrollInvert = false;

  /// Whether the remote cursor is hidden while in Touch mode (default on). In
  /// Touch mode the finger *is* the pointer, so the streamed cursor is noise.
  bool hideCursorInTouch = true;
  late double pointerGainBase;
  late double pointerGainK;
  late double zoomMax;
  late double scrollStep;
  late double edgePanSpeed;

  /// Multi-monitor: index of the display currently shown.
  int currentDisplay = 0;

  /// Virtual cursor position in **image** coordinates (the source of truth for
  /// both modes). Rendered at [cursorScreen]. See §3.1.
  Offset cursorImage = Offset.zero;
  Size viewport = Size.zero;
  bool _disposed = false;

  static const double _edgeMargin = 40;

  StreamSubscription? _phaseSub;
  StreamSubscription? _peerSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _pipSub;
  StreamSubscription? _frameSub;

  /// Whether the cursor has been centred for the current connection (once it is,
  /// we stop re-centring on every frame).
  bool _cursorCentered = false;

  /// Auto-reconnect state. [reconnecting] is true while retrying after an
  /// unexpected drop; [reconnectAttempt] is the current attempt (1.._maxReconnect).
  /// We only retry once a connection has actually succeeded ([_everConnected]),
  /// and never after a user-initiated close ([_userClosing]).
  bool reconnecting = false;
  int reconnectAttempt = 0;
  bool _everConnected = false;
  bool _userClosing = false;
  static const _maxReconnect = 5;
  Timer? _reconnectTimer;

  /// True while the app is in picture-in-picture (small window) — the page hides
  /// its chrome and the floating handle so only the remote shows.
  bool pipActive = false;
  Timer? _chromeTimer;
  Timer? _edgePanTimer;

  bool get isConnected => phase == SessionPhase.connected;

  double _readDouble(String key, double fallback) =>
      double.tryParse(core.config.get(key)) ?? fallback;

  double _readEdgePanSpeed() =>
      switch (core.config.get(ConfigKeys.edgePanSpeed)) {
        'slow' => 3.5,
        'fast' => 9.0,
        _ => 6.0, // medium
      };

  // --- Coordinate model ------------------------------------------------------

  /// Live transform snapshot: from the real engine's `CanvasModel` when present,
  /// else the FakeCore local transform.
  CanvasView get view {
    final c = neodeskCanvasOverride;
    if (c != null) {
      return CanvasView(
        s: c.scale,
        ox: c.offsetX,
        oy: c.offsetY,
        w: c.imageWidth,
        h: c.imageHeight,
        vw: viewport.width,
        vh: viewport.height,
      );
    }
    final geo = frameSource.displayGeometry;
    return CanvasView(
      s: canvas.scale,
      ox: canvas.offsetX,
      oy: canvas.offsetY,
      w: geo.width.toDouble(),
      h: geo.height.toDouble(),
      vw: viewport.width,
      vh: viewport.height,
    );
  }

  /// Where the virtual cursor is drawn, in screen coordinates.
  Offset get cursorScreen {
    final v = view;
    return v.isValid
        ? v.imageToScreen(cursorImage)
        : Offset(viewport.width / 2, viewport.height / 2);
  }

  /// Whether the cursor should be visible at all (mode-aware): hidden in Touch
  /// mode when [hideCursorInTouch] is on, always shown in Pointer mode.
  bool get cursorVisible =>
      !(mode == InteractionUiMode.touch && hideCursorInTouch);

  /// Pushes [cursorVisible] to the real engine's remote-cursor paint (cheap bool,
  /// read per frame). No-op on the FakeCore demo (override is null).
  void _publishCursorVisibility() => neodeskShowRemoteCursor = cursorVisible;

  /// Whether to draw the local virtual cursor. Only on the FakeCore demo — the
  /// real engine renders its own remote cursor (driven via [neodeskCursorOverride]).
  bool get showLocalCursor => cursorVisible && neodeskCursorOverride == null;

  // --- Mode / chrome ---------------------------------------------------------

  void setMode(InteractionUiMode m) {
    if (m == mode) return;
    mode = m;
    _publishCursorVisibility(); // cursor visibility follows the mode
    if (m == InteractionUiMode.pointer) unawaited(_recenterCursor());
    notifyListeners();
  }

  /// Dispatches a discrete gesture's mapped [GestureAction] (DESIGN.md §4).
  void performGesture(GestureAction action) {
    switch (action) {
      case GestureAction.none:
        break;
      case GestureAction.leftClick:
        input.tap(MouseButton.left);
      case GestureAction.rightClick:
        input.tap(MouseButton.right);
      case GestureAction.middleClick:
        input.tap(MouseButton.middle);
      case GestureAction.doubleClick:
        input.tap(MouseButton.left);
        input.tap(MouseButton.left);
      case GestureAction.showToolbar:
        setChrome(true); // persistent; dismissed via the toolbar's Hide button

      case GestureAction.toggleKeyboard:
        toggleKeyboard();
      case GestureAction.escape:
        input.key('Escape', press: true);
      // Continuous actions are applied per-frame by the gesture pads, not here.
      case GestureAction.moveCursor:
      case GestureAction.panCanvas:
      case GestureAction.zoomCanvas:
      case GestureAction.scrollWheel:
        break;
    }
  }

  /// Places the cursor at the centre of the visible viewport (in image space) so
  /// it is findable, and asks the engine to move the real cursor there. Returns
  /// whether the engine actually moved it (false if its geometry isn't ready yet
  /// — the move is silently refused). Used when entering Pointer mode / after a
  /// flip (fire-and-forget) and by [_ensureCursorCentered] (which retries).
  Future<bool> _recenterCursor() async {
    final v = view;
    if (!v.isValid) return false;
    cursorImage = v.screenToImage(Offset(v.vw / 2, v.vh / 2));
    final c = neodeskCursorOverride;
    // No engine override (demo): the local virtual cursor is already centred.
    return c == null ? true : await c.moveTo(v.vw / 2, v.vh / 2);
  }

  /// Centre the cursor once per connection. Retried from the frame stream because
  /// on a cold start the engine refuses the move until its display geometry is
  /// ready — so only commit (and stop retrying) once it actually lands; otherwise
  /// the pointer is left stuck at the remote's top-left.
  Future<void> _ensureCursorCentered() async {
    if (_cursorCentered || phase != SessionPhase.connected) return;
    final v = view;
    if (!v.isValid || viewport.isEmpty) return;
    _cursorCentered = true; // optimistic — prevents re-entrant double-attempts
    if (await _recenterCursor()) {
      // Landed: stop watching frames (re-armed on reconnect).
      _frameSub?.cancel();
      _frameSub = null;
    } else {
      _cursorCentered = false; // engine not ready — retry on the next frame
    }
  }

  void setChrome(bool visible) {
    if (chromeVisible == visible) return;
    chromeVisible = visible;
    notifyListeners();
  }

  void toggleScrollStrip() {
    scrollStripVisible = !scrollStripVisible;
    core.config.setBool(ConfigKeys.scrollStrip, scrollStripVisible);
    notifyListeners();
  }

  // Invert-scroll and hide-cursor-in-Touch are persistent preferences set in
  // Settings (not in-session quick toggles), so no live togglers live here — the
  // values are read from config at session start.

  /// Wheel-scroll by [notches] (used by the scroll strip). Positive = down.
  void scrollBy(int notches) => input.scroll(wheelDir(notches));

  /// Toggle the system/ordinary keyboard. The default keyboard action (toolbar
  /// button, four-finger tap) opens the ordinary keyboard first.
  void toggleKeyboard() {
    systemKeyboard = !systemKeyboard;
    notifyListeners();
  }

  /// Toggle the special-keys panel (Esc/F-keys/modifiers/nav).
  void toggleSpecialKeyboard() {
    specialKeyboard = !specialKeyboard;
    notifyListeners();
  }

  /// Toggle the shortcut-combos panel.
  void toggleCombosKeyboard() {
    combosKeyboard = !combosKeyboard;
    notifyListeners();
  }

  /// Dismiss all keyboard surfaces.
  void hideKeyboard() {
    if (!keyboardVisible) return;
    systemKeyboard = false;
    specialKeyboard = false;
    combosKeyboard = false;
    notifyListeners();
  }

  /// How long chrome stays up before auto-hiding (DESIGN.md §5.5).
  static const _kChromeAutoHide = Duration(milliseconds: 2500);

  /// Edge auto-pan tick (~60 fps) while the cursor sits against a viewport edge.
  static const _kEdgePanInterval = Duration(milliseconds: 16);

  /// Show chrome, then auto-hide after [d].
  void flashChrome([Duration d = _kChromeAutoHide]) {
    setChrome(true);
    _chromeTimer?.cancel();
    _chromeTimer = Timer(d, () => setChrome(false));
  }

  /// Tracks the viewport size. Centres the cursor on first bind, and re-fits the
  /// canvas after an orientation flip (portrait↔landscape) so the remote image
  /// isn't left mis-scaled/off-centre. Safe during build (defers the re-fit to a
  /// post-frame callback so it never notifies mid-layout).
  void bindViewport(Size s) {
    if (viewport == s) return;
    final old = viewport;
    viewport = s;
    if (old.isEmpty) {
      final v = view;
      cursorImage = v.isValid
          ? v.screenToImage(Offset(s.width / 2, s.height / 2))
          : Offset.zero;
      // Now that we have a viewport, try to centre the cursor (deferred a frame
      // so the engine's models are ready; the frame stream also retries until
      // the view is valid, covering a cold start where the canvas lags).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _ensureCursorCentered();
      });
      return;
    }
    // Only react to an orientation flip, not to keyboard-driven height changes.
    final flipped = (old.width > old.height) != (s.width > s.height);
    if (flipped) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || viewport != s) return;
        // Real engine: re-apply its view style to the new window size; FakeCore
        // demo: fit locally.
        final c = neodeskCanvasOverride;
        if (c != null) {
          c.refit();
        } else {
          fitCanvas();
        }
        if (mode == InteractionUiMode.pointer) unawaited(_recenterCursor());
      });
    }
  }

  // --- Cursor movement -------------------------------------------------------

  /// Pointer mode: move the cursor by a screen-space delta. On the real engine
  /// this delegates to RustDesk's `CursorModel` (which converts, renders the
  /// remote cursor, edge-pans and sends to the peer). On the FakeCore demo it
  /// moves the local virtual cursor with scale-aware sensitivity (÷s + accel).
  void moveCursorBy(Offset screenDelta) {
    final c = neodeskCursorOverride;
    if (c != null) {
      c.moveBy(screenDelta.dx, screenDelta.dy);
      return;
    }
    final v = view;
    if (!v.isValid) return;
    final gain = pointerGainBase * (1 + pointerGainK * screenDelta.distance);
    final img = screenDelta / v.s * gain;
    cursorImage = Offset(
      (cursorImage.dx + img.dx).clamp(0.0, v.w),
      (cursorImage.dy + img.dy).clamp(0.0, v.h),
    );
    input.moveTo(cursorImage.dx, cursorImage.dy);
    notifyListeners();
  }

  /// Touch mode: place the cursor under the touched point (absolute). Real engine
  /// routes through `CursorModel.move`; FakeCore maps screen->image locally. §1.1.
  void cursorTo(Offset screen) {
    final c = neodeskCursorOverride;
    if (c != null) {
      c.moveTo(screen.dx, screen.dy);
      return;
    }
    final v = view;
    if (!v.isValid) return;
    final img = v.screenToImage(screen);
    cursorImage = img;
    input.moveTo(img.dx, img.dy);
    notifyListeners();
  }

  // --- Canvas pan / zoom -----------------------------------------------------

  /// Combined pan + zoom in a single step: a two-finger gesture does both at
  /// once, so the canvas follows the fingers like a map/photo viewer (no
  /// pan-vs-zoom mode switch). Pan is applied first, then zoom about [focal],
  /// which keeps the image pixel under the focal point anchored while it also
  /// translates. The real engine clamps itself (§11.2); FakeCore clamps here.
  void transformCanvas(
      {Offset pan = Offset.zero, double zoom = 1.0, Offset? focal}) {
    final c = neodeskCanvasOverride;
    if (c != null) {
      if (pan != Offset.zero) c.panBy(pan.dx, pan.dy);
      if (zoom != 1.0 && focal != null) c.zoomBy(zoom, focal);
      notifyListeners();
      return;
    }
    final v = view;
    var ox = v.ox + pan.dx;
    var oy = v.oy + pan.dy;
    var s = v.s;
    if (zoom != 1.0 && focal != null) {
      final ns = (s * zoom)
          .clamp(v.fitScale, math.max(v.fitScale, zoomMax))
          .toDouble();
      final k = ns / s;
      ox = focal.dx - (focal.dx - ox) * k;
      oy = focal.dy - (focal.dy - oy) * k;
      s = ns;
    }
    final clamped = v.clampOffset(ox, oy, s);
    canvas =
        CanvasTransform(offsetX: clamped.dx, offsetY: clamped.dy, scale: s);
    notifyListeners();
  }

  void panCanvas(Offset delta) => transformCanvas(pan: delta);

  /// Toolbar "Fit": a true reset of the view — zoom the whole image back to fit
  /// the viewport AND recentre it (clears any pan).
  void fitCanvas() {
    final v = view;
    if (!v.isValid) return;
    final c = neodeskCanvasOverride;
    if (c != null) {
      // Atomically set fit-scale and a centred origin. (refit/updateViewStyle
      // alone doesn't reset a pinch-zoom — it early-returns when the view style
      // is unchanged; and zoomBy-then-read-back-scale assumed a sync update.)
      final s = v.fitScale;
      c.setTransform(s, (v.vw - c.imageWidth * s) / 2,
          (v.vh - c.imageHeight * s) / 2);
      notifyListeners();
      return;
    }
    final s = v.fitScale;
    canvas = CanvasTransform(
      scale: s,
      offsetX: (v.vw - v.w * s) / 2,
      offsetY: (v.vh - v.h * s) / 2,
    );
    notifyListeners();
  }

  /// Toolbar: 100% (native pixel) zoom, centred (§4).
  void nativeCanvas() {
    final v = view;
    if (v.isValid) {
      transformCanvas(zoom: 1.0 / v.s, focal: Offset(v.vw / 2, v.vh / 2));
    }
  }

  // --- Pointer-mode edge auto-pan (§3.3) -------------------------------------

  /// Begin a Pointer-mode one-finger drag: arms the edge auto-pan ticker. Only
  /// for the FakeCore demo — the real engine edge-pans inside `CursorModel`.
  void beginPointerDrag() {
    if (neodeskCursorOverride != null) return;
    _edgePanTimer ??= Timer.periodic(_kEdgePanInterval, (_) => _edgePanTick());
  }

  /// End the drag: disarms edge auto-pan.
  void endPointerDrag() {
    _edgePanTimer?.cancel();
    _edgePanTimer = null;
  }

  void _edgePanTick() {
    final v = view;
    if (!v.isValid) return;
    final screen = v.imageToScreen(cursorImage);
    // Normalised push (-1..1) per axis, proportional to margin depth.
    double ex = 0, ey = 0;
    if (screen.dx < _edgeMargin) {
      ex = -(_edgeMargin - screen.dx) / _edgeMargin;
    } else if (screen.dx > v.vw - _edgeMargin) {
      ex = (screen.dx - (v.vw - _edgeMargin)) / _edgeMargin;
    }
    if (screen.dy < _edgeMargin) {
      ey = -(_edgeMargin - screen.dy) / _edgeMargin;
    } else if (screen.dy > v.vh - _edgeMargin) {
      ey = (screen.dy - (v.vh - _edgeMargin)) / _edgeMargin;
    }
    if (ex == 0 && ey == 0) return;
    final stepX = (ex * edgePanSpeed) / v.s;
    final stepY = (ey * edgePanSpeed) / v.s;
    final old = cursorImage;
    cursorImage = Offset(
      (cursorImage.dx + stepX).clamp(0.0, v.w),
      (cursorImage.dy + stepY).clamp(0.0, v.h),
    );
    final moved = cursorImage - old;
    if (moved == Offset.zero) return; // at image bound: nothing left to reveal
    input.moveTo(cursorImage.dx, cursorImage.dy);
    // Pan opposite so the cursor stays pinned near the edge.
    panCanvas(Offset(-moved.dx * v.s, -moved.dy * v.s));
    notifyListeners();
  }

  // --- Misc ------------------------------------------------------------------

  int wheelDir(int raw) => scrollInvert ? -raw : raw;

  void setDisplay(int index) {
    if (currentDisplay == index) return;
    currentDisplay = index;
    session.switchDisplay(index); // actually switch the remote monitor
    notifyListeners();
  }

  /// Streamed image quality (`best` / `balanced` / `low`), applied to the engine.
  String imageQuality = ImageQuality.balanced;

  void setImageQuality(String value) {
    imageQuality = value;
    session.setImageQuality(value);
    notifyListeners();
  }

  /// Send Ctrl+Alt+Del to the remote (the dedicated secure-attention call).
  Future<void> ctrlAltDel() => session.ctrlAltDel();

  /// Lock the remote screen.
  Future<void> lockScreen() => session.lockScreen();

  // Session toggle-options, cached for the More menu.
  bool clipboardEnabled = true;
  bool audioEnabled = true;
  bool viewOnly = false; // input disabled (watch only)
  bool qualityMonitorOn = false; // FPS/bitrate overlay

  /// Latest connection stats (only meaningful while [qualityMonitorOn]).
  QualityStats? quality;

  Future<void> _loadSessionToggles() async {
    clipboardEnabled = await session.getToggleOption('enable-clipboard');
    audioEnabled = await session.getToggleOption('enable-audio');
    viewOnly = await session.getToggleOption('view-only');
    qualityMonitorOn = await session.getToggleOption('show-quality-monitor');
    notifyListeners();
  }

  void toggleViewOnly() {
    viewOnly = !viewOnly;
    session.setToggleOption('view-only', viewOnly);
    notifyListeners();
  }

  void toggleQualityMonitor() {
    qualityMonitorOn = !qualityMonitorOn;
    session.setToggleOption('show-quality-monitor', qualityMonitorOn);
    notifyListeners();
  }

  Future<int> getCustomQuality() => session.getCustomQuality();

  /// Apply a custom image quality (%) and switch the preset to `custom`.
  void setCustomQuality(int q) {
    session.setCustomQuality(q);
    setImageQuality(ImageQuality.custom);
  }

  void setCustomFps(int fps) => session.setCustomFps(fps);

  void toggleClipboard() {
    clipboardEnabled = !clipboardEnabled;
    session.setToggleOption('enable-clipboard', clipboardEnabled);
    notifyListeners();
  }

  void toggleAudio() {
    audioEnabled = !audioEnabled;
    session.setToggleOption('enable-audio', audioEnabled);
    notifyListeners();
  }

  // Codec / resolution — fetched on demand by the More-menu pickers.
  Future<({String current, List<String> available})> codecInfo() =>
      session.codecInfo();
  Future<void> setCodec(String codec) => session.setCodec(codec);
  Future<({int width, int height, List<({int w, int h})> options})>
      resolutionInfo() => session.resolutionInfo();
  Future<void> changeResolution(int w, int h) =>
      session.changeResolution(w, h);

  /// Retry the connection after an unexpected drop, with a short capped backoff,
  /// up to [_maxReconnect] times. After that, give up (the page then closes).
  void _scheduleReconnect() {
    if (reconnectAttempt >= _maxReconnect) {
      reconnecting = false; // exhausted — let the page close
      return;
    }
    reconnecting = true;
    reconnectAttempt++;
    final secs = math.min(reconnectAttempt * 2, 10);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: secs), () {
      if (_disposed || _userClosing) return;
      session.connect(id: peerId);
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    reconnecting = false;
    reconnectAttempt = 0;
  }

  Future<void> disconnect() {
    _userClosing = true; // suppress auto-reconnect for a deliberate close
    _cancelReconnect();
    return session.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _chromeTimer?.cancel();
    _edgePanTimer?.cancel();
    _phaseSub?.cancel();
    _peerSub?.cancel();
    _qualitySub?.cancel();
    _pipSub?.cancel();
    _frameSub?.cancel();
    super.dispose();
  }
}
