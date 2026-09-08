import 'package:flutter/widgets.dart' show BuildContext;

import '../ports/config_store.dart';
import '../ports/file_transfer.dart';
import '../ports/frame_source.dart';
import '../ports/input_sink.dart';
import '../ports/peer_repository.dart';
import '../ports/remote_session.dart';

/// Top-level composition root for the core layer.
///
/// Bundles the ports a remote-control screen needs. The UI depends on this
/// single object and never reaches into the native engine directly. Concrete
/// implementations: `FakeCore` (lib/ui/demo, in-memory) for the standalone demo,
/// and `RustdeskCore` (rustdesk/lib/neodesk/adapter.dart) bound to the engine.
abstract interface class NeodeskCore {
  RemoteSessionFactory get sessions;
  ConfigStore get config;
  PeerRepository get peers;
  FileTransferFactory get files;

  /// Scan a QR code and return its text (a device ID / address), or null if the
  /// user cancelled. The app implementation opens a camera page; the demo returns
  /// null. Needs a [context] to push the scanner.
  Future<String?> scanQrCode(BuildContext context);

  /// Open a remote terminal session to [id]. The app pushes an xterm-backed
  /// terminal page (its own engine session); the demo is a no-op.
  Future<void> openTerminal(BuildContext context, String id);

  /// Enter Android picture-in-picture (a Moonlight-style small floating window)
  /// so the remote keeps streaming over other apps. No-op off Android / in demo.
  Future<void> enterPictureInPicture();

  /// Arm/disarm automatically entering picture-in-picture when the app is sent to
  /// the background (Home / app-switch) — only meaningful during an active
  /// session, so the session page arms it on connect and disarms on close.
  /// No-op off Android / in demo.
  Future<void> setAutoPictureInPicture(bool enabled);

  /// Emits true when the app enters picture-in-picture and false when it leaves,
  /// so the session can hide its chrome/floating handle while in the small window.
  Stream<bool> get pictureInPictureMode;

  /// The actual installed app version (from the platform package metadata, i.e.
  /// the same string Android shows), e.g. "1.2.3". Use this for display and
  /// update comparisons instead of the compile-time [kNeodeskVersion] constant,
  /// which can drift from the built APK. The demo returns [kNeodeskVersion].
  Future<String> appVersion();

  /// Check the project's GitHub releases for a newer version. Returns null when
  /// already up to date (or on any error). The demo returns null.
  Future<UpdateInfo?> checkForUpdate();

  /// Open [url] in the system browser (e.g. a release download). No-op in demo.
  Future<void> openExternalUrl(String url);

  /// Download the APK at [url] and launch the system installer, reporting
  /// progress via [onProgress] as `(received, total)` bytes. [total] is 0 when
  /// the server doesn't advertise a length (common for redirected release-asset
  /// downloads) — callers should then show an indeterminate bar but can still
  /// display [received]. Returns false if it couldn't download or start the
  /// installer — the caller can then fall back to [openExternalUrl]. No-op/false
  /// off Android / in demo.
  Future<bool> downloadAndInstall(String url,
      {void Function(int received, int total)? onProgress});

  /// Set the engine's UI language for its dialogs (`system` follows the phone,
  /// else a RustDesk code like `en` / `zh-cn`). No-op in demo.
  Future<void> setLanguage(String lang);

  /// Prompt the device unlock (biometric / PIN / pattern) for the app lock.
  /// Returns true if confirmed; false if cancelled or no secure lock is set.
  /// Returns true in demo (no lock).
  Future<bool> authenticateAppLock();

  /// While the app lock is on, mark the window secure (`FLAG_SECURE`) so remote
  /// content is excluded from the recent-apps thumbnail and screenshots. No-op
  /// off Android / in demo.
  Future<void> setAppLockSecure(bool secure);

  /// Ask the platform to intercept the volume Up/Down keys (so they don't change
  /// system volume) and report presses via [volumeKeyEvents]. Pass false/false to
  /// stop. No-op off Android / in demo. Intercepting natively (not via Flutter's
  /// keyboard) avoids corrupting Flutter's pressed-key state.
  Future<void> setVolumeKeyIntercept({required bool up, required bool down});

  /// Volume-key presses while intercepted.
  Stream<VolumeKeyEvent> get volumeKeyEvents;

  /// Per-session services. Valid only while [session] is connected; the
  /// adapter binds these to that session's underlying `FFI` models.
  FrameSource frameSourceOf(RemoteSession session);
  InputSink inputSinkOf(RemoteSession session);
}

/// Press phase of an intercepted volume key.
enum VolumeKeyPhase { down, repeat, up }

/// An intercepted volume-key press.
class VolumeKeyEvent {
  const VolumeKeyEvent({required this.isUpKey, required this.phase});

  final bool isUpKey; // true = Volume Up, false = Volume Down
  final VolumeKeyPhase phase;
}

/// A newer release found by [NeodeskCore.checkForUpdate].
class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, this.notes = ''});

  final String version; // e.g. "0.4.0"
  final String url; // APK download URL (or the release page)
  final String notes; // release body / changelog
}
