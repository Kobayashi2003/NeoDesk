import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';

/// Two-pane file transfer (This device / Remote tabs) driving the [FileTransfer]
/// port. Browse either side, transfer (download/upload), manage files (new
/// folder / rename / delete), multi-select for batch actions, and watch/cancel
/// jobs at the bottom. See DESIGN.md §4.6.
class FileTransferPage extends StatefulWidget {
  const FileTransferPage({super.key, required this.core, required this.peerId});

  final NeodeskCore core;
  final PeerId peerId;

  @override
  State<FileTransferPage> createState() => _FileTransferPageState();
}

class _FileTransferPageState extends State<FileTransferPage> {
  late final FileTransfer _ft;
  final _subs = <StreamSubscription>[];

  FileListing _local = FileListing.empty;
  FileListing _remote = FileListing.empty;
  List<TransferJob> _jobs = const [];
  bool _localLoaded = false;
  bool _remoteLoaded = false;
  int _tab = 0; // 0 = local, 1 = remote

  // Multi-select state (entry paths on the active side).
  bool _selectMode = false;
  final Set<String> _selected = {};

  // Show-hidden toggle, per tab (0 = local, 1 = remote).
  final List<bool> _showHidden = [false, false];

  bool get _isLocal => _tab == 0;
  FileListing get _listing => _isLocal ? _local : _remote;

