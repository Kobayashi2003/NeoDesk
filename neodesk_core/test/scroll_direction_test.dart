import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/neodesk_core.dart';
import 'package:neodesk_core/ui/demo/fake_core.dart';
import 'package:neodesk_core/ui/session/gestures/interaction_ui_mode.dart';
import 'package:neodesk_core/ui/session/session_controller.dart';

/// The engine's wheel is positive-up. Getting that backwards made a volume key
/// bound to Scroll up scroll down, and Invert flipped it back.
void main() {
  SessionController controller({required bool invert}) {
    final core = FakeCore();
    core.config.setBool(ConfigKeys.scrollInvert, invert);
    return SessionController(
      core: core,
      session: core.sessions.create(),
      peerId: 'test',
      initialMode: InteractionUiMode.pointer,
    );
  }

  String lastInput(SessionController c) =>
      (c.input as FakeInputSink).log.value.first.label;

  for (final invert in [false, true]) {
    test('wheel sends the given direction (invert: $invert)', () {
      final c = controller(invert: invert);
      c.wheel(1);
      expect(lastInput(c), 'scroll(1)');
      c.wheel(-1);
      expect(lastInput(c), 'scroll(-1)');
    });
  }

  test('dragging down scrolls down', () {
    final c = controller(invert: false);
    DragScroller(c).add(c.scrollStep);
    expect(lastInput(c), 'scroll(-1)');
  });

  test('invert flips drag scrolling', () {
    final c = controller(invert: true);
    DragScroller(c).add(c.scrollStep);
    expect(lastInput(c), 'scroll(1)');
  });

  test('a drag shorter than one step sends nothing', () {
    final c = controller(invert: false);
    DragScroller(c).add(c.scrollStep - 1);
    expect((c.input as FakeInputSink).log.value, isEmpty);
  });
}
