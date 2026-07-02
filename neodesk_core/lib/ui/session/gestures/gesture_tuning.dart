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
    this.multiTapMs = 250,
    this.settleMs = 80,
    this.dragSlop = 12,
    this.tapSlop = 16,
    this.zoomActivate = 24,
    this.earlyTap = false,
  });

  /// How long a finger must stay down (without moving past [dragSlop]) to count
  /// as a long-press rather than a tap.
  final int longPressMs;

  /// Max duration for a multi-finger gesture to still register as a tap.
  final int multiTapMs;

  /// Settle window after a 2-finger gesture begins, during which two-finger
  /// continuous actions are withheld so a 3rd/4th finger can pre-empt them.
  final int settleMs;

  /// Movement (px) before a touch counts as a drag (and cancels the long-press).
  final double dragSlop;

  /// Max accumulated travel (px) for a multi-finger touch to still count as a tap.
  final double tapSlop;

  /// Finger-spread change (px) that counts as a real pinch/zoom.
  final double zoomActivate;

  /// Fire the tap as soon as the *first* finger lifts (the gesture is already
  /// decided by then), instead of waiting for every finger to leave the screen.
  final bool earlyTap;

  static const defaults = GestureTuning();

  Duration get longPress => Duration(milliseconds: longPressMs);
  Duration get multiTap => Duration(milliseconds: multiTapMs);
  Duration get settle => Duration(milliseconds: settleMs);

  GestureTuning copyWith({
    int? longPressMs,
    int? multiTapMs,
    int? settleMs,
    double? dragSlop,
    double? tapSlop,
    double? zoomActivate,
    bool? earlyTap,
  }) =>
      GestureTuning(
        longPressMs: longPressMs ?? this.longPressMs,
        multiTapMs: multiTapMs ?? this.multiTapMs,
        settleMs: settleMs ?? this.settleMs,
        dragSlop: dragSlop ?? this.dragSlop,
        tapSlop: tapSlop ?? this.tapSlop,
        zoomActivate: zoomActivate ?? this.zoomActivate,
        earlyTap: earlyTap ?? this.earlyTap,
      );

  Map<String, dynamic> toJson() => {
        'longPressMs': longPressMs,
        'multiTapMs': multiTapMs,
        'settleMs': settleMs,
        'dragSlop': dragSlop,
        'tapSlop': tapSlop,
        'zoomActivate': zoomActivate,
        'earlyTap': earlyTap,
      };

  static GestureTuning fromJson(Map<String, dynamic> j) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    int i(String k, int f) => (j[k] as num?)?.round() ?? f;
    return GestureTuning(
      longPressMs: i('longPressMs', 500),
      multiTapMs: i('multiTapMs', 250),
      settleMs: i('settleMs', 80),
      dragSlop: d('dragSlop', 12),
      tapSlop: d('tapSlop', 16),
      zoomActivate: d('zoomActivate', 24),
      earlyTap: j['earlyTap'] == true,
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
