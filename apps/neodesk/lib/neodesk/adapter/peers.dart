part of '../adapter.dart';

class _RustdeskPeerRepository implements nd.PeerRepository {
  _RustdeskPeerRepository() {
    _bindModel(gFFI.recentPeersModel, _recent, bind.mainLoadRecentPeers);
    _bindModel(gFFI.favoritePeersModel, _favorites, bind.mainLoadFavPeers);
    _bindModel(gFFI.lanPeersModel, _lan, bind.mainLoadLanPeers);
    // Online status: query the ID server for ID-based peers, and TCP-probe
    // IP-direct peers (the ID server doesn't track those). Refresh on a timer so
    // the green dots stay fresh.
    Timer(_kInitialOnlineDelay, _refreshOnline);
    Timer.periodic(_kOnlinePollInterval, (_) => _refreshOnline());
  }

  // Online-status polling cadence and per-host probe timeout.
  static const _kInitialOnlineDelay = Duration(seconds: 2);
  static const _kOnlinePollInterval = Duration(seconds: 15);
  static const _kProbeTimeout = Duration(milliseconds: 1500);

  final _recent = StreamController<List<nd.PeerEntry>>.broadcast();
  final _favorites = StreamController<List<nd.PeerEntry>>.broadcast();
  final _lan = StreamController<List<nd.PeerEntry>>.broadcast();

  // Reachability of IP-direct peers (keyed by peer id), filled by [_probeIp].
  final _ipOnline = <String, bool>{};

  // RustDesk's default direct-IP-access port (used when the id omits one).
  static const _directAccessPort = 21118;

  void _refreshOnline() {
    final ids = _allIds();
    if (ids.isNotEmpty) bind.queryOnlines(ids: ids.toList());
    _probeIp(ids);
  }

  Set<String> _allIds() => {
        for (final p in gFFI.recentPeersModel.peers) p.id,
        for (final p in gFFI.favoritePeersModel.peers) p.id,
        for (final p in gFFI.lanPeersModel.peers) p.id,
      };

  /// TCP-probe each IP-direct peer (concurrently); on a change, re-emit so the
  /// dots update.
  Future<void> _probeIp(Set<String> ids) async {
    final targets = {
      for (final id in ids)
        if (_parseHostPort(id) case final hp?) id: hp,
    };
    if (targets.isEmpty) return;
    var changed = false;
    await Future.wait(targets.entries.map((e) async {
      final ok = await _tcpReachable(e.value.$1, e.value.$2);
      if (_ipOnline[e.key] != ok) {
        _ipOnline[e.key] = ok;
        changed = true;
      }
    }));
    if (changed) _emitAll();
  }

  Future<bool> _tcpReachable(String host, int port) async {
    try {
      final s = await Socket.connect(host, port, timeout: _kProbeTimeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// (host, port) if [id] is an IP/host (has a dot); null for ID-server ids.
  (String, int)? _parseHostPort(String id) {
    final s = id.replaceAll(' ', '');
    if (!s.contains('.')) return null; // numeric ID-server id
    final i = s.lastIndexOf(':');
    if (i > 0) {
      return (s.substring(0, i),
          int.tryParse(s.substring(i + 1)) ?? _directAccessPort);
    }
    return (s, _directAccessPort);
  }

  void _emitAll() {
    _emitOne(gFFI.recentPeersModel, _recent);
    _emitOne(gFFI.favoritePeersModel, _favorites);
    _emitOne(gFFI.lanPeersModel, _lan);
  }

  void _emitOne(Peers model, StreamController<List<nd.PeerEntry>> out) {
    if (!out.isClosed) out.add(model.peers.map(_toEntry).toList());
  }

  void _bindModel(Peers model, StreamController<List<nd.PeerEntry>> out,
      Future<void> Function() load) {
    model.addListener(() => _emitOne(model, out));
    _emitOne(model, out); // seed current
    load(); // trigger async (re)load → model notifies
  }

  nd.PeerEntry _toEntry(Peer p) => nd.PeerEntry(
        id: p.id,
        username: p.username,
        hostname: p.hostname,
        platform: p.platform,
        alias: p.alias,
        // IP-direct peers: prefer the probe result over the (always-false)
        // ID-server status.
        online: _ipOnline[p.id] ?? p.online,
      );

  @override
  Stream<List<nd.PeerEntry>> get recent => _recent.stream;

  @override
  Stream<List<nd.PeerEntry>> get favorites => _favorites.stream;

  @override
  Stream<List<nd.PeerEntry>> get lan => _lan.stream;

  @override
  Future<void> addFavorite(String id) async {
    final favs = (await bind.mainGetFav()).toList();
    if (!favs.contains(id)) {
      favs.add(id);
      await bind.mainStoreFav(favs: favs);
      await bind.mainLoadFavPeers(); // model notifies → favorites stream re-emits
    }
  }

  @override
  Future<void> removeFavorite(String id) async {
    final favs = (await bind.mainGetFav()).toList();
    if (favs.remove(id)) {
      await bind.mainStoreFav(favs: favs);
      await bind.mainLoadFavPeers();
    }
  }

  @override
  Future<void> forget(String id) => bind.mainRemovePeer(id: id);

  @override
  Future<void> setAlias(String id, String alias) async {
    await bind.mainSetPeerAlias(id: id, alias: alias);
    await Future.wait([
      bind.mainLoadRecentPeers(),
      bind.mainLoadFavPeers(),
      bind.mainLoadLanPeers(),
    ]);
  }
}
