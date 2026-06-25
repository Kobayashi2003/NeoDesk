part of '../adapter.dart';

class _RustdeskFileTransferFactory implements nd.FileTransferFactory {
  @override
  nd.FileTransfer open(String id, {String? password}) =>
      _RustdeskFileTransfer(id, password);
}

class _RustdeskFileTransfer implements nd.FileTransfer {
  _RustdeskFileTransfer(this._id, this._password) {
    _start();
  }

  final String _id;
  final String? _password;

  final _local = StreamController<nd.FileListing>.broadcast();
  final _remote = StreamController<nd.FileListing>.broadcast();
  final _phase = StreamController<nd.SessionPhaseLite>.broadcast();
  final _jobs = StreamController<List<nd.TransferJob>>.broadcast();
  final _workers = <Worker>[];
  bool _ready = false;

  FileController get _localC => gFFI.fileModel.localController;
  FileController get _remoteC => gFFI.fileModel.remoteController;

  Future<void> _start() async {
    if (!_phase.isClosed) _phase.add(nd.SessionPhaseLite.connecting);
    // Android needs full storage access to browse local files.
    if (isAndroid &&
        !await AndroidPermissionManager.check(kManageExternalStorage)) {
      await AndroidPermissionManager.request(kManageExternalStorage);
    }
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, _id);
    // The engine calls fileModel.onReady() itself on a file-transfer connect
    // (model.dart handlePeerInfo), which populates the controllers — we just
    // bridge their `directory` (and the job table) to streams and mark ready on
    // the first listing (pi.isSet is unreliable here / may not change).
    gFFI.start(_id, isFileTransfer: true, password: _password);
    _workers.add(ever(_localC.directory, (_) {
      _markReady();
      _emit(_localC, _local);
    }));
    _workers.add(ever(_remoteC.directory, (_) {
      _markReady();
      _emit(_remoteC, _remote);
    }));
    _workers
        .add(ever(gFFI.fileModel.jobController.jobTable, (_) => _emitJobs()));
    // Seed any already-loaded directory (e.g. reopening).
    if (_localC.directory.value.path.isNotEmpty) _emit(_localC, _local);
    if (_remoteC.directory.value.path.isNotEmpty) _emit(_remoteC, _remote);
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    if (!_phase.isClosed) _phase.add(nd.SessionPhaseLite.ready);
  }

  void _emit(FileController c, StreamController<nd.FileListing> out) {
    if (out.isClosed) return;
    final d = c.directory.value;
    out.add(nd.FileListing(
      path: d.path,
      entries: [
        for (final Entry e in d.entries)
          nd.FileEntry(
            name: e.name,
            // A drive (entryType 3) is navigable like a folder, but isDirectory
            // is false for it — treat drives as dirs so tapping enters them.
            isDir: e.isDirectory || e.isDrive,
            // A bare drive path ("D:") must end with a separator ("D:\") to list.
            path: e.isDrive ? _driveRoot(e.path, e.name) : e.path,
            size: e.size,
            modifiedEpoch: e.modifiedTime,
          ),
      ],
    ));
  }

  String _driveRoot(String path, String name) {
    final p = path.isNotEmpty ? path : name;
    return (p.endsWith('\\') || p.endsWith('/')) ? p : '$p\\';
  }

  void _emitJobs() {
    if (_jobs.isClosed) return;
    _jobs.add([
      for (final j in gFFI.fileModel.jobController.jobTable)
        nd.TransferJob(
          id: j.id,
          name: j.fileName,
          progress: j.percent.clamp(0.0, 1.0).toDouble(),
          state: switch (j.state) {
            JobState.done => nd.TransferState.done,
            JobState.error => nd.TransferState.error,
            JobState.paused => nd.TransferState.paused,
            _ => nd.TransferState.running,
          },
          toRemote: !j.isRemoteToLocal,
          speed: j.speed,
        ),
    ]);
  }

  @override
  Stream<nd.FileListing> get local => _local.stream;
  @override
  Stream<nd.FileListing> get remote => _remote.stream;
  @override
  Stream<nd.SessionPhaseLite> get phase => _phase.stream;
  @override
  Stream<List<nd.TransferJob>> get jobs => _jobs.stream;

  @override
  Future<void> openLocal(String path) async {
    if (path.isNotEmpty) await _localC.openDirectory(path);
  }

  @override
  Future<void> openRemote(String path) async {
    if (path.isNotEmpty) await _remoteC.openDirectory(path);
  }

  @override
  Future<void> upLocal() async {
    await _localC.openDirectory('..');
  }

  @override
  Future<void> upRemote() async {
    await _remoteC.openDirectory('..');
  }

  @override
  Future<void> goHome({required bool onRemote}) async {
    // Remote home is "" → the drive list (C:, D:, …) on Windows.
    (onRemote ? _remoteC : _localC).goToHomeDirectory();
  }

  @override
  Future<void> refresh() async {
    await _localC.refresh();
    await _remoteC.refresh();
  }

  // Single-entry transfers/delete are just the batch operations with one item.
  @override
  Future<void> download(nd.FileEntry entry) =>
      transferAll(fromRemote: true, entries: [entry]);

  @override
  Future<void> upload(nd.FileEntry entry) =>
      transferAll(fromRemote: false, entries: [entry]);

  @override
  Future<void> createFolder(
      {required bool onRemote, required String name}) async {
    final c = onRemote ? _remoteC : _localC;
    final path = PathUtil.join(
        c.directory.value.path, name, c.options.value.isWindows);
    await c.createDir(path);
  }

  @override
  Future<void> deleteEntry(
          {required bool onRemote, required nd.FileEntry entry}) =>
      deleteAll(onRemote: onRemote, entries: [entry]);

  @override
  Future<void> rename({
    required bool onRemote,
    required nd.FileEntry entry,
    required String newName,
  }) async {
    await bind.sessionRenameFile(
      sessionId: gFFI.sessionId,
      actId: DateTime.now().millisecondsSinceEpoch,
      path: entry.path,
      newName: newName,
      isRemote: onRemote,
    );
    await (onRemote ? _remoteC : _localC).refresh();
  }

  /// Resolve neodesk entries back to live engine [Entry]s on [c]'s current dir
  /// and collect them into a [SelectedItems].
  SelectedItems _select(FileController c, bool isLocal, List<nd.FileEntry> es) {
    final sel = SelectedItems(isLocal: isLocal);
    for (final entry in es) {
      final e = c.directory.value.entries
          .firstWhere((x) => x.path == entry.path, orElse: () => Entry());
      if (e.name.isNotEmpty) sel.add(e);
    }
    return sel;
  }

  @override
  Future<void> transferAll(
      {required bool fromRemote, required List<nd.FileEntry> entries}) async {
    final src = fromRemote ? _remoteC : _localC;
    final dst = fromRemote ? _localC : _remoteC;
    final sel = _select(src, !fromRemote, entries);
    if (sel.items.isEmpty) return;
    await src.sendFiles(sel, dst.directoryData());
  }

  @override
  Future<void> deleteAll(
      {required bool onRemote, required List<nd.FileEntry> entries}) async {
    final c = onRemote ? _remoteC : _localC;
    final sel = _select(c, !onRemote, entries);
    if (sel.items.isEmpty) return;
    await c.removeAction(sel);
  }

  @override
  Future<void> cancelJob(int id) =>
      gFFI.fileModel.jobController.cancelJob(id);

  @override
  Future<void> resumeJob(int id) async =>
      gFFI.fileModel.jobController.resumeJob(id);

  @override
  Future<void> setShowHidden(
      {required bool onRemote, required bool show}) async {
    final c = onRemote ? _remoteC : _localC;
    c.toggleShowHidden(showHidden: show);
    await c.refresh();
  }

  @override
  Future<void> close() async {
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    await bind.sessionClose(sessionId: gFFI.sessionId);
    await _local.close();
    await _remote.close();
    await _phase.close();
    await _jobs.close();
  }
}
