import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:neodesk_core/neodesk_core.dart';

/// User-tunable thresholds for the gesture state machine ([GestureEngine]).
///
/// Persisted as JSON in [ConfigStore] (key [ConfigKeys.gestureTuning]) and read
/// once per session; the Gesture-sensitivity settings page edits them live with a
/// test area. See DESIGN.md §4.2.
@immutable
class GestureTuning {
  const GestureTuning({
    this.longPressMs = 500,
    this.settleMs = 150,
    this.dragSlop = 12,
    this.tapSlop = 16,
    this.zoomActivate = 24,
    this.earlyTap = true,
  });

  /// Schema version of the persisted JSON. v2 flipped [earlyTap] on by default;
  /// v3 renamed `collectMs` back to [settleMs].
  static const _schema = 3;

  /// How long a finger must stay down (without moving past [dragSlop]) to count
  /// as a long-press rather than a tap.
  ///
  /// It doubles as the multi-finger tap window: everything before the long press
  /// would fire is the multi-finger trigger period (see `GestureEngine`).
  final int longPressMs;

  /// How long after the *first* touch two-finger continuous actions
  /// (scroll/pinch/pan) are withheld, letting the gesture settle so a 3rd or 4th
  /// finger arriving a beat later can still pre-empt them.
  ///
  /// It does *not* bound which fingers join the gesture — [longPressMs] does.
  final int settleMs;

  /// Movement (px) before a touch counts as a drag (and cancels the long-press).
  final double dragSlop;

  /// Max accumulated travel (px) for a multi-finger touch to still count as a tap.
  final double tapSlop;

  /// Finger-spread change (px) that counts as a real pinch/zoom.
  final double zoomActivate;

  /// Fire the tap as soon as the *first* finger lifts, instead of waiting for
  /// every finger to leave the screen. The gesture is fully decided by then: the
  /// collection window has fixed the finger count and the anchor.
  final bool earlyTap;

  static const defaults = GestureTuning();

  Duration get longPress => Duration(milliseconds: longPressMs);
  Duration get settle => Duration(milliseconds: settleMs);

  GestureTuning copyWith({
    int? longPressMs,
    int? settleMs,
    double? dragSlop,
    double? tapSlop,
    double? zoomActivate,
    bool? earlyTap,
  }) =>
      GestureTuning(
        longPressMs: longPressMs ?? this.longPressMs,
        settleMs: settleMs ?? this.settleMs,
        dragSlop: dragSlop ?? this.dragSlop,
        tapSlop: tapSlop ?? this.tapSlop,
        zoomActivate: zoomActivate ?? this.zoomActivate,
        earlyTap: earlyTap ?? this.earlyTap,
      );

  Map<String, dynamic> toJson() => {
        '_v': _schema,
        'longPressMs': longPressMs,
        'settleMs': settleMs,
        'dragSlop': dragSlop,
        'tapSlop': tapSlop,
        'zoomActivate': zoomActivate,
        'earlyTap': earlyTap,
      };

  static GestureTuning fromJson(Map<String, dynamic> j) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    int i(String k, int f) => (j[k] as num?)?.round() ?? f;
    final version = (j['_v'] as num?)?.toInt() ?? 1;
    return GestureTuning(
      longPressMs: i('longPressMs', 500),
      // v3 restored the name `settleMs`, so only trust that key from v3 on: a v1
      // record's `settleMs` is the *old* window (timed from the second finger,
      // default 80) and must not be resurrected. v1/v2 carry the same window
      // under the name `collectMs`. Pre-1.9.2 `multiTapMs` is gone entirely.
      settleMs: version >= 3 ? i('settleMs', 150) : i('collectMs', 150),
      dragSlop: d('dragSlop', 12),
      tapSlop: d('tapSlop', 16),
      zoomActivate: d('zoomActivate', 24),
      // v2 turned early-tap on. The page rewrites the whole record on any edit,
      // so a pre-v2 `false` is indistinguishable from the old default.
      earlyTap: version < 2 || j['earlyTap'] == true,
    );
  }
}

/// Loads/saves [GestureTuning] to [ConfigStore]; falls back to [GestureTuning.defaults].
abstract final class GestureTuningStore {
  static GestureTuning load(ConfigStore cfg) {
    final raw = cfg.get(ConfigKeys.gestureTuning);
    if (raw.isEmpty) return GestureTuning.defaults;
    try {
      return GestureTuning.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('neodesk: invalid gesture tuning, using defaults: $e');
      return GestureTuning.defaults;
    }
  }

  static void save(ConfigStore cfg, GestureTuning t) =>
      cfg.set(ConfigKeys.gestureTuning, jsonEncode(t.toJson()));
}
