import 'package:flutter_test/flutter_test.dart';
import 'package:neodesk_core/ui/session/gestures/gesture_engine.dart';
import 'package:neodesk_core/ui/session/gestures/gesture_map.dart';
import 'package:neodesk_core/ui/session/gestures/gesture_tuning.dart';
import 'package:neodesk_core/ui/session/gestures/interaction_ui_mode.dart';

/// Records what the engine decided, so a test can assert on slot + anchor.
class _RecSink extends GestureSink {
  final taps = <(GestureSlot, Offset)>[];
  final longPresses = <Offset>[];
  final continuousSlots = <GestureSlot>[];
  final holdDrags = <Offset>[];
  int holdEnds = 0;

  /// What [longPress] should report back to the engine.
  LongPressOutcome outcome = LongPressOutcome.ignored;

  @override
  void tap(GestureSlot slot, Offset at) => taps.add((slot, at));

  @override
  LongPressOutcome longPress(GestureSlot slot, Offset at) {
    longPresses.add(at);
    return outcome;
  }

  @override
  void holdDrag(Offset absPos, Offset delta) => holdDrags.add(absPos);

  @override
  void holdEnd() => holdEnds++;

  @override
  void continuous(GestureSlot slot,
          {Offset delta = Offset.zero,
          Offset absPos = Offset.zero,
          double zoom = 1.0,
          Offset focal = Offset.zero}) =>
      continuousSlots.add(slot);
}

