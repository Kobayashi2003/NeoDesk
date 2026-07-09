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

    test('two-finger tap anchors on the second finger, whatever lifts first',
        () {
      final e = engineWith(earlyTap: true);
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(200, 200)); // completing finger == anchor
      e.up(2); // the *second* finger lifts first

      expect(sink.taps, hasLength(1));
      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
      expect(sink.taps.single.$2, const Offset(200, 200));
    });

    test('the anchor is fixed when the finger lands, not where it drifts to',
        () {
      final e = engineWith();
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(200, 200));
      e.move(2, const Offset(206, 206), const Offset(6, 6)); // under dragSlop
      e.up(1);
      e.up(2);

      expect(sink.taps.single.$2, const Offset(200, 200));
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
    test('three fingers fire the three-finger tap at the third finger', () {
      final e = engineWith();
      e.down(1, const Offset(10, 10));
      e.down(2, const Offset(20, 10));
      e.down(3, const Offset(30, 10));
      e.up(1);
      e.up(2);
      e.up(3);

      expect(sink.taps.single.$1, GestureSlot.threeFingerTap);
      expect(sink.taps.single.$2, const Offset(30, 10));
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

  group('finger-collection window', () {
    GestureEngine collecting() => GestureEngine(
          tuning: const GestureTuning(longPressMs: 500, collectMs: 60),
          sink: sink,
        );

    test('a finger landing after the window cancels the tap', () async {
      final e = collecting();
      e.down(1, const Offset(50, 50));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      e.down(2, const Offset(200, 200)); // too late to be collected
      e.up(1);
      e.up(2);

      // Neither a two-finger tap (not collected) nor a one-finger one.
      expect(sink.taps, isEmpty);
    });

    test('a finger landing inside the window is collected', () async {
      final e = collecting();
      e.down(1, const Offset(50, 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      e.down(2, const Offset(200, 200));
      e.up(1);
      e.up(2);

      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
      expect(sink.taps.single.$2, const Offset(200, 200));
    });
  });

  group('multi-finger taps tolerate fingers rolling as they land', () {
    test('a finger past dragSlop no longer vetoes a two-finger tap', () {
      final e = engineWith();
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(200, 200));
      // 20px > dragSlop (12): _moved is set, but the centroid barely moves and
      // nothing gets classified as a drag.
      e.move(2, const Offset(220, 200), const Offset(20, 0));
      e.up(1);
      e.up(2);

      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
    });

    test('a real two-finger swipe still does not fire a tap', () {
      final e = engineWith();
      e.down(1, const Offset(50, 200));
      e.down(2, const Offset(120, 200));
      // Both fingers travel together, far past tapSlop — a swipe, not a tap.
      for (var i = 1; i <= 10; i++) {
        e.move(1, Offset(50, 200 + 12.0 * i), const Offset(0, 12));
        e.move(2, Offset(120, 200 + 12.0 * i), const Offset(0, 12));
      }
      e.up(1);
      e.up(2);

      expect(sink.taps, isEmpty);
    });
  });

  group('multi-finger window runs until the long press would fire', () {
    // Everything before the long press is the multi-finger trigger period, so a
    // slow two-finger tap must still register.
    GestureEngine slow() => GestureEngine(
          tuning: const GestureTuning(longPressMs: 200),
          sink: sink,
        );

    test('a two-finger tap well past the old 250ms limit still fires',
        () async {
      final e = slow();
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(80, 50));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      e.up(1);
      e.up(2);

      expect(sink.taps.single.$1, GestureSlot.twoFingerTap);
    });

    test('once the long press would have fired, no tap', () async {
      final e = slow();
      e.down(1, const Offset(50, 50));
      e.down(2, const Offset(80, 50));
      await Future<void>.delayed(const Duration(milliseconds: 260));
      e.up(1);
      e.up(2);

      expect(sink.taps, isEmpty);
      expect(sink.longPresses, isEmpty); // 2nd finger cancelled the timer
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
          GestureAction.panElseCursor);
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

    test('a v1 value that is just the old default yields to the v2 default', () {
      // The whole map was written out whenever the user edited any one row, so
      // these carry no intent — they must not pin the old behaviour forever.
      const raw = '{"touch":{"oneFingerDrag":"moveCursor",'
          '"twoFingerDragH":"panCanvas","threeFingerTap":"none"}}';
      final m = GestureMap.fromJson(raw);
      expect(m.action(InteractionUiMode.touch, GestureSlot.oneFingerDrag),
          GestureAction.panElseCursor);
      expect(m.action(InteractionUiMode.touch, GestureSlot.twoFingerDragH),
          GestureAction.none);
      expect(m.action(InteractionUiMode.touch, GestureSlot.threeFingerTap),
          GestureAction.showToolbar);
    });

    test('a one-finger drag cannot bind the dead bare panCanvas', () {
      expect(GestureMap.allowedActions(GestureSlot.oneFingerDrag),
          isNot(contains(GestureAction.panCanvas)));
      // A 1.9.1 config that stored it is carried over, not dropped.
      const raw = '{"_v":2,"pointer":{"oneFingerDrag":"panCanvas"}}';
      final m = GestureMap.fromJson(raw);
      expect(m.action(InteractionUiMode.pointer, GestureSlot.oneFingerDrag),
          GestureAction.panElseCursor);
    });

    test('a v1 value the user actually chose survives the migration', () {
      const raw = '{"touch":{"oneFingerDrag":"scrollWheel",'
          '"threeFingerTap":"escape"}}';
      final m = GestureMap.fromJson(raw);
      expect(m.action(InteractionUiMode.touch, GestureSlot.oneFingerDrag),
          GestureAction.scrollWheel);
      expect(m.action(InteractionUiMode.touch, GestureSlot.threeFingerTap),
          GestureAction.escape);
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
