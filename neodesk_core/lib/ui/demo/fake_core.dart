import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:neodesk_core/neodesk_core.dart';

/// In-memory implementation of every core port, backed by sample data.
///
/// This is NOT the RustDesk adapter — it exists so the new UI/gesture layer
/// (lib/ui) can be developed, run and tested standalone, with no native engine
/// or Rust toolchain present. The real app swaps in `RustdeskCore`
/// (rustdesk/lib/neodesk/adapter.dart) and the UI is unchanged.
class FakeCore implements NeodeskCore {
  FakeCore()
      : _peers = FakePeerRepository(),
        _config = FakeConfigStore();

  final FakePeerRepository _peers;
  final FakeConfigStore _config;
  final FakeRemoteSessionFactory _sessions = FakeRemoteSessionFactory();
  final FakeFileTransferFactory _files = FakeFileTransferFactory();

  @override
  RemoteSessionFactory get sessions => _sessions;

  @override
  ConfigStore get config => _config;

  @override
  PeerRepository get peers => _peers;

  @override
  FileTransferFactory get files => _files;

  @override
  Future<String?> scanQrCode(BuildContext context) async => null;

  @override
  Future<void> openTerminal(BuildContext context, String id) async {}

  @override
  Future<void> enterPictureInPicture() async {}

  @override
  Stream<bool> get pictureInPictureMode => const Stream.empty();

  @override
  Future<String> appVersion() async => kNeodeskVersion;

  @override
  Future<UpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> openExternalUrl(String url) async {}

  @override
  Future<bool> downloadAndInstall(String url,
          {void Function(int received, int total)? onProgress}) async =>
      false;

  @override
  Future<void> setLanguage(String lang) async {}

  @override
  String? get remoteClipboardText => null;

  @override
  Future<bool> authenticateAppLock() async => true;

  @override
  Future<void> setVolumeKeyIntercept(
      {required bool up, required bool down}) async {}

  @override
  Stream<VolumeKeyEvent> get volumeKeyEvents => const Stream.empty();

  @override
  FrameSource frameSourceOf(RemoteSession session) =>
      (session as FakeRemoteSession).frameSource;

  @override
  InputSink inputSinkOf(RemoteSession session) =>
      (session as FakeRemoteSession).inputSink;
}

// ---------------------------------------------------------------------------
// Peers
// ---------------------------------------------------------------------------

const _sampleRecent = <PeerEntry>[
  PeerEntry(
      id: '123 456 789',
      alias: 'Office Desktop',
      platform: 'Windows',
      hostname: 'DESKTOP-OFFICE',
      online: true),
  PeerEntry(
      id: '871 220 533',
      alias: 'MacBook Pro',
      platform: 'Mac OS',
      hostname: 'macbook',
      online: true),
  PeerEntry(
      id: '402 119 870',
      alias: 'Living Room PC',
      platform: 'Linux',
      hostname: 'htpc',
      online: false),
  PeerEntry(
      id: '655 901 244',
      platform: 'Android',
      hostname: 'Pixel 8',
      online: false),
];

const _sampleFavorites = <PeerEntry>[
  PeerEntry(
      id: '123 456 789',
      alias: 'Office Desktop',
      platform: 'Windows',
      online: true),
  PeerEntry(
      id: '871 220 533',
      alias: 'MacBook Pro',
      platform: 'Mac OS',
      online: true),
];

const _sampleLan = <PeerEntry>[
  PeerEntry(
      id: '192.168.1.20', alias: 'NAS-Server', platform: 'Linux', online: true),
];

class FakePeerRepository implements PeerRepository {
  final _recent = Behaviorish<List<PeerEntry>>(List.of(_sampleRecent));
  final _favorites = Behaviorish<List<PeerEntry>>(List.of(_sampleFavorites));
  final _lan = Behaviorish<List<PeerEntry>>(List.of(_sampleLan));

  @override
  Stream<List<PeerEntry>> get recent => _recent.stream;

  @override
  Stream<List<PeerEntry>> get favorites => _favorites.stream;

  @override
  Stream<List<PeerEntry>> get lan => _lan.stream;

  @override
  Future<void> addFavorite(String id) async {
    final p = _recent.value.where((e) => e.id == id);
    if (p.isEmpty) return;
    if (_favorites.value.any((e) => e.id == id)) return;
    _favorites.add([..._favorites.value, p.first]);
  }

  @override
  Future<void> removeFavorite(String id) async =>
      _favorites.add(_favorites.value.where((e) => e.id != id).toList());

