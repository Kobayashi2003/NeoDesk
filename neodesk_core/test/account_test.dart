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

    test('rejects empty credentials without challenging', () async {
      expect(await account.login('', 'pw'), isA<LoginFailed>());
      expect(await account.login('user', ''), isA<LoginFailed>());
      expect(account.current, isNull);
    });

    test('challenges for a code before issuing a session', () async {
      final outcome = await account.login('user', 'pw');
      expect(outcome, isA<LoginNeedsCode>());
      // Still signed out — a challenge is not a sign-in.
      expect(account.current, isNull);
    });

    test('a wrong code fails and leaves the user signed out', () async {
      final pending = await account.login('user', 'pw') as LoginNeedsCode;
      expect(await account.submitCode(pending, '000000'), isA<LoginFailed>());
      expect(account.current, isNull);
    });

    test('the right code signs in and exposes the user', () async {
      final pending = await account.login('kobayashi', 'pw') as LoginNeedsCode;
      final done = await account.submitCode(pending, FakeAccount.demoCode);
      expect(done, isA<LoginSucceeded>());
      expect(account.current?.name, 'kobayashi');
      expect((done as LoginSucceeded).user.name, 'kobayashi');
    });

    test('logout clears the session', () async {
      final pending = await account.login('user', 'pw') as LoginNeedsCode;
      await account.submitCode(pending, FakeAccount.demoCode);
      expect(account.current, isNotNull);
      await account.logout();
      expect(account.current, isNull);
    });

    test('the user stream replays the current value to a late subscriber',
        () async {
      final pending = await account.login('user', 'pw') as LoginNeedsCode;
      await account.submitCode(pending, FakeAccount.demoCode);
      // Subscribing after the fact must still see the signed-in user, or a
      // widget built later would render as signed out.
      expect((await account.user.first)?.name, 'user');
    });

    test('the user stream emits sign-in and sign-out', () async {
      final seen = <String?>[];
      final sub = account.user.listen((u) => seen.add(u?.name));
      final pending = await account.login('user', 'pw') as LoginNeedsCode;
      await account.submitCode(pending, FakeAccount.demoCode);
      await account.logout();
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [null, 'user', null]);
    });
  });
}
