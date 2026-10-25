import 'package:flutter/material.dart';

/// Colour tokens of the reader app's folder cards (see admin_ui_tokens.md §2).
class GColors {
  static const saffron = Color(0xFFE8821A);
  static const saffronDark = Color(0xFFC06A10);
  static const maroon = Color(0xFF7B1F2E);
  static const maroonLight = Color(0xFFA0293D);
  static const gold = Color(0xFFC9A84C);
  static const goldLight = Color(0xFFE2C97E);
  static const cream = Color(0xFFFDF6E3);
  static const creamDark = Color(0xFFF5E6C8);
  static const brown = Color(0xFF4A2C0A);
  static const text = Color(0xFF3D1F00);
  static const muted = Color(0xFF8B6A4A);
  static const paper = Color(0xFFFFFDF7);
}

enum Tone { saffron, maroon, gold }

Tone toneOf(Object? v) => switch (v) {
  'maroon' => Tone.maroon,
  'gold' => Tone.gold,
  _ => Tone.saffron,
};

/// The gradient and the ink of a [Tone].
(List<Color>, Color) toneColors(Tone tone) => switch (tone) {
  Tone.saffron => ([GColors.saffron, GColors.saffronDark], GColors.paper),
  Tone.maroon => ([GColors.maroonLight, GColors.maroon], GColors.paper),
  Tone.gold => ([GColors.goldLight, GColors.gold], GColors.brown),
};
