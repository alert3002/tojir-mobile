import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_shape.dart';

/// Візуальна система Tojir: виразний M3, спокійна палітра, типографіка рівня продукту 2027.
ThemeData buildTojirTheme({
  required Brightness brightness,
  Color? darkSurface,
}) {
  const seed = Color(0xFF4F46E5);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    surface: darkSurface,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  final materialBase = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
  final baseText = GoogleFonts.plusJakartaSansTextTheme(materialBase).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  final r = AppShape.radius;
  final rLg = AppShape.radiusLg;

  final scaffoldBg = brightness == Brightness.dark
      ? (darkSurface ?? colorScheme.surface)
      : const Color(0xFFF0F4FA);

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scaffoldBg,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: baseText,
    splashFactory: InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant.withValues(alpha: 0.45), thickness: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      shadowColor: colorScheme.shadow.withValues(alpha: brightness == Brightness.dark ? 0.35 : 0.12),
      surfaceTintColor: colorScheme.surfaceTint.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: brightness == Brightness.dark ? 0.2 : 0.35)),
      ),
      margin: EdgeInsets.zero,
      color: brightness == Brightness.dark ? colorScheme.surfaceContainerLow : colorScheme.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: brightness == Brightness.dark ? 0.35 : 0.55),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(r)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(r))),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.22)),
      labelStyle: baseText.labelLarge ?? const TextStyle(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      elevation: 3,
      backgroundColor: colorScheme.surfaceContainerHigh,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppShape.sheetTop),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
      backgroundColor: colorScheme.surfaceContainerHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      elevation: 3,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      elevation: 2,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
