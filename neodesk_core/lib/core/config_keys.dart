/// Central registry of every [ConfigStore] key the UI reads or writes.
///
/// Single source of truth: previously some keys were declared as constants in
/// `settings_page.dart` *and* re-typed as raw string literals in
/// `session_controller.dart`, so a rename in one place silently broke the other.
/// Everything now references [ConfigKeys] instead.
abstract final class ConfigKeys {
  /// Interaction mode a new session opens in (`touch` / `pointer`).
  static const defaultMode = 'neodesk.mode.default';

  /// Invert wheel-scroll direction (bool).
  static const scrollInvert = 'neodesk.scrollinvert';

  /// Hide the remote cursor while in Touch mode (bool; default on). In Pointer
  /// mode the cursor is always shown — it is the thing you steer.
  static const hideCursorInTouch = 'neodesk.hidecursorintouch';

  /// Pointer-mode base sensitivity multiplier (double, stored as text).
  static const pointerGainBase = 'neodesk.pointer.gainBase';

  /// Pointer-mode acceleration coefficient (double, stored as text).
  static const pointerGainK = 'neodesk.pointer.gainK';

  /// Maximum pinch-zoom scale (double, stored as text).
  static const zoomMax = 'neodesk.zoom.max';

  /// Pointer-mode edge auto-pan speed (`slow` / `medium` / `fast`).
  static const edgePanSpeed = 'neodesk.edgepan.speed';

  /// Screen px of drag per wheel notch (double, stored as text). Larger = slower.
  static const scrollStep = 'neodesk.scroll.step';

  /// Show the auxiliary vertical scroll strip in-session (bool).
  static const scrollStrip = 'neodesk.scroll.strip';

  /// Persisted [GestureMap] JSON.
  static const gestureMap = 'neodesk.gesturemap';

  /// Persisted user-editable shortcut combos (JSON list).
  static const combos = 'neodesk.combos';

  /// Opacity of the in-session panels — Fn keys / Combos / More (double 0.55–1.0,
  /// stored as text). Lets the remote screen show through to reduce occlusion.
  static const panelOpacity = 'neodesk.panel.opacity';

  /// On-screen key size for the Fn/Combos panels (`small` / `medium` / `large`).
  static const keySize = 'neodesk.kbd.keysize';

  /// Compact keyboard layout: fewer, horizontally-scrollable rows instead of the
  /// full width-filling grid (bool).
  static const keyCompact = 'neodesk.kbd.compact';

  /// Wide keys: size each Fn/Combos key to its label in horizontally-scrollable
  /// rows so long labels aren't clipped (bool).
  static const keyWide = 'neodesk.kbd.wide';

  /// What each phone volume key does during a session — an action token (`off`,
  /// `scrollUp`/`scrollDown`, `left`/`right`, a modifier `ctrl`/`alt`/`shift`/
  /// `meta`, or a `VK_*` key). When not `off` the key is consumed (no system
  /// volume change); a quick press taps, holding holds (and scroll repeats).
  static const volumeUp = 'neodesk.volume.up';
  static const volumeDown = 'neodesk.volume.down';

  /// Engine UI language for its dialogs (`system` follows the phone, else a
  /// RustDesk code like `en` / `zh-cn`). The neodesk UI itself stays English.
  static const language = 'neodesk.language';

  /// Require a device unlock (biometric / PIN) to open the app (bool).
  static const appLock = 'neodesk.applock';

  /// Detail level of the in-session quality-monitor overlay
  /// (`simple` = FPS + delay; `detailed` = + bitrate, network speed, codec).
  static const qualityMonitorDetail = 'neodesk.qualitymonitor.detail';

  /// UI theme for neodesk's own surfaces (`system` follows the device, else
  /// `light` / `dark`). Engine-spawned dialogs keep the app-wide theme.
  static const theme = 'neodesk.theme';

  /// Last-used remote-terminal font size in logical px (double, stored as text),
  /// so the A-/A+ choice and pinch-zoom persist across terminal sessions.
  static const terminalFontSize = 'neodesk.terminal.fontsize';

  /// Auto-enter picture-in-picture (small window) when the app is backgrounded
  /// during an active session (bool).
  static const autoPip = 'neodesk.autopip';

  /// Ask for confirmation before disconnecting an active session (bool, default
  /// on). Off = leaving/back/Disconnect closes the session immediately.
  static const confirmDisconnect = 'neodesk.confirmdisconnect';
}
