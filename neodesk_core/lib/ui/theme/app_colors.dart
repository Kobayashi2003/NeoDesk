import 'package:flutter/material.dart';

/// Spotify-flavoured dark palette. See DESIGN.md §2.1.
///
/// Single source of truth for colour — widgets must not hardcode hex values.
class AppColors {
  AppColors._();

  // ---- Background / surface (Spotify layering) ----
  static const bgBase = Color(0xFF121212);
  static const bgElevated1 = Color(0xFF181818);
  static const bgElevated2 = Color(0xFF282828);
  static const bgInput = Color(0xFF2A2A2A);

  // ---- Accent ----
  static const accent = Color(0xFF1ED760); // Spotify green
  static const accentPressed = Color(0xFF1AC957);
  static const accentMuted = Color(0x291ED760); // accent @ 16%

  // ---- Text ----
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const textDisabled = Color(0xFF6A6A6A);
  static const textOnAccent = Color(0xFF000000);

  // ---- Semantic ----
  static const danger = Color(0xFFF0364F);
  static const online = Color(0xFF1ED760);
  static const offline = Color(0xFF6A6A6A);

  // ---- Lines ----
  static const divider = Color(0xFF2A2A2A);
  static const border = Color(0xFF3E3E3E);
}

/// Semi-transparent colours for the remote-session overlay chrome (§2.1 note).
class OverlayColors {
  OverlayColors._();

  static const barBg = Color(0xCC121212); // base @ 80%
  static const ballBg = Color(0xCC282828);
}
