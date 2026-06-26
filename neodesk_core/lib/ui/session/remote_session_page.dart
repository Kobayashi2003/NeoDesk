import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../demo/fake_core.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';
import '../widgets/pill_button.dart';
import 'chrome/floating_ball.dart';
import 'chrome/overlay_chrome.dart';
import 'chrome/scroll_strip.dart';
import 'cursor_layer.dart';
import 'frame_layer.dart';
import 'gestures/gesture_layer.dart';
import 'gestures/interaction_ui_mode.dart';
import 'keyboard/key_combo.dart';
import 'keyboard/remote_keyboard.dart';
import 'session_controller.dart';

/// Full-screen remote-control screen. Owns the [SessionController], drives the
/// phase→UI state machine (DESIGN.md §5.6) and composes the layers.
class RemoteSessionPage extends StatefulWidget {
  const RemoteSessionPage({
    super.key,
    required this.core,
    required this.session,
    required this.peerId,
  });

  final NeodeskCore core;
  final RemoteSession session;
  final PeerId peerId;

  @override
  State<RemoteSessionPage> createState() => _RemoteSessionPageState();
}

class _RemoteSessionPageState extends State<RemoteSessionPage> {
  late final SessionController _c;
  bool _popped = false;
  StreamSubscription<SessionPhase>? _phaseSub;

  @override
  void initState() {
    super.initState();
    final mode = InteractionUiModeX.fromStorage(widget.core.config.get(
        ConfigKeys.defaultMode,
        defaultValue: InteractionUiModeX.defaultMode.storageKey));
    _c = SessionController(
      core: widget.core,
      session: widget.session,
      peerId: widget.peerId,
      initialMode: mode,
    );
    // React to real phase *transitions* off the session's phase stream (which
    // only emits on change) — not the controller's catch-all notifications,
    // which fire on every cursor move/chrome toggle and would re-flash the
    // toolbar. Rendering still rebuilds via the ListenableBuilder below.
    _phaseSub = widget.session.phase.listen(_onPhase);
    // Hide the Android status/navigation bars for an immersive remote view
    // (they swipe back temporarily). Restored on dispose.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final cfg = widget.core.config;
    _volUp = cfg.get(ConfigKeys.volumeUp, defaultValue: 'off');
    _volDown = cfg.get(ConfigKeys.volumeDown, defaultValue: 'off');
    if (_volUp != 'off' || _volDown != 'off') {
      // Intercept natively (not via Flutter's HardwareKeyboard, which desyncs and
      // then stops consuming the keys → they revert to system volume).
      widget.core
          .setVolumeKeyIntercept(up: _volUp != 'off', down: _volDown != 'off');
      _volSub = widget.core.volumeKeyEvents.listen(_onVolumeKey);
    }
  }

  late final String _volUp;
  late final String _volDown;
  StreamSubscription<VolumeKeyEvent>? _volSub;
  static const _modVk = {
    'ctrl': 'VK_CONTROL',
    'alt': 'VK_MENU',
    'shift': 'VK_SHIFT',
    'meta': 'Meta'
  };

  /// Dispatch a (natively-intercepted) volume-key press. A quick press taps;
  /// holding holds — scroll repeats while held, a key/modifier stays down, a
  /// click becomes a drag.
  void _onVolumeKey(VolumeKeyEvent e) {
    if (_c.phase != SessionPhase.connected) return;
    final action = e.isUpKey ? _volUp : _volDown;
    if (action == 'off') return;
    switch (e.phase) {
      case VolumeKeyPhase.down:
        _volPress(action);
      case VolumeKeyPhase.repeat:
        if (action == 'scrollUp' || action == 'scrollDown') _volPress(action);
      case VolumeKeyPhase.up:
        _volRelease(action);
    }
  }

  void _volPress(String action) {
    final input = _c.input;
    switch (action) {
      case 'scrollUp':
        _c.scrollBy(-1);
      case 'scrollDown':
        _c.scrollBy(1);
      case 'left':
        input.pointerDown(MouseButton.left);
      case 'right':
        input.pointerDown(MouseButton.right);
      case 'ctrl' || 'alt' || 'shift' || 'meta':
        _setVolMod(action, true);
      default: // VK_*
        input.key(action, down: true, press: false);
    }
  }

  void _volRelease(String action) {
    final input = _c.input;
    switch (action) {
      case 'left':
        input.pointerUp(MouseButton.left);
      case 'right':
        input.pointerUp(MouseButton.right);
      case 'ctrl' || 'alt' || 'shift' || 'meta':
        _setVolMod(action, false);
      case 'scrollUp' || 'scrollDown':
        break; // momentary; nothing to release
      default: // VK_*
        input.key(action, down: false, press: false);
    }
  }

  /// Hold/release a modifier: the engine flag (so it rides on touch clicks) plus
  /// a real key event (so it reads as held), matching the Fn-keys Hold behaviour.
  void _setVolMod(String m, bool on) {
    _c.input.setModifiers(
      ctrl: m == 'ctrl' ? on : null,
      alt: m == 'alt' ? on : null,
      shift: m == 'shift' ? on : null,
      meta: m == 'meta' ? on : null,
    );
    _c.input.key(_modVk[m]!, down: on, press: false);
  }

  void _onPhase(SessionPhase p) {
    if (p == SessionPhase.connected) {
      _c.flashChrome();
    } else if (p == SessionPhase.closed && !_c.reconnecting && !_popped) {
      _popped = true;
      // Use pop(), not maybePop(): the PopScope(canPop: false) below blocks
      // maybePop() (it re-invokes _close instead), which left the page stuck on
      // the "Disconnected" spinner forever. pop() leaves the route directly.
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _close() async {
    await _c.disconnect();
  }

  @override
  void dispose() {
    if (_volUp != 'off' || _volDown != 'off') {
      widget.core.setVolumeKeyIntercept(up: false, down: false);
      _volSub?.cancel();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _phaseSub?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // The remote view stays full-screen; the keyboard floats over it
        // (positioned above viewInsets) instead of resizing/squishing the canvas.
        resizeToAvoidBottomInset: false,
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => _bodyForPhase(),
        ),
      ),
    );
  }

