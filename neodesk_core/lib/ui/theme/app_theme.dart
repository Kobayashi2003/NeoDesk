import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'dimens.dart';

/// Assembles the global [ThemeData] for either brightness. See DESIGN.md §7.
///
/// Colours come from [AppColors], which forwards to the palette selected by
/// `appBrightness`; callers build with the same brightness that is currently
/// active, so the two stay in step.
class AppTheme {
  AppTheme._();

  static ThemeData dark() => build(Brightness.dark);
  static ThemeData light() => build(Brightness.light);

  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: AppColors.textOnAccent,
      secondary: AppColors.accent,
      onSecondary: AppColors.textOnAccent,
      surface: AppColors.bgElevated1,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    ).copyWith(surfaceTint: Colors.transparent);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme(),
      dividerColor: AppColors.divider,
      splashFactory: InkRipple.splashFactory,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgElevated2,
        modalBackgroundColor: AppColors.bgElevated2,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Dimens.rSheet)),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgBase,
        selectedItemColor: AppColors.textPrimary,
        unselectedItemColor: AppColors.textDisabled,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.textOnAccent
              : AppColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.bgInput,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
