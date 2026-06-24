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

  static const display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static const mono = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 1.0,
  );

  /// Builds the Material [TextTheme] from the scale above.
  static TextTheme textTheme() => const TextTheme(
        displaySmall: display,
        titleLarge: title,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: button,
      ).apply(fontFamily: fontFamily);
}
