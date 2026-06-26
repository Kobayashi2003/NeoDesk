import '../types/enums.dart';
import '../types/ids.dart';
import '../types/peer_info.dart';

/// A single remote-control session.
///
/// Facade over RustDesk's `FFI` object (`flutter/lib/models/model.dart`),
/// which owns the per-session models (ffiModel/canvasModel/cursorModel/
/// imageModel/inputModel...). This port exposes only lifecycle + state; the
/// frame/input/cursor concerns are split into their own ports so a new UI can
/// depend on exactly what it uses.
abstract interface class RemoteSession {
  SessionId get sessionId;

  /// Reactive connection phase. Backed by `FfiModel` flags
  /// (pi.isSet / waitForFirstImage / closed).
  Stream<SessionPhase> get phase;

  /// Reactive peer/display info once the handshake completes.
  Stream<PeerRuntimeInfo> get peerInfo;

  /// Begin the session. Wraps `FFI.start(id, ...)`.
  Future<void> connect({
    required PeerId id,
    ConnKind kind = ConnKind.remoteControl,
    String? password,
    bool forceRelay = false,
  });

  /// Switch the shown remote monitor. Wraps `bind.sessionSwitchDisplay`.
  Future<void> switchDisplay(int index);

  /// Set the streamed image quality (`best` / `balanced` / `low`). Wraps
  /// `bind.sessionSetImageQuality`.
  Future<void> setImageQuality(String value);

  /// Send the secure attention sequence (Ctrl+Alt+Del) to the remote. A
  /// dedicated engine call — the regular injected chord is blocked by Windows.
  Future<void> ctrlAltDel();

  /// Lock the remote screen. Wraps `bind.sessionLockScreen`.
  Future<void> lockScreen();

  /// Read a boolean session toggle-option (e.g. `enable-clipboard`,
  /// `enable-audio`). Wraps `bind.sessionGetToggleOption`.
  Future<bool> getToggleOption(String key);

  /// Set a boolean session toggle-option to [on] (toggles iff it differs).
  Future<void> setToggleOption(String key, bool on);

  /// Video codec preference: the [current] choice and the [available] options
  /// (`auto` / `vp8` / `vp9` / `av1` / `h264` / `h265`, filtered to what the peer
  /// supports). Wraps `bind.sessionAlternativeCodecs` / `sessionGetOption`.
  Future<({String current, List<String> available})> codecInfo();

  /// Set the codec preference. Wraps `sessionPeerOption` + `sessionChangePreferCodec`.
  Future<void> setCodec(String codec);

  /// Current display resolution ([width]×[height]) and the supported [options].
  Future<({int width, int height, List<({int w, int h})> options})>
      resolutionInfo();

  /// Change the remote display resolution. Wraps `bind.sessionChangeResolution`.
  Future<void> changeResolution(int width, int height);

  /// Custom image-quality % (10–100) when the quality preset is `custom`.
  Future<int> getCustomQuality();
  Future<void> setCustomQuality(int quality);

  /// Custom frame-rate cap (5–120) for the `custom` quality preset.
  Future<void> setCustomFps(int fps);

  /// Live connection stats (FPS / bitrate / delay / codec). Only updates while
  /// the `show-quality-monitor` toggle-option is on. Wraps `QualityMonitorModel`.
  Stream<QualityStats> get qualityStats;

  /// Tear down. Wraps `clientClose(sessionId, ffi)` / `bind.sessionClose`.
  Future<void> close();
}

/// Image-quality levels accepted by [RemoteSession.setImageQuality] (the engine's
/// `kRemoteImageQuality*` tokens).
abstract final class ImageQuality {
  static const best = 'best';
  static const balanced = 'balanced';
  static const low = 'low';
  static const custom = 'custom';
}

/// A snapshot of live connection quality (all strings, as the engine reports
/// them; any may be null before the first sample).
class QualityStats {
  const QualityStats(
      {this.fps, this.bitrate, this.delay, this.codec, this.speed});

  final String? fps;
  final String? bitrate; // target bitrate
  final String? delay; // network delay, ms
  final String? codec;
  final String? speed; // network throughput
}

/// Creates/owns [RemoteSession] instances. Mirrors how RustDesk constructs a
/// fresh `FFI(sessionId)` per connection.
abstract interface class RemoteSessionFactory {
  RemoteSession create({SessionId? sessionId});
}