  Widget _bodyForPhase() {
    // Auto-reconnecting after a drop: show a retry view (with Cancel to bail out)
    // regardless of the raw phase, instead of "Connecting"/"Disconnected".
    if (_c.reconnecting) {
      return _loading(
          trArg('Reconnecting… (attempt {})', _c.reconnectAttempt));
    }
    switch (_c.phase) {
      case SessionPhase.idle:
      case SessionPhase.connecting:
        return _loading(trArg('Connecting to {}', widget.peerId));
      case SessionPhase.authenticating:
        return _loading(tr('Authenticating…'));
      case SessionPhase.waitingFirstImage:
        return _loading(tr('Waiting for image…'));
      case SessionPhase.error:
        return _error();
      case SessionPhase.closed:
        return _loading(tr('Disconnected'), cancellable: false);
      case SessionPhase.connected:
        return _connected();
    }
  }

  /// Small live stats panel (top-left) shown while the quality monitor is on.
  Widget _qualityOverlay() {
    final q = _c.quality;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: Dimens.s8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Simple = the two numbers you actually watch (smoothness + lag);
              // Detailed = the full stat block.
              _qLine('FPS', q?.fps),
              _qLine('Delay', q?.delay),
              if (_c.qualityMonitorDetailed) ...[
                _qLine('Bitrate', q?.bitrate),
                _qLine('Speed', q?.speed),
                _qLine('Codec', q?.codec),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _qLine(String k, String? v) => Text('$k  ${v ?? '—'}',
      style: const TextStyle(
          color: Colors.white, fontSize: 11, fontFamily: 'monospace'));

  Widget _loading(String text, {bool cancellable = true}) => Container(
        color: AppColors.bgBase,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 3),
              ),
              const SizedBox(height: Dimens.s24),
              Text(text, style: AppTypography.body),
              if (cancellable) ...[
                const SizedBox(height: Dimens.s24),
                // Don't trap the user on a stuck connect/reconnect — let them
                // back out cleanly (the engine retries can otherwise spin).
                TextButton(
                  onPressed: _close,
                  child: Text(tr('Cancel'),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _error() => Container(
        color: AppColors.bgBase,
        padding: const EdgeInsets.all(Dimens.s24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.danger, size: 48),
              const SizedBox(height: Dimens.s16),
              Text(tr('Connection failed'), style: AppTypography.title),
              const SizedBox(height: Dimens.s24),
              PillButton(
                  label: tr('Back'),
                  filled: false,
                  onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      );

  Widget _connected() {
    return LayoutBuilder(builder: (context, constraints) {
      final bounds = constraints.biggest;
      final input = _c.input;
      return Stack(
        children: [
          FrameLayer(controller: _c),
          GestureLayer(controller: _c),
          CursorLayer(controller: _c),
          OverlayChrome(
            controller: _c,
            peerName: widget.peerId,
            onClose: _close,
          ),
          if (_c.scrollStripVisible && !_c.pipActive)
            ScrollStrip(controller: _c, bounds: bounds),
          if (_c.qualityMonitorOn && !_c.pipActive) _qualityOverlay(),
          // Draggable handle to bring the toolbar back; only while the toolbar
          // and keyboard are both hidden.
          FloatingBall(
            bounds: bounds,
            visible: !_c.chromeVisible && !_c.keyboardVisible && !_c.pipActive,
            // Show the toolbar and keep it (no auto-hide); the toolbar's own
            // "Hide" button (or tapping the remote in Touch mode) dismisses it.
            onTap: () => _c.setChrome(true),
          ),
          if (input is FakeInputSink) _InputHud(sink: input),
          if (_c.keyboardVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                // Float above the system keyboard when it's up.
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: RemoteKeyboard(
                  input: input,
                  systemActive: _c.systemKeyboard,
                  specialActive: _c.specialKeyboard,
                  combosActive: _c.combosKeyboard,
                  onToggleSystem: _c.toggleKeyboard,
                  onToggleSpecial: _c.toggleSpecialKeyboard,
                  onToggleCombos: _c.toggleCombosKeyboard,
                  onHide: _c.hideKeyboard,
                  combos: ComboStore.load(_c.core.config),
                  opacity: double.tryParse(
                          _c.core.config.get(ConfigKeys.panelOpacity)) ??
                      0.9,
                  keySize: _c.core.config
                      .get(ConfigKeys.keySize, defaultValue: 'medium'),
                  compact: _c.core.config.getBool(ConfigKeys.keyCompact),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Demo-only HUD that shows the last few [InputSink] calls, so the gesture→
/// primitive mapping (DESIGN.md) can be verified at a glance.
class _InputHud extends StatelessWidget {
  const _InputHud({required this.sink});

  final FakeInputSink sink;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: Dimens.s8,
      bottom: Dimens.bottomBarHeight + 24,
      child: IgnorePointer(
        child: ValueListenableBuilder<List<InputAction>>(
          valueListenable: sink.log,
          builder: (context, log, _) {
            if (log.isEmpty) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Dimens.s12, vertical: Dimens.s8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(Dimens.rChip),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('InputSink',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.accent, fontSize: 10)),
                  const SizedBox(height: 2),
                  ...log.take(5).toList().asMap().entries.map((e) => Text(
                        e.value.label,
                        style: TextStyle(
                          color: e.key == 0
                              ? AppColors.accent
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
