import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

/// One brightness' worth of the neodesk colour set. Widgets never read this
/// directly — they go through [AppColors], which forwards to the active palette
/// so a theme switch re-colours the whole UI. See DESIGN.md §2.1.
class _Palette {
  const _Palette({
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
const _dark = _Palette(
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
const _light = _Palette(
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

/// Active brightness for neodesk's own UI. The root ([NeodeskEntry]) listens and
/// re-themes the whole UI when it changes; [AppColors]/[AppTypography] read it.
/// Mirrors the `appLocale` reactive pattern. Defaults to dark.
final ValueNotifier<Brightness> appBrightness = ValueNotifier(Brightness.dark);

_Palette get _p => appBrightness.value == Brightness.light ? _light : _dark;

/// Apply a stored Theme setting (`system` / `light` / `dark`) to the live UI.
/// `system` resolves to the device brightness (snapshot — re-applied on change).
void applyThemeSetting(String setting) {
  appBrightness.value = switch (setting) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => PlatformDispatcher.instance.platformBrightness,
  };
}

/// Brightness-aware palette. Single source of truth for colour — widgets must
/// not hardcode hex values. Each field forwards to the active [_Palette] so a
/// theme switch re-colours everything. See DESIGN.md §2.1.
class AppColors {
  AppColors._();

  // ---- Background / surface ----
  static Color get bgBase => _p.bgBase;
  static Color get bgElevated1 => _p.bgElevated1;
  static Color get bgElevated2 => _p.bgElevated2;
  static Color get bgInput => _p.bgInput;

  // ---- Accent ----
  static Color get accent => _p.accent;
  static Color get accentPressed => _p.accentPressed;
  static Color get accentMuted => _p.accentMuted;

  // ---- Text ----
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textDisabled => _p.textDisabled;
  static Color get textOnAccent => _p.textOnAccent;

  // ---- Semantic ----
  static Color get danger => _p.danger;
  static Color get online => _p.online;
  static Color get offline => _p.offline;

  // ---- Lines ----
  static Color get divider => _p.divider;
  static Color get border => _p.border;
}

/// Semi-transparent colours for the remote-session overlay chrome. Kept dark
/// regardless of theme: the chrome floats over arbitrary remote video, where a
/// dark scrim stays readable. (§2.1 note)
class OverlayColors {
  OverlayColors._();

  static const barBg = Color(0xCC121212); // base @ 80%
  static const ballBg = Color(0xCC282828);
}
