import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/neodesk_core.dart';
import 'package:neodesk_core/ui/demo/fake_core.dart';

/// The contract the Devices page relies on: every mutation must be visible on
/// the streams straight away, because the list is a StreamBuilder and nothing
/// else pokes it. The real adapter regressed on exactly this — deleting a peer
/// wrote through to the engine but never reloaded its models, so the row stayed
/// on screen until the app was restarted.
void main() {
  late FakePeerRepository peers;

  setUp(() => peers = FakePeerRepository());

  Future<List<String>> ids(Stream<List<PeerEntry>> s) async =>
      (await s.first).map((p) => p.id).toList();

  test('forget removes the peer from recent immediately', () async {
    final before = await ids(peers.recent);
    expect(before, isNotEmpty);
    final victim = before.first;

    await peers.forget(victim);

    expect(await ids(peers.recent), isNot(contains(victim)));
  });

  test('forget also clears it from favourites', () async {
    // '123 456 789' ships as both a recent and a favourite in the sample data.
    final favs = await ids(peers.favorites);
    final victim = favs.first;
    expect(await ids(peers.recent), contains(victim));

    await peers.forget(victim);

    expect(await ids(peers.favorites), isNot(contains(victim)),
        reason: 'a deleted peer left on the favourites shelf looks '
            'half-deleted, and re-adding the id later resurrects it');
    expect(await ids(peers.recent), isNot(contains(victim)));
  });

  test('forget emits on the streams, not just mutates state', () async {
    // One subscriber only: Behaviorish replays its current value from
    // `onListen`, which a broadcast controller fires just once — when it goes
    // from no listeners to some. A second concurrent subscriber would get no
    // replay and hang waiting for the next event.
    final seen = <List<String>>[];
    final sub =
        peers.recent.listen((l) => seen.add(l.map((p) => p.id).toList()));
    await Future.delayed(Duration.zero);
    expect(seen, hasLength(1), reason: 'the seed value should arrive');

    await peers.forget(seen.first.first);
    await Future.delayed(Duration.zero);
    await sub.cancel();

    expect(seen, hasLength(2),
        reason: 'the list must re-emit or the UI never rebuilds');
    expect(seen.last.length, seen.first.length - 1);
  });

  test('forgetting an unknown id is harmless', () async {
    final before = await ids(peers.recent);
    await peers.forget('no such peer');
    expect(await ids(peers.recent), before);
  });

  test('addFavorite / removeFavorite show up on the favourites stream',
      () async {
    final recent = await ids(peers.recent);
    final favs = await ids(peers.favorites);
    final candidate = recent.firstWhere((id) => !favs.contains(id));

    await peers.addFavorite(candidate);
    expect(await ids(peers.favorites), contains(candidate));

    await peers.removeFavorite(candidate);
    expect(await ids(peers.favorites), isNot(contains(candidate)));
  });
}
