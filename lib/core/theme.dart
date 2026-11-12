import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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

/// Premium Wolf palette: Nepal crimson, midnight navy, moonlight silver/blue.
abstract final class TwonPalette {
  static const midnight = Color(0xff071a33);
  static const navy = Color(0xff102742);
  static const navyRaised = Color(0xff173356);
  static const crimson = Color(0xffc62839);
  static const moonlight = Color(0xffdde6ee);
  static const moonBlue = Color(0xff6e9dc7);

  static const crimsonGradient = [Color(0xffd4394a), crimson, Color(0xffa91f30)];
  static const navyGradient = [Color(0xff1a3a60), navy, Color(0xff0b1f38)];
  static const dangerGradient = [Color(0xff8a2230), Color(0xff761a27)];
}

/// Wolf motion language: short, quiet, purposeful. Every duration collapses to
/// zero when the platform asks for reduced motion.
abstract final class TwonMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Cubic(0.22, 1, 0.36, 1);
  static Duration of(BuildContext context, Duration duration) =>
      (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      ? Duration.zero
      : duration;
}

/// Dimensional button surface used by the button themes: a vertical gradient,
/// a thin top-edge highlight, layered shadow, and a tactile press (scale 0.97,
/// reduced elevation). Disabled buttons are flat; focus shows a moonlight ring.
Widget twonButtonSurface(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child, {
  required List<Color> gradient,
  required Color glow,
  Color? border,
  double radius = 16,
}) {
  final scheme = Theme.of(context).colorScheme;
  final disabled = states.contains(WidgetState.disabled);
  final pressed = states.contains(WidgetState.pressed);
  final focused = states.contains(WidgetState.focused);
  final hovered = states.contains(WidgetState.hovered);
  final shape = BorderRadius.circular(radius);
  final shadows = disabled
      ? const <BoxShadow>[]
      : pressed
      ? const [
          BoxShadow(
            color: Color(0x33071a33),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ]
      : [
          const BoxShadow(
            color: Color(0x3d071a33),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: glow.withValues(alpha: hovered ? .55 : .42),
            blurRadius: hovered ? 24 : 18,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ];
  return AnimatedScale(
    scale: pressed ? .97 : 1,
    duration: TwonMotion.of(context, TwonMotion.fast),
    curve: TwonMotion.curve,
    child: AnimatedContainer(
      duration: TwonMotion.of(context, TwonMotion.base),
      curve: TwonMotion.curve,
      decoration: BoxDecoration(
        borderRadius: shape,
        color: disabled ? scheme.onSurface.withValues(alpha: .12) : null,
        gradient: disabled
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient,
              ),
        border: focused
            ? Border.all(color: TwonPalette.moonBlue, width: 2)
            : border == null
            ? null
            : Border.all(color: border),
        boxShadow: shadows,
      ),
      foregroundDecoration: disabled
          ? null
          : BoxDecoration(
              borderRadius: shape,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .09, .1],
                colors: [
                  Colors.white.withValues(alpha: pressed ? .1 : .22),
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0),
                ],
              ),
            ),
      child: child,
    ),
  );
}

/// Ready-made styles for the four button roles (primary comes from the theme).
abstract final class TwonButtonStyles {
  static ButtonStyle secondary() => ButtonStyle(
    foregroundColor: const WidgetStatePropertyAll(TwonPalette.moonlight),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    backgroundBuilder: (c, states, child) => twonButtonSurface(
      c,
      states,
      child,
      gradient: TwonPalette.navyGradient,
      glow: TwonPalette.midnight,
      border: TwonPalette.moonBlue.withValues(alpha: .45),
    ),
  );

  static ButtonStyle destructive() => ButtonStyle(
    foregroundColor: const WidgetStatePropertyAll(Color(0xfffff3f4)),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    backgroundBuilder: (c, states, child) => twonButtonSurface(
      c,
      states,
      child,
      gradient: TwonPalette.dangerGradient,
      glow: TwonPalette.midnight,
    ),
  );

