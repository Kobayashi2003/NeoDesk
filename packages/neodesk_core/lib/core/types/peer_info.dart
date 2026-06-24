import 'ids.dart';

/// A saved/known peer entry.
///
/// Lifted (and trimmed) from RustDesk's `Peer` model
/// (`flutter/lib/models/peer_model.dart`). Only the fields a connection list
/// UI realistically needs; extend as required.
class PeerEntry {
  final PeerId id;
  final String username;
  final String hostname;
  final String platform;
  final String alias;
  final bool online;

  const PeerEntry({
    required this.id,
    this.username = '',
    this.hostname = '',
    this.platform = '',
    this.alias = '',
    this.online = false,
  });

  String get displayName => alias.isNotEmpty ? alias : id;
}

/// Runtime info about the connected peer / its display.
///
/// Mirrors the parts of RustDesk's `PeerInfo`
/// (`flutter/lib/models/model.dart`) the rendering & input layers consume.
class PeerRuntimeInfo {
  final String platform; // e.g. kPeerPlatformWindows/Android/...
  final bool isAndroid;
  final int currentDisplay;
  final int displayCount;

  const PeerRuntimeInfo({
    this.platform = '',
    this.isAndroid = false,
    this.currentDisplay = 0,
    this.displayCount = 1,
  });
}
