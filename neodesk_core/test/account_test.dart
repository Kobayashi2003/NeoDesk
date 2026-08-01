import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/neodesk_core.dart';
import 'package:neodesk_core/ui/demo/fake_core.dart';

void main() {
  group('AccountUser labels', () {
    test('falls back to the handle when there is no display name', () {
      const u = AccountUser(name: 'kobayashi');
      expect(u.label, 'kobayashi');
      expect(u.labelWithHandle, 'kobayashi');
    });

    test('prefers the display name', () {
      const u = AccountUser(name: 'kobayashi', displayName: 'Kobayashi');
      expect(u.label, 'Kobayashi');
      expect(u.labelWithHandle, 'Kobayashi (@kobayashi)');
    });

    test('does not repeat itself when the two are the same', () {
      const u = AccountUser(name: 'neo', displayName: 'neo');
      expect(u.labelWithHandle, 'neo');
    });

    test('treats a whitespace-only display name as absent', () {
      const u = AccountUser(name: 'neo', displayName: '   ');
      expect(u.label, 'neo');
      expect(u.labelWithHandle, 'neo');
    });

    test('an empty handle yields an empty label, not "(@)"', () {
      const u = AccountUser(name: '', displayName: 'Ghost');
      expect(u.labelWithHandle, '');
    });
  });

  group('sign-in flow', () {
    late FakeAccount account;

    setUp(() => account = FakeAccount());

    test('starts signed out', () {
      expect(account.current, isNull);
    });

    test('offers the providers the server advertises', () async {
      final list = await account.providers();
      expect(list.map((p) => p.id), containsAll(['google', 'github']));
      // Every provider must carry a label, or the button renders blank.
      expect(list.every((p) => p.label.isNotEmpty), isTrue);
    });

    test('a completed sign-in exposes the user', () async {
      final list = await account.providers();
      final outcome = await account.signInWith(list.first);
      expect(outcome, isA<SignInSucceeded>());
      expect(account.current, isNotNull);
      expect((outcome as SignInSucceeded).user.name, account.current!.name);
    });

    test('reports progress while it waits', () async {
      final seen = <String>[];
      final list = await account.providers();
      await account.signInWith(list.first, onStatus: seen.add);
      expect(seen, isNotEmpty);
    });

    test('cancelling mid-flight leaves the user signed out', () async {
      final list = await account.providers();
      final pending = account.signInWith(list.first);
      await Future.delayed(const Duration(milliseconds: 100));
      await account.cancelSignIn();
      expect(await pending, isA<SignInCancelled>());
      expect(account.current, isNull);
    });

    test('cancelling when nothing is running is harmless', () async {
      await account.cancelSignIn();
      expect(account.current, isNull);
    });

    test('logout clears the session', () async {
      final list = await account.providers();
      await account.signInWith(list.first);
      expect(account.current, isNotNull);
      await account.logout();
      expect(account.current, isNull);
    });

    test('the user stream replays the current value to a late subscriber',
        () async {
      final list = await account.providers();
      await account.signInWith(list.first);
      // Subscribing after the fact must still see the signed-in user, or a
      // widget built later would render as signed out.
      expect((await account.user.first)?.name, account.current!.name);
    });

    test('the user stream emits sign-in and sign-out', () async {
      final seen = <String?>[];
      final sub = account.user.listen((u) => seen.add(u?.name));
      final list = await account.providers();
      await account.signInWith(list.first);
      await account.logout();
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [null, 'demo', null]);
    });
  });
}