  @override
  Future<void> forget(String id) async =>
      _recent.add(_recent.value.where((e) => e.id != id).toList());

  @override
  Future<void> setAlias(String id, String alias) async {
    PeerEntry rename(PeerEntry e) => e.id != id
        ? e
        : PeerEntry(
            id: e.id,
            username: e.username,
            hostname: e.hostname,
            platform: e.platform,
            alias: alias,
            online: e.online);
    _recent.add(_recent.value.map(rename).toList());
    _favorites.add(_favorites.value.map(rename).toList());
    _lan.add(_lan.value.map(rename).toList());
  }
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

class FakeConfigStore implements ConfigStore {
  final Map<String, String> _store = {};

  @override
  String get(String key, {String defaultValue = ''}) =>
      _store[key] ?? defaultValue;

  @override
  Future<void> set(String key, String value) async => _store[key] = value;

  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _store.containsKey(key) ? _store[key] == 'true' : defaultValue;

  @override
  Future<void> setBool(String key, bool value) async =>
      _store[key] = value ? 'true' : 'false';
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

class FakeRemoteSessionFactory implements RemoteSessionFactory {
  int _n = 0;

  @override
  RemoteSession create({SessionId? sessionId}) =>
      FakeRemoteSession(sessionId ?? 'fake-session-${_n++}');
}

class FakeRemoteSession implements RemoteSession {
  FakeRemoteSession(this.sessionId);

  @override
  final SessionId sessionId;

  final _phase = StreamController<SessionPhase>.broadcast();
  final _peerInfo = StreamController<PeerRuntimeInfo>.broadcast();

  final frameSource = FakeFrameSource();
  late final inputSink = FakeInputSink();

  @override
  Stream<SessionPhase> get phase => _phase.stream;

  @override
  Stream<PeerRuntimeInfo> get peerInfo => _peerInfo.stream;

  @override
  Future<void> connect({
    required PeerId id,
    ConnKind kind = ConnKind.remoteControl,
    String? password,
    bool forceRelay = false,
  }) async {
    // Simulate the RustDesk handshake cadence so the phase->UI state machine
    // (DESIGN.md §5.6) is exercised end to end.
    _phase.add(SessionPhase.connecting);
    await Future.delayed(const Duration(milliseconds: 700));
    _phase.add(SessionPhase.authenticating);
    await Future.delayed(const Duration(milliseconds: 500));
    _phase.add(SessionPhase.waitingFirstImage);
    await Future.delayed(const Duration(milliseconds: 600));
    _peerInfo.add(const PeerRuntimeInfo(
      platform: 'Windows',
      isAndroid: false,
      currentDisplay: 0,
      displayCount: 2,
    ));
    frameSource._begin();
    _phase.add(SessionPhase.connected);
  }

  @override
  Future<void> switchDisplay(int index) async {}

  @override
  Future<void> setImageQuality(String value) async {}

  @override
  Future<void> ctrlAltDel() async {}

  @override
  Future<void> lockScreen() async {}

  final _toggles = <String, bool>{};
  @override
  Future<bool> getToggleOption(String key) async => _toggles[key] ?? true;
  @override
  Future<void> setToggleOption(String key, bool on) async =>
      _toggles[key] = on;

  String _codec = 'auto';
  @override
  Future<({String current, List<String> available})> codecInfo() async =>
      (current: _codec, available: const ['auto', 'vp8', 'vp9', 'h264', 'h265']);
  @override
  Future<void> setCodec(String codec) async => _codec = codec;

  ({int w, int h}) _res = (w: 1920, h: 1080);
  @override
  Future<({int width, int height, List<({int w, int h})> options})>
      resolutionInfo() async => (
        width: _res.w,
        height: _res.h,
        options: const [(w: 1920, h: 1080), (w: 1280, h: 720), (w: 1024, h: 768)],
      );
  @override
  Future<void> changeResolution(int width, int height) async =>
      _res = (w: width, h: height);

  int _customQuality = 50;
  @override
  Future<int> getCustomQuality() async => _customQuality;
  @override
  Future<void> setCustomQuality(int quality) async => _customQuality = quality;
  @override
  Future<void> setCustomFps(int fps) async {}
  @override
  Stream<QualityStats> get qualityStats => Stream.periodic(
        const Duration(seconds: 1),
        (i) => QualityStats(
            fps: '60', bitrate: '${2 + i % 3} Mb', delay: '12ms', codec: 'h264'),
      );

