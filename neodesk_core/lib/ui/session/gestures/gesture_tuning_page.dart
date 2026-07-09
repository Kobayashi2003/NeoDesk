import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import 'gesture_engine.dart';
import 'gesture_map.dart';
import 'gesture_tuning.dart';

/// Adjusts the gesture-recognition thresholds ([GestureTuning]) with a live test
/// area that runs the real [GestureEngine] on the current (unsaved) values, plus
/// a reset-to-defaults action. Applies to the next session opened.
class GestureTuningPage extends StatefulWidget {
  const GestureTuningPage({super.key, required this.config});

  final ConfigStore config;

  @override
  State<GestureTuningPage> createState() => _GestureTuningPageState();
}

class _GestureTuningPageState extends State<GestureTuningPage> {
  late GestureTuning _t = GestureTuningStore.load(widget.config);

  void _update(GestureTuning next) {
    setState(() => _t = next);
    GestureTuningStore.save(widget.config, next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Gesture sensitivity')),
        actions: [
          TextButton(
            onPressed: () => _update(GestureTuning.defaults),
            child: Text(tr('Reset'),
                style: AppTypography.button.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Test area stays pinned above the sliders so you can feel each change.
          Padding(
            padding: const EdgeInsets.all(Dimens.s16),
            child: _GestureTestArea(tuning: _t),
          ),
          Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Dimens.s8),
              children: [
                _switch('Trigger on first finger up',
                    'Fire the tap the moment a finger lifts', _t.earlyTap,
                    (v) => _update(_t.copyWith(earlyTap: v))),
                _intRow('Long-press time', _t.longPressMs, 200, 1000, 'ms',
                    (v) => _update(_t.copyWith(longPressMs: v))),
                _intRow('Multi-tap time limit', _t.multiTapMs, 150, 600, 'ms',
                    (v) => _update(_t.copyWith(multiTapMs: v))),
                _intRow('Two-finger settle', _t.settleMs, 0, 200, 'ms',
                    (v) => _update(_t.copyWith(settleMs: v))),
                _dblRow('Drag threshold', _t.dragSlop, 4, 30, 'px',
                    (v) => _update(_t.copyWith(dragSlop: v))),
                _dblRow('Tap tolerance', _t.tapSlop, 8, 40, 'px',
                    (v) => _update(_t.copyWith(tapSlop: v))),
                _dblRow('Pinch threshold', _t.zoomActivate, 10, 60, 'px',
                    (v) => _update(_t.copyWith(zoomActivate: v))),
                const SizedBox(height: Dimens.s24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _intRow(String label, int value, int min, int max, String unit,
          ValueChanged<int> onChanged) =>
      _sliderRow(label, '$value $unit', value.toDouble(), min.toDouble(),
          max.toDouble(), (v) => onChanged(v.round()));

  Widget _dblRow(String label, double value, double min, double max,
          String unit, ValueChanged<double> onChanged) =>
      _sliderRow(label, '${value.toStringAsFixed(0)} $unit', value, min, max,
          onChanged);

  Widget _sliderRow(String label, String valueText, double value, double min,
          double max, ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Dimens.pageInset, vertical: Dimens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr(label), style: AppTypography.body)),
                Text(valueText, style: AppTypography.caption),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                thumbColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );

  Widget _switch(String label, String sub, bool value,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Dimens.pageInset),
        title: Text(tr(label), style: AppTypography.body),
        subtitle: Text(tr(sub), style: AppTypography.caption),
        value: value,
        activeColor: AppColors.accent,
        onChanged: onChanged,
      );
}

/// A sandbox that runs the real [GestureEngine] on [tuning] and shows what it
/// recognises (and the live finger count) — no session needed.
class _GestureTestArea extends StatefulWidget {
  const _GestureTestArea({required this.tuning});

  final GestureTuning tuning;

  @override
  State<_GestureTestArea> createState() => _GestureTestAreaState();
}

class _GestureTestAreaState extends State<_GestureTestArea> {
  late final GestureEngine _engine =
      GestureEngine(tuning: widget.tuning, sink: _TestSink(_report));
  String _last = '';
  int _fingers = 0;

  void _report(String s) {
    if (mounted) setState(() => _last = s);
  }

  @override
  void didUpdateWidget(_GestureTestArea old) {
    super.didUpdateWidget(old);
    _engine.tuning = widget.tuning; // live-apply slider changes
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  void _refreshFingers() =>
      setState(() => _fingers = _engine.fingerCount);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.bgElevated1,
        borderRadius: BorderRadius.circular(Dimens.rCard),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _engine.down(e.pointer, e.localPosition);
          _refreshFingers();
        },
        onPointerMove: (e) => _engine.move(e.pointer, e.localPosition, e.delta),
        onPointerUp: (e) {
          _engine.up(e.pointer);
          _refreshFingers();
        },
        onPointerCancel: (e) {
          _engine.cancel(e.pointer);
          _refreshFingers();
        },
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _last.isEmpty ? tr('Try gestures here') : _last,
                style: AppTypography.title.copyWith(
                    color: _last.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.accent),
              ),
              const SizedBox(height: Dimens.s8),
              Text(trArg('Fingers: {}', _fingers),
                  style: AppTypography.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns recognised gestures into a human-readable label for the test area.
class _TestSink extends GestureSink {
  _TestSink(this.report);

  final void Function(String) report;

  @override
  void tap(GestureSlot slot, Offset at) => report(slot.label);

  @override
  LongPressOutcome longPress(GestureSlot slot, Offset at) {
    report(tr('Long press'));
    // Let the hold path run so a following drag shows up too.
    return LongPressOutcome.holding;
  }

  @override
  void holdDrag(Offset absPos, Offset delta) => report(tr('Long-press drag'));

  @override
  void continuous(GestureSlot slot,
          {Offset delta = Offset.zero,
          Offset absPos = Offset.zero,
          double zoom = 1.0,
          Offset focal = Offset.zero}) =>
      report(slot.label);
}
