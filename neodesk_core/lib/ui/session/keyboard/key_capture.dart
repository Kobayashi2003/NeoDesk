/// Pure logic for the invisible system-keyboard capture (no Flutter deps, so it
/// is unit-tested in isolation — see test/key_capture_test.dart).
///
/// The soft keyboard is captured by a hidden `TextField` holding a filler buffer;
/// each edit is diffed against the previous buffer to recover what the user did.
/// This file holds the two decisions that historically grew fragile, reactive
/// `if`s inside the widget — now isolated and covered by tests:
///
///   * [computeCaptureDelta] — turn an `old → new` buffer edit into "send N
///     backspaces" / "commit this inserted text" / "do nothing", while deferring
///     for a CJK IME that is still composing.
///   * [isSingleAsciiChar] — whether committed text should go as a single key
///     event or as a whole string (preserving order for CJK/emoji).
library;

/// The key-level effect of one soft-keyboard buffer edit.
class KeyboardCaptureDelta {
  const KeyboardCaptureDelta({
    this.backspaces = 0,
    this.committed = '',
    this.deferred = false,
  });

  /// Number of backspaces to send (buffer shrank).
  final int backspaces;

  /// Text inserted since the last edit (buffer grew); empty otherwise.
  final String committed;

  /// True while an IME is composing non-ASCII (e.g. pinyin → 汉字): nothing is
  /// sent AND the tracked buffer must NOT advance, so the eventual commit diffs
  /// against the pre-composition buffer and arrives as one finished, in-order
  /// word. Callers keep their previous buffer value when this is set.
  final bool deferred;

  /// Whether this edit produces no key output (but the buffer may still advance).
  bool get isEmpty => backspaces == 0 && committed.isEmpty;
}

/// Derive the key-level effect of a soft-keyboard edit from [oldValue] → [newValue].
///
/// [composingText] is the IME's current composing region (empty when not
/// composing). When it contains non-ASCII we defer: CJK still commits as a
/// finished word. ASCII composing — English autocorrect, or Gboard treating
/// "/word" as one composing unit — is forwarded immediately, otherwise letters
/// typed after a '/' get stuck in the composing region and never reach the remote.
KeyboardCaptureDelta computeCaptureDelta(
    String oldValue, String newValue, String composingText) {
  if (composingText.runes.any((r) => r > 0x7f)) {
    return const KeyboardCaptureDelta(deferred: true);
  }
  if (newValue.length < oldValue.length) {
    return KeyboardCaptureDelta(backspaces: oldValue.length - newValue.length);
  }
  if (newValue.length > oldValue.length) {
    return KeyboardCaptureDelta(committed: newValue.substring(oldValue.length));
  }
  return const KeyboardCaptureDelta();
}

/// Whether committed text is a single ASCII character (sent as a key event).
/// Anything longer, or non-ASCII (CJK, emoji — emoji being a surrogate pair so
/// `length` > 1), is sent as a whole string so character order is preserved.
bool isSingleAsciiChar(String s) => s.length == 1 && s.runes.first <= 0x7f;
