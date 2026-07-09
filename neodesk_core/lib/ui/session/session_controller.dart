import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:neodesk_core/neodesk_core.dart';

import 'canvas_override.dart';
import 'canvas_view.dart';
import 'cursor_override.dart';
import 'gestures/gesture_map.dart';
import 'gestures/gesture_tuning.dart';
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
    gestureTuning = GestureTuningStore.load(core.config);
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
    qualityMonitorDetailed =
        core.config.get(ConfigKeys.qualityMonitorDetail) == 'detailed';
    currentDisplay = 0;
    _phaseSub = session.phase.listen((p) {
      phase = p;
      if (p == SessionPhase.connected) {
        _everConnected = true;
        reconnecting = false;
        reconnectAttempt = 0;
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
      // Keep the shown-display selection in step with the engine (it reports the
      // actual current monitor once the handshake completes / after a switch).
      currentDisplay = info.currentDisplay;
      notifyListeners();
    });
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

  /// Recognition thresholds for the gesture state machine (long-press time,
  /// slops, early-tap…). Read once at session start; edited in Settings.
  late GestureTuning gestureTuning;

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

  /// Quality-monitor overlay verbosity (false = simple FPS+delay, true = full).
  late bool qualityMonitorDetailed;

  /// Multi-monitor: index of the display currently shown.
  int currentDisplay = 0;

  /// Virtual cursor position in **image** coordinates (the source of truth for
  /// both modes). Rendered at [cursorScreen]. See §3.1.
  Offset cursorImage = Offset.zero;
  Size viewport = Size.zero;
  bool _disposed = false;

  static const double _edgeMargin = 40;

  /// In Pointer mode, keep the cursor at least this many screen px inside the
  /// viewport while zooming, so it tracks the edge instead of being pushed
  /// off-screen and lost.
  static const double _cursorZoomMargin = 8;

  StreamSubscription? _phaseSub;
  StreamSubscription? _peerSub;
  StreamSubscription? _qualitySub;
  StreamSubscription? _pipSub;


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

  /// Live finger position + ticker for the hold-drag edge continuation.
  Timer? _holdEdgeTimer;
  Offset? _holdFinger;

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
      // Hold actions are press/release pairs driven by the gesture pad's
      // long-press hold path, not one-shot actions.
      case GestureAction.holdLeft:
      case GestureAction.holdRight:
      case GestureAction.holdMiddle:
        break;
      case GestureAction.showToolbar:
        setChrome(true); // persistent; dismissed via the toolbar's Hide button

      case GestureAction.toggleKeyboard:
        toggleKeyboard();
      case GestureAction.escape:
        input.key('Escape', press: true);
      // Continuous actions are applied per-frame by the gesture pads, not here.
      case GestureAction.moveCursor:
      case GestureAction.panCanvas:
      case GestureAction.panElseCursor:
      case GestureAction.zoomCanvas:
      case GestureAction.scrollWheel:
        break;
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

  /// Toggle the system/ordinary keyboard. The toolbar button opens the ordinary
  /// keyboard first; a gesture can also be bound to `toggleKeyboard`.
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

  /// Tracks the viewport size: centres the cursor on first bind, and re-fits the
  /// canvas after an orientation flip (deferred to a post-frame callback so it
  /// never notifies mid-layout).
  void bindViewport(Size s) {
    if (viewport == s) return;
    final old = viewport;
    viewport = s;
    if (old.isEmpty) {
      final v = view;
      cursorImage = v.isValid
          ? v.screenToImage(Offset(s.width / 2, s.height / 2))
          : Offset.zero;
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

  /// Combined pan + zoom in one step, so a two-finger gesture moves the canvas
  /// like a map viewer (no pan/zoom mode switch): pan first, then zoom about
  /// [focal] (anchors the pixel under it). The engine self-clamps; FakeCore
  /// clamps here.
  void transformCanvas(
      {Offset pan = Offset.zero, double zoom = 1.0, Offset? focal}) {
    final zooming = zoom != 1.0 && focal != null;
    final c = neodeskCanvasOverride;
    if (c != null) {
      if (pan != Offset.zero) c.panBy(pan.dx, pan.dy);
      if (zooming) c.zoomBy(zoom, focal);
      if (zooming && mode == InteractionUiMode.pointer) _keepCursorOnScreen();
      notifyListeners();
      return;
    }
    final v = view;
    var ox = v.ox + pan.dx;
    var oy = v.oy + pan.dy;
    var s = v.s;
    if (zooming) {
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
    if (zooming && mode == InteractionUiMode.pointer) _keepCursorOnScreen();
    notifyListeners();
  }

  /// Pointer mode: a zoom moves the cursor's *screen* position outward (its image
  /// position is unchanged), so a cursor near an edge would be carried off-screen.
  /// Clamp it back inside the viewport so further zoom drags it along the edge.
  void _keepCursorOnScreen() {
    final v = view;
    if (!v.isValid || v.vw <= 0 || v.vh <= 0) return;
    final c = neodeskCursorOverride;
    final img = c != null ? c.imagePosition : cursorImage;
    if (img == null) return;
    final screen = v.imageToScreen(img);
    const m = _cursorZoomMargin;
    final cx = screen.dx.clamp(m, math.max(m, v.vw - m)).toDouble();
    final cy = screen.dy.clamp(m, math.max(m, v.vh - m)).toDouble();
    if ((cx - screen.dx).abs() < 0.5 && (cy - screen.dy).abs() < 0.5) return;
    if (c != null) {
      c.moveTo(cx, cy);
    } else {
      cursorImage = v.screenToImage(Offset(cx, cy));
      input.moveTo(cursorImage.dx, cursorImage.dy);
    }
  }

  void panCanvas(Offset delta) => transformCanvas(pan: delta);

  /// Whether the image overflows the viewport on either axis — i.e. whether
  /// there is anything a pan could reveal. At fit scale `CanvasView.clampOffset`
  /// pins the offset to the centred value, so a pan there does nothing at all.
  bool get canPan {
    final v = view;
    if (!v.isValid) return false;
    return v.w * v.s > v.vw + 0.5 || v.h * v.s > v.vh + 0.5;
  }

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

  /// Normalised edge push for a screen point, scaled by [edgePanSpeed] — zero
  /// unless [p] is inside the [_edgeMargin] band, then proportional to depth.
  Offset _edgePush(Offset p, CanvasView v) {
    double ex = 0, ey = 0;
    if (p.dx < _edgeMargin) {
      ex = -(_edgeMargin - p.dx) / _edgeMargin;
    } else if (p.dx > v.vw - _edgeMargin) {
      ex = (p.dx - (v.vw - _edgeMargin)) / _edgeMargin;
    }
    if (p.dy < _edgeMargin) {
      ey = -(_edgeMargin - p.dy) / _edgeMargin;
    } else if (p.dy > v.vh - _edgeMargin) {
      ey = (p.dy - (v.vh - _edgeMargin)) / _edgeMargin;
    }
    if (ex == 0 && ey == 0) return Offset.zero;
    return Offset(ex * edgePanSpeed, ey * edgePanSpeed);
  }

  // --- Long-press hold-drag edge continuation --------------------------------

  /// A hold-drag (long-press with a button held — i.e. selecting text or
  /// dragging) runs out of screen before it runs out of content. While the
  /// finger rests inside the edge band, keep the gesture going as if it were
  /// still moving. Driven by the **finger**, not the cursor: it is the finger
  /// that hits the physical edge.
  void beginHoldDrag(Offset finger) {
    _holdFinger = finger;
    _holdEdgeTimer ??= Timer.periodic(_kEdgePanInterval, (_) => _holdEdgeTick());
  }

  void updateHoldFinger(Offset finger) => _holdFinger = finger;

  void endHoldDrag() {
    _holdEdgeTimer?.cancel();
    _holdEdgeTimer = null;
    _holdFinger = null;
  }

  void _holdEdgeTick() {
    final f = _holdFinger;
    final v = view;
    if (f == null || !v.isValid) return;
    final push = _edgePush(f, v);
    if (push == Offset.zero) return;
    if (mode == InteractionUiMode.touch) {
      // Shift the view toward the edge, then re-place the cursor under the
      // (stationary) finger: it now sits on freshly revealed content, so the
      // remote cursor advances and the selection extends. Stops on its own once
      // the canvas hits its clamp — there is nothing left to reveal.
      panCanvas(-push);
      cursorTo(f);
    } else {
      // Relative mode: keep nudging the cursor outward. The real engine's
      // CursorModel edge-pans on relative moves; FakeCore clamps at the image
      // bound.
      moveCursorBy(push);
    }
  }

  void _edgePanTick() {
    final v = view;
    if (!v.isValid) return;
    final screen = v.imageToScreen(cursorImage);
    final push = _edgePush(screen, v);
    if (push == Offset.zero) return;
    final stepX = push.dx / v.s;
    final stepY = push.dy / v.s;
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
    _refitForDisplaySwitch();
    notifyListeners();
  }

  /// One-shot re-fit after a display switch (the new monitor may differ in
  /// resolution): fit once the engine publishes the new geometry, or after a few
  /// frames for a same-resolution monitor where only the origin changed.
  StreamSubscription? _switchFitSub;
  void _refitForDisplaySwitch() {
    _switchFitSub?.cancel();
    final before = frameSource.displayGeometry;
    var ticks = 0;
    _switchFitSub = frameSource.onFrame.listen((_) {
      if (_disposed) return _cancelSwitchFit();
      final now = frameSource.displayGeometry;
      final geometryChanged =
          now.width != before.width || now.height != before.height;
      if (geometryChanged || ++ticks >= 4) {
        fitCanvas();
        _cancelSwitchFit();
      }
    });
  }

  void _cancelSwitchFit() {
    _switchFitSub?.cancel();
    _switchFitSub = null;
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
  bool followRemoteCursor = true; // show + follow the remote's own cursor
  bool blockInput = false; // block the remote PC's own keyboard & mouse
  bool canBlockInput = false; // peer granted the block_input permission

  /// Latest connection stats (only meaningful while [qualityMonitorOn]).
  QualityStats? quality;

  Future<void> _loadSessionToggles() async {
    // The engine's live per-session options are the *inverted* `disable-*` ones
    // (the `enable-*` keys are global defaults and don't affect the running
    // stream). So a session has audio/clipboard on unless explicitly disabled.
    clipboardEnabled = !await session.getToggleOption('disable-clipboard');
    audioEnabled = !await session.getToggleOption('disable-audio');
    viewOnly = await session.getToggleOption('view-only');
    qualityMonitorOn = await session.getToggleOption('show-quality-monitor');
    // Apply the follow-remote-cursor preference (so the phone's pointer tracks
    // the remote user's physical mouse). Block-input starts off and needs the
    // peer's permission.
    followRemoteCursor =
        core.config.getBool(ConfigKeys.followRemoteCursor, defaultValue: true);
    await session.setToggleOption('show-remote-cursor', followRemoteCursor);
    canBlockInput = await session.hasPermission('block_input');
    blockInput = false;
    notifyListeners();
  }

  void toggleFollowRemoteCursor() {
    followRemoteCursor = !followRemoteCursor;
    core.config.setBool(ConfigKeys.followRemoteCursor, followRemoteCursor);
    session.setToggleOption('show-remote-cursor', followRemoteCursor);
    notifyListeners();
  }

  void toggleBlockInput() {
    blockInput = !blockInput;
    session.setBlockInput(blockInput);
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
  Future<int> getCustomFps() => session.getCustomFps();

  /// Apply a custom image quality (%) and switch the preset to `custom`.
  void setCustomQuality(int q) {
    session.setCustomQuality(q);
    setImageQuality(ImageQuality.custom);
  }

  /// Apply a custom frame-rate cap and switch the preset to `custom` — a named
  /// preset ignores custom-fps, so without this the change wouldn't take effect
  /// and the menu would fall back to the previous preset.
  void setCustomFps(int fps) {
    session.setCustomFps(fps);
    setImageQuality(ImageQuality.custom);
  }

  void toggleClipboard() {
    clipboardEnabled = !clipboardEnabled;
    session.setToggleOption('disable-clipboard', !clipboardEnabled);
    notifyListeners();
  }

  void toggleAudio() {
    audioEnabled = !audioEnabled;
    session.setToggleOption('disable-audio', !audioEnabled);
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
    // Idempotent while a retry is already pending — a single drop can emit both
    // `error` and `closed`, which must not burn two attempts / start two timers.
    if (_reconnectTimer?.isActive ?? false) return;
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
    _switchFitSub?.cancel();
    _chromeTimer?.cancel();
    _edgePanTimer?.cancel();
    _holdEdgeTimer?.cancel();
    _phaseSub?.cancel();
    _peerSub?.cancel();
    _qualitySub?.cancel();
    _pipSub?.cancel();
    super.dispose();
  }
}