void main() {
  late _RecSink sink;

  // A short long-press so the timer tests stay fast.
  GestureEngine engineWith({bool earlyTap = false}) => GestureEngine(
        tuning: GestureTuning(longPressMs: 20, earlyTap: earlyTap),
        sink: sink,
      );

  setUp(() => sink = _RecSink());

  /// Let the long-press timer fire.
  Future<void> pastLongPress() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  group('anchor', () {
    test('one-finger tap fires at the down point, not the lift point', () {
      final e = engineWith();
      e.down(1, const Offset(100, 100));
      // Drift under dragSlop (12) — still a tap, but the lift point differs.
      e.move(1, const Offset(106, 106), const Offset(6, 6));
      e.up(1);

      expect(sink.taps, hasLength(1));
      expect(sink.taps.single.$1, GestureSlot.oneFingerTap);
      expect(sink.taps.single.$2, const Offset(100, 100));
    });

    test('two-finger tap anchors on the first finger regardless of lift order',
        () {
      final e = engineWith(earlyTap: true);
      e.down(1, const Offset(50, 50)); // first contact == anchor
      e.down(2, const Offset(200, 200));
      e.up(2); // the *second* finger lifts first

      expect(sink.taps, hasLength(1));
      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
      expect(sink.taps.single.$2, const Offset(50, 50));
    });

    test('long press reports the anchor', () async {
      final e = engineWith();
      sink.outcome = LongPressOutcome.holding;
      e.down(1, const Offset(30, 40));
      await pastLongPress();

      expect(sink.longPresses, [const Offset(30, 40)]);
    });
  });

  group('tap slot selection', () {
    test('three fingers fire the three-finger tap', () {
      final e = engineWith();
      e.down(1, const Offset(10, 10));
      e.down(2, const Offset(20, 10));
      e.down(3, const Offset(30, 10));
      e.up(1);
      e.up(2);
      e.up(3);

      expect(sink.taps.single.$1, GestureSlot.threeFingerTap);
    });

    test('five fingers are a palm, not a four-finger tap', () {
      final e = engineWith();
      for (var i = 1; i <= 5; i++) {
        e.down(i, Offset(10.0 * i, 10));
      }
      for (var i = 1; i <= 5; i++) {
        e.up(i);
      }

      expect(sink.taps, isEmpty);
    });
  });

  group('long press', () {
    test('bound to none (ignored) still lets the tap fire on lift', () async {
      final e = engineWith();
      sink.outcome = LongPressOutcome.ignored;
      e.down(1, const Offset(70, 70));
      await pastLongPress();
      e.up(1);

      expect(sink.longPresses, hasLength(1));
      expect(sink.taps.single.$1, GestureSlot.oneFingerTap);
    });

    test('a fired discrete long press consumes the tap', () async {
      final e = engineWith();
      sink.outcome = LongPressOutcome.fired;
      e.down(1, const Offset(70, 70));
      await pastLongPress();
      e.up(1);

      expect(sink.taps, isEmpty);
    });

    test('holding routes moves to holdDrag and the lift to holdEnd', () async {
      final e = engineWith();
      sink.outcome = LongPressOutcome.holding;
      e.down(1, const Offset(70, 70));
      await pastLongPress();
      e.move(1, const Offset(120, 70), const Offset(50, 0));
      e.up(1);

      expect(sink.holdDrags, [const Offset(120, 70)]);
      expect(sink.holdEnds, 1);
      expect(sink.taps, isEmpty);
      expect(sink.continuousSlots, isEmpty); // never a plain one-finger drag
    });
  });

  group('one gesture per touch sequence', () {
    test('a residual finger cannot drag after a two-finger tap fired', () {
      final e = engineWith(earlyTap: true);
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(200, 200));
      e.up(2); // two-finger tap fires; finger 1 is still down

      e.move(1, const Offset(300, 300), const Offset(250, 250));

      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
      expect(sink.continuousSlots, isEmpty);
    });

    test('a plain one-finger drag still emits oneFingerDrag', () {
      final e = engineWith();
      e.down(1, const Offset(50, 50));
      e.move(1, const Offset(90, 50), const Offset(40, 0));

      expect(sink.continuousSlots, [GestureSlot.oneFingerDrag]);
      e.up(1);
      expect(sink.taps, isEmpty); // it moved, so no tap
    });
  });

  group('GestureMap', () {
    test('pinch is fixed to zoom and not editable', () {
      final m = GestureMap.defaults();
      expect(GestureMap.editableSlots, isNot(contains(GestureSlot.twoFingerPinch)));

      m.set(InteractionUiMode.touch, GestureSlot.twoFingerPinch,
          GestureAction.panCanvas);
      expect(m.action(InteractionUiMode.touch, GestureSlot.twoFingerPinch),
          GestureAction.zoomCanvas);
    });

    test('two-finger drags cannot bind moveCursor (they carry no absPos)', () {
      final m = GestureMap.defaults();
      m.set(InteractionUiMode.touch, GestureSlot.twoFingerDragV,
          GestureAction.moveCursor);
      expect(m.action(InteractionUiMode.touch, GestureSlot.twoFingerDragV),
          GestureAction.scrollWheel); // unchanged
    });

    test('mode defaults differ where the modes genuinely differ', () {
      final m = GestureMap.defaults();
      expect(m.action(InteractionUiMode.touch, GestureSlot.oneFingerDrag),
          GestureAction.panCanvas);
      expect(m.action(InteractionUiMode.pointer, GestureSlot.oneFingerDrag),
          GestureAction.moveCursor);
      expect(m.action(InteractionUiMode.touch, GestureSlot.twoFingerDragH),
          GestureAction.none);
    });

    test('v1 configs migrate a long-press click to the hold action', () {
      const raw = '{"touch":{"oneFingerLongPress":"leftClick"}}'; // no "_v"
      final m = GestureMap.fromJson(raw);
      expect(m.action(InteractionUiMode.touch, GestureSlot.oneFingerLongPress),
          GestureAction.holdLeft);
    });

    test('v2 configs keep an explicit long-press click', () {
      final raw = GestureMap.defaults().toJson();
      final m = GestureMap.fromJson(raw);
      m.set(InteractionUiMode.touch, GestureSlot.oneFingerLongPress,
          GestureAction.leftClick);
      final reloaded = GestureMap.fromJson(m.toJson());
      expect(
          reloaded.action(
              InteractionUiMode.touch, GestureSlot.oneFingerLongPress),
          GestureAction.leftClick);
    });
  });
}
