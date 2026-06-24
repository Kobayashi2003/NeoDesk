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

  /// What each phone volume key does during a session — an action token (`off`,
  /// `scrollUp`/`scrollDown`, `left`/`right`, a modifier `ctrl`/`alt`/`shift`/
  /// `meta`, or a `VK_*` key). When not `off` the key is consumed (no system
  /// volume change); a quick press taps, holding holds (and scroll repeats).
  static const volumeUp = 'neodesk.volume.up';
  static const volumeDown = 'neodesk.volume.down';
}
