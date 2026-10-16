import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Inter type scale from the design system. Tabular figures are enabled for
/// numeric/telemetry styles (roll numbers, timestamps, distances) so digits
/// do not jitter during live refreshes.
abstract final class AppTextStyles {
  static const _base = TextStyle(
    fontFamily: 'Inter',
    color: AppColors.textPrimary,
    debugLabel: 'Inter',
  );

  static TextStyle _t(
    double size, {
    double? lineHeight,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
    bool tabular = false,
  }) {
    return _base.copyWith(
      fontSize: size,
      height: lineHeight != null ? lineHeight / size : null,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  // Headlines
  static final headlineLg = _t(
    28,
    lineHeight: 34,
    weight: FontWeight.w700,
    letterSpacing: -0.56,
  );
  static final headlineMd = _t(
    22,
    lineHeight: 28,
    weight: FontWeight.w600,
    letterSpacing: -0.33,
  );
  static final headlineSm = _t(
    18,
    lineHeight: 24,
    weight: FontWeight.w600,
    letterSpacing: -0.18,
  );

  // Body
  static final bodyLg = _t(16, lineHeight: 24, letterSpacing: -0.08);
  static final bodyMd = _t(14, lineHeight: 20);
  static final bodySm = _t(12, lineHeight: 16, letterSpacing: 0.12);

  // Labels
  static final labelLg = _t(
    14,
    lineHeight: 18,
    weight: FontWeight.w600,
    letterSpacing: 0.07,
  );
  static final labelMd = _t(
    12,
    lineHeight: 16,
    weight: FontWeight.w600,
    letterSpacing: 0.24,
  );
  static final labelSm = _t(
    11,
    lineHeight: 14,
    weight: FontWeight.w500,
    letterSpacing: 0.33,
  );

  // Data
  static final dataMetric = _t(
    20,
    lineHeight: 26,
    weight: FontWeight.w600,
    letterSpacing: -0.2,
    tabular: true,
  );
  static final tabular = _t(14, lineHeight: 20, tabular: true);
  static final tabularSm = _t(12, lineHeight: 16, tabular: true);
  static final tabularLg = _t(
    16,
    lineHeight: 24,
    weight: FontWeight.w600,
    tabular: true,
  );

  /// Uppercase micro-label (label-sm + caps), e.g. "VERIFICATION STEP".
  static TextStyle microLabel({Color color = AppColors.textSecondary}) =>
      labelSm.copyWith(color: color, letterSpacing: 0.8, height: 14 / 11);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.textSecondary,
    onSecondary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.cardHighest,
    outline: Color(0xFF707977),
    outlineVariant: Color(0xFFBFC8C6),
  );

  const focusRing = BorderSide(color: AppColors.primary, width: 1);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.18,
        color: AppColors.textPrimary,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.cardHighest,
            disabledForegroundColor: AppColors.textDisabled,
            minimumSize: const Size.fromHeight(48),
            textStyle: AppTextStyles.labelLg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              Colors.white.withValues(alpha: 0.08),
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.card,
        minimumSize: const Size.fromHeight(48),
        textStyle: AppTextStyles.labelLg,
        side: const BorderSide(color: AppColors.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppTextStyles.labelLg,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: AppTextStyles.bodyLg.copyWith(color: AppColors.textDisabled),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: focusRing,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.error),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.card,
      ),
      checkColor: WidgetStateProperty.all(Colors.white),
      visualDensity: VisualDensity.compact,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.cardHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(AppColors.hairline),
      thumbColor: WidgetStateProperty.all(Colors.white),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.card,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );
}
