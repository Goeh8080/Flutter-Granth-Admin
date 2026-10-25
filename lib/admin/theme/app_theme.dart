import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// Round 1: the admin screens use the SAME cream / paper / saffron / maroon look as the user
/// app (`lib/theme/colors.dart`). These names are kept so the older panel screens need no edit.
class AppColors {
  static const saffron = GColors.saffron;
  static const saffronDeep = GColors.saffronDark;
  static const gold = GColors.gold;
  static const maroon = GColors.maroon;
  static const green = Color(0xFF2F7D32);
  static const red = Color(0xFFC0392B);
  static const blue = Color(0xFF8B6A4A);
}

const kFont = GFonts.sans;
const kSerif = GFonts.script;

/// One light palette (no dark mode in the admin app), mapped onto the user app's colours.
class Palette {
  final bool dark;
  const Palette(this.dark);
  static const _light = Palette(false);
  static Palette of(BuildContext context) => _light;

  Color get text => GColors.text;
  Color get subtext => GColors.muted;
  Color get glassFill => GColors.paper;
  Color get glassFillStrong => GColors.paper;
  Color get glassBorder => GColors.creamDark;
  Color get glassShadow => const Color(0x144A2C0A);
  Color get barFill => GColors.stickyBar;
  Color get separator => GColors.creamDark;
  Color get fieldFill => Colors.white;
  List<Color> get backdrop => const [
    GColors.cream,
    GColors.cream,
    GColors.cream,
  ];
}

/// The user app's theme plus the Cupertino bits the older admin screens rely on.
ThemeData buildAdminTheme() {
  final base = buildTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: GColors.maroon,
      scaffoldBackgroundColor: GColors.cream,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: GFonts.sans,
          fontSize: 16,
          color: GColors.text,
        ),
        navActionTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: GFonts.sans,
          fontSize: 17,
          color: GColors.maroon,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: GFonts.display,
          fontSize: 30,
          height: 1.3,
          color: GColors.maroon,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: GFonts.sans,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: GColors.maroon,
        ),
      ),
    ),
  );
}
