/// Binds the neodesk core ports to RustDesk's real engine (the global `gFFI`
/// and its per-session models). This is the concrete `NeodeskCore` the
/// redesigned UI (package:neodesk_core) runs against in the real app, replacing
/// the in-memory FakeCore.
///
/// Mobile RustDesk drives a single global session (`gFFI`), so the session
/// factory returns one session bound to it.
library;

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show Socket;
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:neodesk_core/neodesk_core.dart' as nd;
import 'package:url_launcher/url_launcher.dart';

import 'scan_page.dart';
import 'terminal_page.dart';

import '../common.dart' show gFFI, isAndroid, AndroidPermissionManager;
import '../consts.dart'
    show kManageExternalStorage, kOptionCodecPreference, kAllDisplayValue;
import '../models/file_model.dart'
    show FileController, SelectedItems, Entry, JobState, PathUtil;
import '../models/input_model.dart' show MouseButtons, InputModel;
import '../models/model.dart';
import '../models/peer_model.dart' show Peers, Peer;
import '../models/platform_model.dart' show bind;

part 'adapter/session.dart';
part 'adapter/input.dart';
part 'adapter/frame.dart';
part 'adapter/config.dart';
part 'adapter/peers.dart';
part 'adapter/files.dart';

/// Composition root over `gFFI`.
class RustdeskCore implements nd.NeodeskCore {
  RustdeskCore()
      : config = _RustdeskConfigStore(),
        peers = _RustdeskPeerRepository(),
        _factory = _RustdeskSessionFactory(),
        _files = _RustdeskFileTransferFactory() {
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _pip.add(call.arguments == true);
    });
    _volkeyChannel.setMethodCallHandler((call) async {
      if (call.method != 'key') return;
      final a = call.arguments as Map;
      _volkey.add(nd.VolumeKeyEvent(
        isUpKey: a['key'] == 'up',
        phase: switch (a['phase']) {
          'down' => nd.VolumeKeyPhase.down,
          'repeat' => nd.VolumeKeyPhase.repeat,
          _ => nd.VolumeKeyPhase.up,
        },
      ));
    });
  }

  final _RustdeskSessionFactory _factory;
  final _RustdeskFileTransferFactory _files;
  static const _pipChannel = MethodChannel('neodesk/pip');
  static const _volkeyChannel = MethodChannel('neodesk/volkey');
  final _pip = StreamController<bool>.broadcast();
  final _volkey = StreamController<nd.VolumeKeyEvent>.broadcast();

  @override
  final nd.ConfigStore config;

  @override
  final nd.PeerRepository peers;

  @override
  nd.RemoteSessionFactory get sessions => _factory;

  @override
  nd.FileTransferFactory get files => _files;

  @override
  Future<String?> scanQrCode(BuildContext context) => neodeskScanQr(context);

  @override
  Future<void> openTerminal(BuildContext context, String id) =>
      neodeskOpenTerminal(context, id);

  @override
  Future<void> enterPictureInPicture() async {
    await _pipChannel.invokeMethod('enter');
  }

  @override
  Stream<bool> get pictureInPictureMode => _pip.stream;

  static const _releasesApi =
      'https://api.github.com/repos/Kobayashi2003/NeoDesk/releases/latest';

  @override
  Future<nd.UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await http.get(Uri.parse(_releasesApi),
          headers: {'Accept': 'application/vnd.github+json'});
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst('v', '');
      if (!_isNewer(tag, nd.kNeodeskVersion)) return null;
      // Prefer the .apk asset's direct download, else the release page.
      var url = j['html_url'] as String? ?? '';
      for (final a in (j['assets'] as List? ?? const [])) {
        if ((a['name'] as String? ?? '').endsWith('.apk')) {
          url = a['browser_download_url'] as String? ?? url;
          break;
        }
      }
      return nd.UpdateInfo(
          version: tag, url: url, notes: j['body'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Numeric dotted-version compare: is [a] newer than [b]?
  bool _isNewer(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? (int.tryParse(pa[i]) ?? 0) : 0;
      final y = i < pb.length ? (int.tryParse(pb[i]) ?? 0) : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  @override
  Future<void> openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Future<void> setVolumeKeyIntercept(
          {required bool up, required bool down}) =>
      _volkeyChannel.invokeMethod('set', {'up': up, 'down': down});

  @override
  Stream<nd.VolumeKeyEvent> get volumeKeyEvents => _volkey.stream;

  @override
  nd.FrameSource frameSourceOf(nd.RemoteSession session) =>
      (session as _RustdeskRemoteSession).frameSource;

  @override
  nd.InputSink inputSinkOf(nd.RemoteSession session) =>
      (session as _RustdeskRemoteSession).inputSink;
}