  /// Filled icon actions (create, send, basket): solid crimson with a white
  /// glyph in both themes. The dark scheme's primary is a light ink for text,
  /// which must not become a fill.
  static ButtonStyle filledIcon() => IconButton.styleFrom(
    backgroundColor: TwonPalette.crimson,
    foregroundColor: Colors.white,
  );
}

ThemeData twonTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: TwonPalette.crimson,
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xffff8f9c) : const Color(0xffb02232),
        onPrimary: dark ? const Color(0xff181b2e) : Colors.white,
        onSurface: dark ? const Color(0xffeef3f8) : const Color(0xff13233d),
        onSurfaceVariant: dark
            ? const Color(0xffa7b8cb)
            : const Color(0xff5d6f88),
        surface: dark ? TwonPalette.navy : Colors.white,
        primaryContainer: dark
            ? const Color(0xff34304b)
            : const Color(0xffffe3eb),
        onPrimaryContainer: dark
            ? const Color(0xffffc4d1)
            : const Color(0xff78132c),
        secondaryContainer: dark
            ? TwonPalette.navyRaised
            : const Color(0xffe8edf6),
        onSecondaryContainer: dark
            ? const Color(0xffe2eafa)
            : const Color(0xff263650),
        surfaceContainerLowest: dark ? TwonPalette.midnight : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff0d2240)
            : const Color(0xfffafbfe),
        surfaceContainerHigh: dark
            ? const Color(0xff1b3a60)
            : const Color(0xffedf1f8),
        surfaceContainerHighest: dark
            ? const Color(0xff21446d)
            : const Color(0xffe6ecf5),
        outline: dark ? const Color(0xff5f7d9f) : const Color(0xff77849a),
        outlineVariant: dark
            ? const Color(0xff24426a)
            : const Color(0xffdbe2ed),

        surfaceContainer: dark
            ? const Color(0xff163050)
            : const Color(0xfff2f4f9),
      );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(
      color: dark ? const Color(0xff2d4a6e) : const Color(0xffdbe1ea),
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
        ? TwonPalette.midnight
        : const Color(0xfff4f7fb),
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
    // Filled controls use solid crimson (white thumb/glyph), never the light
    // dark-mode text ink, so toggles and FABs read the same in both themes.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? Colors.white
            : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? TwonPalette.crimson
            : null,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? TwonPalette.crimson
            : null,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? (dark ? scheme.primary : TwonPalette.crimson)
            : null,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: TwonPalette.crimson,
      foregroundColor: Colors.white,
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
      backgroundColor: dark ? TwonPalette.midnight : const Color(0xfff4f7fb),
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
          color: dark
              ? TwonPalette.moonBlue.withValues(alpha: .16)
              : const Color(0xffe1e6ee),
        ),
      ),
      color: scheme.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff0d2240) : Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: dark ? TwonPalette.moonBlue : const Color(0xff3a74a8),
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.all(16),
    ),
    // Primary: restrained crimson gradient with depth and a tactile press.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: const Size(48, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            foregroundColor: Colors.white,
            disabledForegroundColor: scheme.onSurface.withValues(alpha: .45),
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
          ).copyWith(
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            backgroundBuilder: (c, states, child) => twonButtonSurface(
              c,
              states,
              child,
              gradient: TwonPalette.crimsonGradient,
              glow: TwonPalette.crimson,
            ),
          ),
    ),
    // Ghost: minimal, for frequent actions.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(
          color: dark
              ? TwonPalette.moonBlue.withValues(alpha: .45)
              : const Color(0xffc5d0de),
        ),
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
    // Stealth page transitions: a short fade and rise (zero under reduced motion).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: StealthPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: StealthPageTransitionsBuilder(),
        TargetPlatform.windows: StealthPageTransitionsBuilder(),
        TargetPlatform.fuchsia: StealthPageTransitionsBuilder(),
      },
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
/// Fade-and-rise page transition (the "stealth" entrance). iOS keeps the
/// native back-swipe transition.
class StealthPageTransitionsBuilder extends PageTransitionsBuilder {
  const StealthPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final curved = CurvedAnimation(parent: animation, curve: TwonMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
