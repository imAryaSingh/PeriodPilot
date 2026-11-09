import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF2A86C8);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final scheme = brightness == Brightness.dark
        ? baseScheme.copyWith(
            primary: const Color(0xFF79C2F2),
            onPrimary: const Color(0xFF06253B),
            primaryContainer: const Color(0xFF173B56),
            onPrimaryContainer: const Color(0xFFD9EEFC),
            secondary: const Color(0xFF7DC8BF),
            onSecondary: const Color(0xFF082A27),
            secondaryContainer: const Color(0xFF173A37),
            onSecondaryContainer: const Color(0xFFC8EDE7),
            surface: const Color(0xFF0D1420),
            onSurface: const Color(0xFFE7EDF5),
            onSurfaceVariant: const Color(0xFFA8B5C7),
            surfaceContainerLowest: const Color(0xFF090F18),
            surfaceContainerLow: const Color(0xFF111A28),
            surfaceContainer: const Color(0xFF151F2E),
            surfaceContainerHigh: const Color(0xFF1A2636),
            surfaceContainerHighest: const Color(0xFF202D3F),
            outline: const Color(0xFF68788D),
            outlineVariant: const Color(0xFF334256),
          )
        : baseScheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
      ),
    );
  }
}