  @override
  Future<void> close() async {
    frameSource._stop();
    _phase.add(SessionPhase.closed);
    await _phase.close();
    await _peerInfo.close();
  }
}

// ---------------------------------------------------------------------------
// Frame source
// ---------------------------------------------------------------------------

class FakeFrameSource implements FrameSource {
  final _transform = Behaviorish<CanvasTransform>(const CanvasTransform());
  final _onFrame = StreamController<void>.broadcast();
  Timer? _timer;
  bool _first = false;

  @override
  DisplayGeometry get displayGeometry =>
      const DisplayGeometry(width: 1920, height: 1080);

  @override
  Stream<CanvasTransform> get transform => _transform.stream;

  @override
  Stream<void> get onFrame => _onFrame.stream;

  @override
  bool get hasFirstFrame => _first;

  void _begin() {
    _first = true;
    _timer ??= Timer.periodic(
        const Duration(milliseconds: 250), (_) => _onFrame.add(null));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}

// ---------------------------------------------------------------------------
// Input sink (records actions so the gesture HUD can verify the mapping)
// ---------------------------------------------------------------------------

/// One recorded input action, surfaced on-screen during testing.
class InputAction {
  InputAction(this.label);
  final String label;
}

class FakeInputSink implements InputSink {
  /// Rolling log of recorded actions (newest first, capped) — shown by the
  /// gesture HUD so the gesture->primitive mapping can be verified on screen.
  final ValueNotifier<List<InputAction>> log = ValueNotifier([]);

  void _record(String label) {
    final next = [InputAction(label), ...log.value];
    log.value = next.length > 12 ? next.sublist(0, 12) : next;
  }

  @override
  Future<void> tap(MouseButton button) async => _record('tap(${button.name})');

  @override
  Future<void> pointerDown(MouseButton button) async =>
      _record('down(${button.name})');

  @override
  Future<void> pointerUp(MouseButton button) async =>
      _record('up(${button.name})');

  @override
  Future<void> sendMouse(MousePhase phase, MouseButton button) async =>
      _record('mouse(${phase.name},${button.name})');

  @override
  Future<void> moveTo(double x, double y) async =>
      _record('moveTo(${x.toStringAsFixed(0)}, ${y.toStringAsFixed(0)})');

  @override
  Future<void> moveBy(double dx, double dy) async =>
      _record('moveBy(${dx.toStringAsFixed(1)}, ${dy.toStringAsFixed(1)})');

  @override
  Future<void> scroll(int y) async => _record('scroll($y)');

  @override
  Future<void> key(String name, {bool? down, bool? press}) async =>
      _record('key($name${down == null ? '' : ', down:$down'})');

  @override
  Future<void> setModifiers({bool? ctrl, bool? alt, bool? shift, bool? meta}) async {
    final on = [
      if (ctrl != null) 'ctrl:$ctrl',
      if (alt != null) 'alt:$alt',
      if (shift != null) 'shift:$shift',
      if (meta != null) 'meta:$meta',
    ].join(',');
    _record('mods($on)');
  }

  @override
  Future<void> text(String value) async => _record('text("$value")');

  @override
  Future<void> androidAction(AndroidSystemAction action) async =>
      _record('android(${action.name})');
}

// ---------------------------------------------------------------------------
// File transfer (in-memory demo)
// ---------------------------------------------------------------------------

class FakeFileTransferFactory implements FileTransferFactory {
  @override
  FileTransfer open(PeerId id, {String? password}) => FakeFileTransfer();
}

class FakeFileTransfer implements FileTransfer {
  final _local = Behaviorish<FileListing>(
      const FileListing(path: '/home/me', entries: _localFiles));
  final _remote = Behaviorish<FileListing>(
      const FileListing(path: 'C:\\Users\\peer', entries: _remoteFiles));
  final _phase = Behaviorish<SessionPhaseLite>(SessionPhaseLite.ready);
  final _jobs = Behaviorish<List<TransferJob>>(const []);

  static const _localFiles = [
    FileEntry(name: 'Documents', isDir: true),
    FileEntry(name: 'Downloads', isDir: true),
    FileEntry(name: 'notes.txt', isDir: false, size: 2048),
    FileEntry(name: 'photo.jpg', isDir: false, size: 1532910),
  ];
  static const _remoteFiles = [
    FileEntry(name: 'Desktop', isDir: true),
    FileEntry(name: 'Projects', isDir: true),
    FileEntry(name: 'report.pdf', isDir: false, size: 482000),
    FileEntry(name: 'build.zip', isDir: false, size: 9381204),
  ];