  @override
  void initState() {
    super.initState();
    _ft = widget.core.files.open(widget.peerId);
    _subs.add(_ft.local.listen((l) => setState(() {
          _local = l;
          _localLoaded = true;
        })));
    _subs.add(_ft.remote.listen((r) => setState(() {
          _remote = r;
          _remoteLoaded = true;
        })));
    _subs.add(_ft.jobs.listen((j) => setState(() => _jobs = j)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _ft.close();
    super.dispose();
  }

  // ---- selection ------------------------------------------------------------

  void _clearSelection() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _toggleSelect(FileEntry e) => setState(() {
        if (!_selected.remove(e.path)) _selected.add(e.path);
        _selectMode = _selected.isNotEmpty;
      });

  void _selectAll() => setState(() {
        _selected
          ..clear()
          ..addAll(_listing.entries.map((e) => e.path));
        _selectMode = _selected.isNotEmpty;
      });

  List<FileEntry> get _selectedEntries =>
      _listing.entries.where((e) => _selected.contains(e.path)).toList();

  void _switchTab(int index) => setState(() {
        _tab = index;
        _selectMode = false;
        _selected.clear();
      });

  // ---- actions --------------------------------------------------------------

  void _onEntry(FileEntry e) {
    if (_selectMode) {
      _toggleSelect(e);
    } else if (e.isDir) {
      _isLocal ? _ft.openLocal(e.path) : _ft.openRemote(e.path);
    } else {
      _isLocal ? _ft.upload(e) : _ft.download(e);
    }
  }

  void _transferSelected() {
    _ft.transferAll(fromRemote: !_isLocal, entries: _selectedEntries);
    _clearSelection();
  }

  void _deleteSelected() {
    _ft.deleteAll(onRemote: !_isLocal, entries: _selectedEntries);
    _clearSelection();
  }

  /// A single-field name dialog (themed by the app's DialogTheme).
  Future<String?> _nameDialog(String title, String action,
      {String initial = ''}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _newFolder() async {
    final name = await _nameDialog('New folder', 'Create');
    if (name != null && name.isNotEmpty) {
      _ft.createFolder(onRemote: !_isLocal, name: name);
    }
  }

  Future<void> _rename(FileEntry e) async {
    final name = await _nameDialog('Rename', 'Rename', initial: e.name);
    if (name != null && name.isNotEmpty && name != e.name) {
      _ft.rename(onRemote: !_isLocal, entry: e, newName: name);
    }
    _clearSelection();
  }

  void _toggleHidden() {
    final show = !_showHidden[_tab];
    setState(() => _showHidden[_tab] = show);
    _ft.setShowHidden(onRemote: !_isLocal, show: show);
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: _selectMode ? _selectionBar() : _normalBar(),
      body: SafeArea(
        child: Column(
          children: [
            _tabBar(),
            _pathBar(),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(child: _fileList()),
            if (_jobs.isNotEmpty) _jobsStrip(),
          ],
        ),
      ),
    );
  }

  AppBar _normalBar() => AppBar(
        title: Text('Files · ${widget.peerId}', style: AppTypography.body),
        actions: [
          IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'New folder',
              onPressed: _newFolder),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: () => _ft.refresh()),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'hidden') _toggleHidden();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'hidden',
                checked: _showHidden[_tab],
                child: const Text('Show hidden files'),
              ),
            ],
          ),
        ],
      );

  AppBar _selectionBar() => AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: _clearSelection),
        title: Text('${_selected.length} selected', style: AppTypography.body),
        actions: [
          IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select all',
              onPressed: _selectAll),
          IconButton(
              icon: Icon(_isLocal ? Icons.upload : Icons.download),
              tooltip: _isLocal ? 'Upload' : 'Download',
              onPressed: _selected.isEmpty ? null : _transferSelected),
          if (_selected.length == 1)
            IconButton(
                icon: const Icon(Icons.drive_file_rename_outline),
                tooltip: 'Rename',
                onPressed: () => _rename(_selectedEntries.first)),
          IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              tooltip: 'Delete',
              onPressed: _selected.isEmpty ? null : _deleteSelected),
        ],
      );

  Widget _tabBar() => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.s12, Dimens.s8, Dimens.s12, Dimens.s4),
        child: Row(
          children: [
            _tabChip('This device', Icons.smartphone, 0),
            const SizedBox(width: Dimens.s8),
            _tabChip('Remote', Icons.dns_outlined, 1),
          ],
        ),
      );

  Widget _tabChip(String label, IconData icon, int index) {
    final on = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Dimens.s8),
          decoration: BoxDecoration(
            color: on ? AppColors.accentMuted : AppColors.bgElevated1,
            borderRadius: BorderRadius.circular(Dimens.rChip),
            border:
                Border.all(color: on ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: on ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: AppTypography.caption.copyWith(
                      color: on ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pathBar() => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Dimens.s8, vertical: Dimens.s4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.storage_outlined, size: 20),
              tooltip: _isLocal ? 'Home' : 'Drives',
              onPressed: () => _ft.goHome(onRemote: !_isLocal),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 20),
              tooltip: 'Up',
              onPressed: () => _isLocal ? _ft.upLocal() : _ft.upRemote(),
            ),
            Expanded(
              child: Text(_listing.path.isEmpty ? 'Drives' : _listing.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption),
            ),
          ],
        ),
      );

  Widget _fileList() {
    final loaded = _isLocal ? _localLoaded : _remoteLoaded;
    if (!loaded) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: Dimens.s12),
            Text(_isLocal ? 'Reading files…' : 'Connecting…',
                style: AppTypography.caption),
          ],
        ),
      );
    }
    final entries = [..._listing.entries]
      ..sort((a, b) => a.isDir == b.isDir
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : (a.isDir ? -1 : 1));
    if (entries.isEmpty) {
      return const Center(
          child: Text('Empty folder', style: AppTypography.caption));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) => _row(entries[i]),
    );
  }

  Widget _row(FileEntry e) {
    final selected = _selected.contains(e.path);
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.accentMuted,
      leading: _selectMode
          ? Icon(
              selected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.accent : AppColors.textSecondary)
          : Icon(e.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
              color: e.isDir ? AppColors.accent : AppColors.textSecondary),
      title: Text(e.name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body),
      subtitle: e.isDir
          ? null
          : Text(_fmtSize(e.size), style: AppTypography.caption),
      trailing: _selectMode
          ? null
          : (e.isDir
              ? const Icon(Icons.chevron_right,
                  color: AppColors.textDisabled, size: 20)
              : Icon(_isLocal ? Icons.upload : Icons.download,
                  color: AppColors.accent, size: 20)),
      onTap: () => _onEntry(e),
      onLongPress: () => _toggleSelect(e),
    );
  }

  Widget _jobsStrip() => Container(
        constraints: const BoxConstraints(maxHeight: 144),
        decoration: const BoxDecoration(
          color: AppColors.bgElevated1,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final j in _jobs.reversed)
              ListTile(
                dense: true,
                leading: Icon(j.toRemote ? Icons.upload : Icons.download,
                    size: 18, color: AppColors.textSecondary),
                title: Text(j.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption),
                subtitle: j.state == TransferState.running && j.speed > 0
                    ? Text('${_fmtSize(j.speed.round())}/s',
                        style: AppTypography.caption)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _jobStatus(j),
                    if (j.state == TransferState.paused)
                      IconButton(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        tooltip: 'Resume',
                        onPressed: () => _ft.resumeJob(j.id),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: j.state == TransferState.running
                          ? 'Cancel'
                          : 'Remove',
                      onPressed: () => _ft.cancelJob(j.id),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _jobStatus(TransferJob j) => switch (j.state) {
        TransferState.done =>
          const Icon(Icons.check_circle, color: AppColors.online, size: 18),
        TransferState.error =>
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
        _ => SizedBox(
            width: 56,
            child: LinearProgressIndicator(
                value: j.progress,
                color: AppColors.accent,
                backgroundColor: AppColors.border),
          ),
      };

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
