import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFB58B4B); // Capybara brown
  static const Color surface = Color(0xFFD6B37B);
  static const Color surfaceAlt = Color(0xFFA0713D);
  static const Color accent = Color(0xFFECD7AA); // warm highlight
  static const Color accentSoft = Color(0xFFF6E8CC);
  static const Color accentWarm = Color(0xFFCC9A5C);
  static const Color textPrimary = Color(0xFFE8ECF2);
  static const Color textSecondary = Color(0xFFAAB2C0);
  static const Color border = Color(0xFF8C6A3E);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFFF9F43);
  static const Color success = Color(0xFF6CF2BC);

  static const LinearGradient heroGlow = LinearGradient(
    colors: [
      Color(0x33EAD3A2),
      Color(0x22A0713D),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGlow = LinearGradient(
    colors: [
      Color(0xFFDAB980),
      Color(0xFFA0713D),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