  @override
  Stream<FileListing> get local => _local.stream;
  @override
  Stream<FileListing> get remote => _remote.stream;
  @override
  Stream<SessionPhaseLite> get phase => _phase.stream;
  @override
  Stream<List<TransferJob>> get jobs => _jobs.stream;

  @override
  Future<void> openLocal(String path) async => _local
      .add(FileListing(path: '${_local.value.path}/$path', entries: _localFiles));
  @override
  Future<void> openRemote(String path) async => _remote.add(
      FileListing(path: '${_remote.value.path}\\$path', entries: _remoteFiles));
  @override
  Future<void> upLocal() async =>
      _local.add(const FileListing(path: '/home', entries: _localFiles));
  @override
  Future<void> upRemote() async =>
      _remote.add(const FileListing(path: 'C:\\Users', entries: _remoteFiles));
  @override
  Future<void> goHome({required bool onRemote}) async {
    if (onRemote) {
      _remote.add(const FileListing(path: '', entries: [
        FileEntry(name: 'C:', isDir: true, path: 'C:\\'),
        FileEntry(name: 'D:', isDir: true, path: 'D:\\'),
      ]));
    } else {
      _local.add(const FileListing(path: '/home/me', entries: _localFiles));
    }
  }

  @override
  Future<void> refresh() async {}

  void _fakeJob(String name, bool toRemote) => _jobs.add([
        ..._jobs.value,
        TransferJob(
            id: DateTime.now().millisecondsSinceEpoch,
            name: name,
            progress: 1,
            state: TransferState.done,
            toRemote: toRemote),
      ]);

  @override
  Future<void> download(FileEntry entry) async => _fakeJob(entry.name, false);
  @override
  Future<void> upload(FileEntry entry) async => _fakeJob(entry.name, true);

  @override
  Future<void> transferAll(
      {required bool fromRemote, required List<FileEntry> entries}) async {
    for (final e in entries) {
      _fakeJob(e.name, !fromRemote);
    }
  }

  @override
  Future<void> deleteAll(
      {required bool onRemote, required List<FileEntry> entries}) async {
    final names = entries.map((e) => e.name).toSet();
    final side = onRemote ? _remote : _local;
    side.add(FileListing(
      path: side.value.path,
      entries: side.value.entries.where((e) => !names.contains(e.name)).toList(),
    ));
  }

  @override
  Future<void> cancelJob(int id) async =>
      _jobs.add(_jobs.value.where((j) => j.id != id).toList());

  @override
  Future<void> resumeJob(int id) async {}

  @override
  Future<void> setShowHidden(
      {required bool onRemote, required bool show}) async {}

  @override
  Future<void> createFolder(
      {required bool onRemote, required String name}) async {
    final side = onRemote ? _remote : _local;
    side.add(FileListing(path: side.value.path, entries: [
      FileEntry(name: name, isDir: true, path: '${side.value.path}/$name'),
      ...side.value.entries,
    ]));
  }

  @override
  Future<void> deleteEntry(
      {required bool onRemote, required FileEntry entry}) async {
    final side = onRemote ? _remote : _local;
    side.add(FileListing(
      path: side.value.path,
      entries: side.value.entries.where((e) => e.name != entry.name).toList(),
    ));
  }

  @override
  Future<void> rename({
    required bool onRemote,
    required FileEntry entry,
    required String newName,
  }) async {
    final side = onRemote ? _remote : _local;
    side.add(FileListing(
      path: side.value.path,
      entries: [
        for (final e in side.value.entries)
          if (e.name == entry.name)
            FileEntry(name: newName, isDir: e.isDir, path: e.path, size: e.size)
          else
            e,
      ],
    ));
  }

  @override
  Future<void> close() async {
    await _local.close();
    await _remote.close();
    await _phase.close();
    await _jobs.close();
  }
}

// ---------------------------------------------------------------------------
// Tiny BehaviorSubject-like helper (avoids an rxdart dependency)
// ---------------------------------------------------------------------------

class Behaviorish<T> {
  Behaviorish(this._value) {
    _controller = StreamController<T>.broadcast(onListen: () {
      _controller.add(_value);
    });
  }

  T _value;
  late final StreamController<T> _controller;

  T get value => _value;
  Stream<T> get stream => _controller.stream;

  void add(T v) {
    _value = v;
    _controller.add(v);
  }

  Future<void> close() => _controller.close();
}
