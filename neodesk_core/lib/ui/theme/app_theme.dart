import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'dimens.dart';

/// Assembles the global dark [ThemeData]. See DESIGN.md §7.
class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.textOnAccent,
      secondary: AppColors.accent,
      surface: AppColors.bgElevated1,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ).copyWith(surfaceTint: Colors.transparent);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      colorScheme: scheme,
      textTheme: AppTypography.textTheme(),
      dividerColor: AppColors.divider,
      splashFactory: InkRipple.splashFactory,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgElevated2,
        modalBackgroundColor: AppColors.bgElevated2,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Dimens.rSheet)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
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
