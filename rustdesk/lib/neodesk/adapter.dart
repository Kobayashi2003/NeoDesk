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
import 'dart:io' show File, Socket;
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:neodesk_core/neodesk_core.dart' as nd;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'scan_page.dart';
import 'terminal_page.dart';

import '../common.dart' show gFFI, isAndroid, AndroidPermissionManager;
import '../consts.dart'
    show
        kManageExternalStorage,
        kOptionCodecPreference,
        kAllDisplayValue,
        kCommConfKeyLang;
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

  // The real installed version (Android's versionName), cached. Compared against
  // release tags so the updater can never offer a version we already have — the
  // compile-time kNeodeskVersion constant can lag the built APK and did, which
  // made the updater re-download an already-installed build.
  String? _appVersionCache;
  Future<String> _currentVersion() async =>
      _appVersionCache ??= (await PackageInfo.fromPlatform()).version;

  @override
  Future<String> appVersion() => _currentVersion();

  @override
  Future<nd.UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await http.get(Uri.parse(_releasesApi),
          headers: {'Accept': 'application/vnd.github+json'});
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
      if (!_isNewer(tag, await _currentVersion())) return null;
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

  static const _installChannel = MethodChannel('neodesk/installapk');

  @override
  Future<bool> downloadAndInstall(String url,
      {void Function(int received, int total)? onProgress}) async {
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/neodesk-update.apk');
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) return false;
      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.close();
      // Native side resolves a FileProvider URI and launches the package installer.
      final ok = await _installChannel
          .invokeMethod<bool>('install', {'path': file.path});
      return ok ?? false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> setLanguage(String lang) => bind.mainSetLocalOption(
      key: kCommConfKeyLang, value: lang == 'system' ? '' : lang);

  static const _appLockChannel = MethodChannel('neodesk/applock');

  @override
  Future<bool> authenticateAppLock() async {
    try {
      return await _appLockChannel.invokeMethod<bool>('authenticate') ?? false;
    } catch (_) {
      return false;
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
