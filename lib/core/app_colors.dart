import 'package:flutter/material.dart';

/// Sheetal brand tokens — matched to the customer app (`sheetal_icecream`).
class AppColors {
  const AppColors._();

  // Brand
  static const primary = Color(0xFFDA3A7B); // Sheetal Magenta
  static const primaryDark = Color(0xFFD43375);
  static const primaryLight = Color(0xFFE0508A);
  static const hotPink = Color(0xFFEC5BB0);
  static const softPink = Color(0xFFF58CCB);

  static const plum = Color(0xFF2D1A4F); // Deep ink
  static const purple = Color(0xFF583090); // Royal purple
  static const muted = Color(0xFF6B5F85);

  static const page = Color(0xFFFFF7FB);
  static const frost = Color(0xFFFDF4F9);
  static const line = Color(0xFFF3CEE6);
  static const borderPink = Color(0xFFF2B6DC);
  static const warmCard = Color(0xFFFFF4E8);

  static const online = Color(0xFF7FB942); // Fresh green (same as customer accent)
  static const danger = Color(0xFFBA1A1A);
  static const warning = Color(0xFFB45309);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFD43375), Color(0xFFE0508A)],
  );

  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEC5BB0), Color(0xFFD93E97)],
  );

  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.6, 1.0],
    colors: [Color(0xFFFFFFFF), Color(0xFFFFF4F9), Color(0xFFFBEFF6)],
  );
}
