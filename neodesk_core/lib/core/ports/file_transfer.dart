import '../types/ids.dart';

/// One entry (file or folder) in a directory listing.
class FileEntry {
  const FileEntry({
    required this.name,
    required this.isDir,
    this.path = '',
    this.size = 0,
    this.modifiedEpoch = 0,
  });

  final String name;
  final bool isDir;
  final String path; // full path (used to navigate / select)
  final int size; // bytes
  final int modifiedEpoch; // seconds since epoch (0 = unknown)
}

/// A directory listing for one side (local or remote).
class FileListing {
  const FileListing({required this.path, required this.entries});

  final String path;
  final List<FileEntry> entries;

  static const empty = FileListing(path: '', entries: []);
}

enum TransferState { running, done, error, paused }

/// A transfer job's progress, surfaced for the jobs strip.
class TransferJob {
  const TransferJob({
    required this.id,
    required this.name,
    required this.progress, // 0..1
    required this.state,
    required this.toRemote, // true = upload, false = download
    this.speed = 0,
  });

  final int id;
  final String name;
  final double progress;
  final TransferState state;
  final bool toRemote;
  final double speed; // bytes/second (0 = unknown / finished)
}

/// A live file-transfer session to one peer. Wraps RustDesk's `FileModel`
/// (`gFFI.fileModel`): two [FileController]s (local / remote) plus a job
/// controller. The UI depends only on plain streams/futures here, so it stays
/// engine-agnostic and demoable.
abstract interface class FileTransfer {
  /// Current listing for each side (re-emits on navigate / refresh).
  Stream<FileListing> get local;
  Stream<FileListing> get remote;

  /// Connection phase (reuses the session phases).
  Stream<SessionPhaseLite> get phase;

  Future<void> openLocal(String path);
  Future<void> openRemote(String path);
  Future<void> upLocal(); // go to parent directory
  Future<void> upRemote();

  /// Jump to the side's root: the local home dir, or — for the remote — the
  /// drive list (Windows roots: C:, D:, …) / filesystem root.
  Future<void> goHome({required bool onRemote});

  Future<void> refresh();

  /// Transfer [entry] from the remote's current dir into the local current dir.
  Future<void> download(FileEntry entry);

  /// Transfer [entry] from the local current dir into the remote current dir.
  Future<void> upload(FileEntry entry);

  /// Batch transfer [entries] (download if [fromRemote], else upload).
  Future<void> transferAll(
      {required bool fromRemote, required List<FileEntry> entries});

  /// Batch delete [entries] from the chosen side (one confirmation).
  Future<void> deleteAll(
      {required bool onRemote, required List<FileEntry> entries});

  /// Cancel/remove a transfer job by id.
  Future<void> cancelJob(int id);

  /// Resume a paused/interrupted job. (The engine has no user-initiated pause of
  /// a running transfer — only resume of one the engine paused, plus cancel.)
  Future<void> resumeJob(int id);

  /// Show or hide dotfiles/hidden entries on the chosen side (re-reads the dir).
  Future<void> setShowHidden({required bool onRemote, required bool show});

  /// Create a new folder named [name] in the current dir of the chosen side.
  Future<void> createFolder({required bool onRemote, required String name});

  /// Delete [entry] from the chosen side (the engine asks for confirmation).
  Future<void> deleteEntry({required bool onRemote, required FileEntry entry});

  /// Rename [entry] to [newName] on the chosen side.
  Future<void> rename({
    required bool onRemote,
    required FileEntry entry,
    required String newName,
  });

  /// Live transfer jobs (progress).
  Stream<List<TransferJob>> get jobs;

  Future<void> close();
}

/// Minimal phase enum for the file-transfer connection (mirrors the relevant
/// [RemoteSession] phases without coupling the two ports).
enum SessionPhaseLite { connecting, ready, error, closed }

/// Opens [FileTransfer] sessions. Mirrors how the remote-control factory creates
/// a fresh engine session per connection (here in file-transfer mode).
abstract interface class FileTransferFactory {
  FileTransfer open(PeerId id, {String? password});
}
