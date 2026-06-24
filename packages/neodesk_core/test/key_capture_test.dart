import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/ui/session/keyboard/key_capture.dart';

void main() {
  group('computeCaptureDelta', () {
    test('typing one ASCII char commits it', () {
      final d = computeCaptureDelta('11111', '11111a', '');
      expect(d.committed, 'a');
      expect(d.backspaces, 0);
      expect(d.deferred, isFalse);
    });

    test('deleting one char sends one backspace', () {
      final d = computeCaptureDelta('11111', '1111', '');
      expect(d.backspaces, 1);
      expect(d.committed, isEmpty);
    });

    test('deleting several chars sends that many backspaces', () {
      final d = computeCaptureDelta('11111', '11', '');
      expect(d.backspaces, 3);
    });

    test('no length change sends nothing', () {
      final d = computeCaptureDelta('11111', '11111', '');
      expect(d.isEmpty, isTrue);
      expect(d.deferred, isFalse);
    });

    test('CJK still composing defers (no output, buffer must not advance)', () {
      // Pinyin shown as a composing 汉字 before the user commits it.
      final d = computeCaptureDelta('11111', '11111你', '你');
      expect(d.deferred, isTrue);
      expect(d.committed, isEmpty);
      expect(d.backspaces, 0);
    });

    test('committed CJK word is forwarded whole once composing ends', () {
      // After deferral the buffer stayed at the pre-composition value, so the
      // finished word arrives as the suffix in one go.
      final d = computeCaptureDelta('11111', '11111你好', '');
      expect(d.committed, '你好');
      expect(d.deferred, isFalse);
    });

    test('ASCII composing ("/" in Gboard) is forwarded immediately', () {
      // Gboard treats "/word" as one composing unit; ASCII must NOT defer or the
      // chars get stuck until the '/' is deleted.
      final slash = computeCaptureDelta('11111', '11111/', '/');
      expect(slash.deferred, isFalse);
      expect(slash.committed, '/');

      final next = computeCaptureDelta('11111/', '11111/w', '/w');
      expect(next.deferred, isFalse);
      expect(next.committed, 'w');
    });

    test('emoji is committed as a string (not a single key)', () {
      final d = computeCaptureDelta('11111', '11111😀', '');
      expect(d.committed, '😀');
      expect(isSingleAsciiChar(d.committed), isFalse);
    });

    test('multi-char autocorrect insertion is committed as a string', () {
      final d = computeCaptureDelta('11111', '11111the', '');
      expect(d.committed, 'the');
      expect(isSingleAsciiChar(d.committed), isFalse);
    });
  });

  group('isSingleAsciiChar', () {
    test('single ASCII char is true', () {
      expect(isSingleAsciiChar('a'), isTrue);
      expect(isSingleAsciiChar('/'), isTrue);
      expect(isSingleAsciiChar('5'), isTrue);
    });

    test('empty / multi / non-ASCII / emoji are false', () {
      expect(isSingleAsciiChar(''), isFalse);
      expect(isSingleAsciiChar('ab'), isFalse);
      expect(isSingleAsciiChar('你'), isFalse);
      expect(isSingleAsciiChar('😀'), isFalse);
    });
  });
}
