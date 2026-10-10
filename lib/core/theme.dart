import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this.preferences)
    : super(
        ThemeMode.values.firstWhere(
          (t) => t.name == preferences.getString('theme'),
          orElse: () => ThemeMode.dark,
        ),
      );
  final SharedPreferences preferences;
  Future<void> change(ThemeMode mode) async {
    await preferences.setString('theme', mode.name);
    emit(mode);
  }
}

ThemeData twonTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xffdc143c),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xffff91a6) : const Color(0xffbd1033),
        onPrimary: dark ? const Color(0xff181b2e) : Colors.white,
        onSurface: dark ? const Color(0xffeef2fa) : const Color(0xff19263f),
        onSurfaceVariant: dark
            ? const Color(0xffaab8cf)
            : const Color(0xff607089),
        surface: dark ? const Color(0xff19263f) : Colors.white,
        primaryContainer: dark
            ? const Color(0xff34304b)
            : const Color(0xffffe3eb),
        onPrimaryContainer: dark
            ? const Color(0xffffc4d1)
            : const Color(0xff78132c),
        secondaryContainer: dark
            ? const Color(0xff293851)
            : const Color(0xffe8edf6),
        onSecondaryContainer: dark
            ? const Color(0xffe2eafa)
            : const Color(0xff263650),
        surfaceContainerLowest: dark ? const Color(0xff0e182d) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff15213a)
            : const Color(0xfffafbfe),
        surfaceContainerHigh: dark
            ? const Color(0xff25334c)
            : const Color(0xffedf1f8),
        surfaceContainerHighest: dark
            ? const Color(0xff2c3b55)
            : const Color(0xffe6ecf5),
        outline: dark ? const Color(0xff61718c) : const Color(0xff77849a),
        outlineVariant: dark
            ? const Color(0xff33425b)
            : const Color(0xffdbe2ed),

        surfaceContainer: dark
            ? const Color(0xff22304a)
            : const Color(0xfff2f4f9),
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(
      color: dark ? const Color(0xff465572) : const Color(0xffdbe1ea),
    ),
  );

  // Inter font: Bold/ExtraBold for titles, Regular for body
  final textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w800,
      fontSize: 57,
      height: 1.12,
      letterSpacing: -0.25,
      color: scheme.onSurface,
    ),
    displayMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w800,
      fontSize: 45,
      height: 1.16,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    displaySmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      fontSize: 36,
      height: 1.22,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      fontSize: 32,
      height: 1.25,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      fontSize: 28,
      height: 1.29,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.33,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w700,
      fontSize: 22,
      height: 1.27,
      letterSpacing: 0,
      color: scheme.onSurface,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      fontSize: 16,
      height: 1.5,
      letterSpacing: 0.15,
      color: scheme.onSurface,
    ),
    titleSmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.43,
      letterSpacing: 0.1,
      color: scheme.onSurface,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 16,
      height: 1.5,
      letterSpacing: 0.5,
      color: scheme.onSurface,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      height: 1.43,
      letterSpacing: 0.25,
      color: scheme.onSurface,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 12,
      height: 1.33,
      letterSpacing: 0.4,
      color: scheme.onSurface,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.43,
      letterSpacing: 0.1,
      color: scheme.onSurface,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
      fontSize: 12,
      height: 1.33,
      letterSpacing: 0.5,
      color: scheme.onSurface,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w500,
      fontSize: 11,
      height: 1.45,
      letterSpacing: 0.5,
      color: scheme.onSurface,
    ),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: dark
        ? const Color(0xff111d36)
        : const Color(0xfff5f7fc),
    fontFamily: 'Inter',
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .55),
      thickness: .8,
      space: 24,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .25),
      selectionHandleColor: scheme.primary,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff111d36) : const Color(0xfff5f7fc),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: dark ? Colors.white12 : const Color(0xffe1e6ee),
        ),
      ),
      color: scheme.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff15213a) : Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      height: 76,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}