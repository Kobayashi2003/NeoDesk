import '../types/peer_info.dart';

/// Access to the saved peer lists shown on the connection screen.
///
/// Abstracts RustDesk's `Peers` models (recent / favorite / lan) held on the
/// `FFI` object and the `peer_model.dart` data. UI-agnostic: just streams of
/// [PeerEntry].
abstract interface class PeerRepository {
  Stream<List<PeerEntry>> get recent;
  Stream<List<PeerEntry>> get favorites;
  Stream<List<PeerEntry>> get lan;

  Future<void> addFavorite(String id);
  Future<void> removeFavorite(String id);
  Future<void> forget(String id);

  /// Set a friendly display name for the peer. Wraps `bind.mainSetPeerAlias`.
  Future<void> setAlias(String id, String alias);
}
