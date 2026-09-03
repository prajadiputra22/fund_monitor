import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF00142F);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF006A61);
  static const Color background = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color onSurface = Color(0xFF0B1C30);
  static const Color onSurfaceVariant = Color(0xFF44474E);
  static const Color outline = Color(0xFF74777F);
  static const Color error = Color(0xFFBA1A1A);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.secondary,
        surface: AppColors.background,
        error: AppColors.error,
      ),
    );
  }
}