import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const saffron = Color(0xFFE8772E);
  static const saffronDeep = Color(0xFFC4501A);
  static const gold = Color(0xFFE9B949);
  static const maroon = Color(0xFF8E2C3B);
  static const green = Color(0xFF34C759);
  static const red = Color(0xFFFF3B30);
  static const blue = Color(0xFF0A84FF);
}

const kFont = 'NotoDeva';
const kSerif = 'TiroDeva';

/// Colours that depend on light/dark mode.
class Palette {
  final bool dark;
  const Palette(this.dark);
  static const _dark = Palette(true), _light = Palette(false);
  static Palette of(BuildContext context) => Theme.brightnessOf(context) == Brightness.dark ? _dark : _light;

  Color get text => dark ? const Color(0xFFF5F2EE) : const Color(0xFF1C1917);
  Color get subtext => dark ? const Color(0xB3EDE6DE) : const Color(0x99332A22);
  Color get glassFill => dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF);
  Color get glassFillStrong => dark ? const Color(0x52262230) : const Color(0xB8FFFFFF);
  Color get glassBorder => dark ? const Color(0x33FFFFFF) : const Color(0xB3FFFFFF);
  Color get glassShadow => dark ? const Color(0x55000000) : const Color(0x1A6B3A1A);
  Color get barFill => dark ? const Color(0x99141218) : const Color(0xA6FFFFFF);
  Color get separator => dark ? const Color(0x22FFFFFF) : const Color(0x1F000000);
  Color get fieldFill => dark ? const Color(0x1FFFFFFF) : const Color(0x99FFFFFF);
  List<Color> get backdrop => dark
      ? const [Color(0xFF120E16), Color(0xFF1C1220), Color(0xFF0E1420)]
      : const [Color(0xFFFFF3E6), Color(0xFFFDE7EC), Color(0xFFEAF1FF)];
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: kFont,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.saffron, brightness: b),
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: b,
      primaryColor: AppColors.saffron,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: kFont,
          fontSize: 16,
          color: dark ? Colors.white : Colors.black,
        ),
        navActionTextStyle: const TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          letterSpacing: -0.4,
          fontFamily: kFont,
          fontSize: 17,
          color: AppColors.saffron,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          letterSpacing: 0.2,
          fontFamily: kFont,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: dark ? Colors.white : const Color(0xFF1C1917),
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          letterSpacing: -0.4,
          fontFamily: kFont,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: dark ? Colors.white : const Color(0xFF1C1917),
        ),
      ),
    ),
  );
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: kFont));
}
