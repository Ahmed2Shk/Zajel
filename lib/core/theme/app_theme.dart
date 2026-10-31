import 'package:flutter/material.dart';

/// Design tokens from docs/design/README.md ("Night and Lightning").
/// This is the only file that may contain raw color values.
abstract final class _Tokens {
  static const backgroundDark = Color(0xFF0E1116);
  static const surfaceDark = Color(0xFF171B22);
  static const backgroundLight = Color(0xFFF7F8FA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const primary = Color(0xFFC6F432);
  static const secondary = Color(0xFF38BDF8);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFF43F5E);
  static const textDark = Color(0xFFE8EAED);
  static const textLight = Color(0xFF0E1116);

  static const radius = 20.0;
  static const fontArabic = 'IBMPlexSansArabic';
  static const fontLatin = 'Inter';
}

/// Colors that have no slot in [ColorScheme].
@immutable
class ZajelColors extends ThemeExtension<ZajelColors> {
  const ZajelColors({required this.success, required this.onSuccess});

  final Color success;
  final Color onSuccess;

  @override
  ZajelColors copyWith({Color? success, Color? onSuccess}) => ZajelColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
  );

  @override
  ZajelColors lerp(ZajelColors? other, double t) {
    if (other == null) return this;
    return ZajelColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
    );
  }
}

extension ZajelThemeContext on BuildContext {
  ZajelColors get zajelColors => Theme.of(this).extension<ZajelColors>()!;
}

abstract final class AppTheme {
  static ThemeData dark(Locale locale) => _build(Brightness.dark, locale);
  static ThemeData light(Locale locale) => _build(Brightness.light, locale);

  static ThemeData _build(Brightness brightness, Locale locale) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? _Tokens.backgroundDark
        : _Tokens.backgroundLight;
    final surface = isDark ? _Tokens.surfaceDark : _Tokens.surfaceLight;
    final text = isDark ? _Tokens.textDark : _Tokens.textLight;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: _Tokens.primary,
      // Text on the lime primary must be dark in both themes.
      onPrimary: _Tokens.backgroundDark,
      secondary: _Tokens.secondary,
      onSecondary: _Tokens.backgroundDark,
      error: _Tokens.error,
      onError: _Tokens.backgroundDark,
      surface: surface,
      onSurface: text,
    );

    final isArabic = locale.languageCode == 'ar';
    final fontFamily = isArabic ? _Tokens.fontArabic : _Tokens.fontLatin;
    final fontFallback = isArabic ? const [_Tokens.fontLatin] : null;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_Tokens.radius),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      extensions: const [
        ZajelColors(
          success: _Tokens.success,
          onSuccess: _Tokens.backgroundDark,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      listTileTheme: ListTileThemeData(shape: shape),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_Tokens.radius),
          borderSide: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_Tokens.radius),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: shape),
      ),
    );
  }
}
