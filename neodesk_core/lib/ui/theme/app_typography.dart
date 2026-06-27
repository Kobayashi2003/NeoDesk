import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale. See DESIGN.md §2.2.
///
/// Decision (DESIGN §9): use the system font, recover the Spotify feel through
/// weight / spacing. `fontFamily` is left null so each platform uses its
/// default; swap in 'Inter' / 'Montserrat' here later without touching callers.
class AppTypography {
  AppTypography._();

  static const String? fontFamily = null;

  // Colour-bearing styles are getters (not const) so they follow the active
  // brightness via [AppColors]; the colourless [button] stays const.
  static TextStyle get display => const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.1,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get title => const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get body => const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ).copyWith(color: AppColors.textPrimary);

  static TextStyle get caption => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ).copyWith(color: AppColors.textSecondary);

  static const button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static TextStyle get mono => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
        letterSpacing: 1.0,
      ).copyWith(color: AppColors.textPrimary);

  /// Builds the Material [TextTheme] from the scale above.
  static TextTheme textTheme() => TextTheme(
        displaySmall: display,
        titleLarge: title,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: button,
      ).apply(fontFamily: fontFamily);
}
