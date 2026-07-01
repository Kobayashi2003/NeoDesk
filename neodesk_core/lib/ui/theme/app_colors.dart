import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// One brightness' worth of the neodesk colour set. Widgets read through
/// [AppColors] (the active palette); theme builders that must produce a theme for
/// a *specific* brightness use [paletteFor]. See DESIGN.md §2.1.
class NeodeskPalette {
  const NeodeskPalette({
    required this.bgBase,
    required this.bgElevated1,
    required this.bgElevated2,
    required this.bgInput,
    required this.accent,
    required this.accentPressed,
    required this.accentMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.textOnAccent,
    required this.danger,
    required this.online,
    required this.offline,
    required this.divider,
    required this.border,
  });

  final Color bgBase, bgElevated1, bgElevated2, bgInput;
  final Color accent, accentPressed, accentMuted;
  final Color textPrimary, textSecondary, textDisabled, textOnAccent;
  final Color danger, online, offline;
  final Color divider, border;
}

/// Spotify-flavoured dark palette (the original look).
const kDarkPalette = NeodeskPalette(
  bgBase: Color(0xFF121212),
  bgElevated1: Color(0xFF181818),
  bgElevated2: Color(0xFF282828),
  bgInput: Color(0xFF2A2A2A),
  accent: Color(0xFF1ED760), // Spotify green
  accentPressed: Color(0xFF1AC957),
  accentMuted: Color(0x291ED760), // accent @ 16%
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xFFB3B3B3),
  textDisabled: Color(0xFF6A6A6A),
  textOnAccent: Color(0xFF000000),
  danger: Color(0xFFF0364F),
  online: Color(0xFF1ED760),
  offline: Color(0xFF6A6A6A),
  divider: Color(0xFF2A2A2A),
  border: Color(0xFF3E3E3E),
);

/// Light counterpart. A slightly deeper green keeps the accent legible on light
/// surfaces (with white text on it); neutrals invert.
const kLightPalette = NeodeskPalette(
  bgBase: Color(0xFFF5F6F8),
  bgElevated1: Color(0xFFFFFFFF),
  bgElevated2: Color(0xFFFFFFFF),
  bgInput: Color(0xFFECEEF1),
  accent: Color(0xFF12B85C),
  accentPressed: Color(0xFF0FA350),
  accentMuted: Color(0x2912B85C),
  textPrimary: Color(0xFF18191C),
  textSecondary: Color(0xFF5B5F66),
  textDisabled: Color(0xFFA0A4AC),
  textOnAccent: Color(0xFFFFFFFF),
  danger: Color(0xFFD32338),
  online: Color(0xFF12B85C),
  offline: Color(0xFFA0A4AC),
  divider: Color(0xFFE5E7EB),
  border: Color(0xFFD6D9DE),
);

/// The palette for a specific brightness (for building a theme regardless of the
/// currently-active one — e.g. the engine's light & dark theme slots).
NeodeskPalette paletteFor(Brightness b) =>
    b == Brightness.light ? kLightPalette : kDarkPalette;

/// Active brightness for neodesk's own UI. The root ([NeodeskEntry]) listens and
/// re-themes the whole UI when it changes; [AppColors]/[AppTypography] read it.
/// Mirrors the `appLocale` reactive pattern. Defaults to dark.
final ValueNotifier<Brightness> appBrightness = ValueNotifier(Brightness.dark);

/// The current Theme *setting* (`system` / `light` / `dark`), kept so the system
/// observer knows whether to track the device brightness.
String _themeSetting = 'dark';

/// Apply a stored Theme setting to the live UI. `system` tracks the device
/// brightness — including later changes, via [_BrightnessObserver].
void applyThemeSetting(String setting) {
  _themeSetting = setting;
  _ensureSystemObserver();
  _refreshBrightness();
}

void _refreshBrightness() {
  appBrightness.value = switch (_themeSetting) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => PlatformDispatcher.instance.platformBrightness,
  };
}

bool _observerAdded = false;
final _BrightnessObserver _observer = _BrightnessObserver();

void _ensureSystemObserver() {
  if (_observerAdded) return;
  _observerAdded = true;
  WidgetsBinding.instance.addObserver(_observer);
}

/// Re-resolves the brightness when the OS theme flips, but only while the setting
/// is `system` (so an explicit Light/Dark choice is never overridden).
class _BrightnessObserver with WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() {
    if (_themeSetting == 'system') _refreshBrightness();
  }
}

NeodeskPalette get _active => paletteFor(appBrightness.value);

/// Brightness-aware palette. Single source of truth for colour — widgets must
/// not hardcode hex values. Each field forwards to the active [NeodeskPalette].
class AppColors {
  AppColors._();

  // ---- Background / surface ----
  static Color get bgBase => _active.bgBase;
  static Color get bgElevated1 => _active.bgElevated1;
  static Color get bgElevated2 => _active.bgElevated2;
  static Color get bgInput => _active.bgInput;

  // ---- Accent ----
  static Color get accent => _active.accent;
  static Color get accentPressed => _active.accentPressed;
  static Color get accentMuted => _active.accentMuted;

  // ---- Text ----
  static Color get textPrimary => _active.textPrimary;
  static Color get textSecondary => _active.textSecondary;
  static Color get textDisabled => _active.textDisabled;
  static Color get textOnAccent => _active.textOnAccent;

  // ---- Semantic ----
  static Color get danger => _active.danger;
  static Color get online => _active.online;
  static Color get offline => _active.offline;

  // ---- Lines ----
  static Color get divider => _active.divider;
  static Color get border => _active.border;
}
