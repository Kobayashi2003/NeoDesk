import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Text-size multiplier for neodesk's own UI. The root wraps the tree in a
/// `MediaQuery` carrying `TextScaler.linear(appTextScale.value)` and listens for
/// changes. Mirrors the `appBrightness` / `appLocale` reactive pattern.
final ValueNotifier<double> appTextScale = ValueNotifier(1.0);

/// Bounds for the Font size setting; 1.0 is the normal size. The ceiling is
/// above 1.4 because the base scale itself came down a fifth in 1.11.2 — this
/// keeps the same headroom for anyone who wants larger text.
const double kTextScaleMin = 0.8, kTextScaleMax = 1.6;

/// Apply a stored Font-size setting (a decimal string) to the live UI.
void applyTextScale(String setting) => appTextScale.value =
    (double.tryParse(setting) ?? 1.0).clamp(kTextScaleMin, kTextScaleMax);

/// Type scale. See DESIGN.md §2.2.
///
/// Decision (DESIGN §9): use the system font, recover the Spotify feel through
/// weight / spacing. `fontFamily` is left null so each platform uses its
/// default; swap in 'Inter' / 'Montserrat' here later without touching callers.
class AppTypography {
  AppTypography._();

  static const String? fontFamily = null;

  /// The whole scale was taken down a fifth in 1.11.2: what used to need the
  /// Font-size setting at 80% is now simply the normal size. Kept as a factor on
  /// the original numbers so the ratios between the steps stay visible.
  ///
  /// The Font-size setting ([appTextScale]) multiplies on top of this.
  static const _sizeScale = 0.8;

  // Colour-bearing styles follow the active brightness via [AppColors], but are
  // memoised per brightness so accessing them in list builders doesn't allocate a
  // new TextStyle every frame — they're only rebuilt when the theme flips. The
  // colourless [button] stays a plain const.
  static Brightness? _cachedFor;
  static late TextStyle _display, _title, _body, _caption, _mono;

  static void _ensureCache() {
    if (_cachedFor == appBrightness.value) return;
    _cachedFor = appBrightness.value;
    _display = const TextStyle(
      fontSize: 28 * _sizeScale,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      height: 1.1,
    ).copyWith(color: AppColors.textPrimary);
    _title = const TextStyle(
      fontSize: 20 * _sizeScale,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ).copyWith(color: AppColors.textPrimary);
    _body = const TextStyle(
      fontSize: 15 * _sizeScale,
      fontWeight: FontWeight.w500,
    ).copyWith(color: AppColors.textPrimary);
    _caption = const TextStyle(
      fontSize: 13 * _sizeScale,
      fontWeight: FontWeight.w400,
    ).copyWith(color: AppColors.textSecondary);
    _mono = const TextStyle(
      fontSize: 14 * _sizeScale,
      fontWeight: FontWeight.w500,
      fontFeatures: [FontFeature.tabularFigures()],
      letterSpacing: 1.0,
    ).copyWith(color: AppColors.textPrimary);
  }

  static TextStyle get display {
    _ensureCache();
    return _display;
  }

  static TextStyle get title {
    _ensureCache();
    return _title;
  }

  static TextStyle get body {
    _ensureCache();
    return _body;
  }

  static TextStyle get caption {
    _ensureCache();
    return _caption;
  }

  static const button = TextStyle(
    fontSize: 15 * _sizeScale,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static TextStyle get mono {
    _ensureCache();
    return _mono;
  }

  /// Builds the Material [TextTheme] from the scale above.
  static TextTheme textTheme() => TextTheme(
        displaySmall: display,
        titleLarge: title,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: button,
      ).apply(fontFamily: fontFamily);
}
