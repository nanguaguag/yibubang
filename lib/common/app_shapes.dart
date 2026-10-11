import 'package:flutter/material.dart';

/// MD3 Expressive 形状令牌（参照 cgfkr 设计系统）
class AppShapes {
  AppShapes._();

  static const double xs = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double largeIncreased = 20;
  static const double extraLarge = 28;
  static const double full = 999;
}

class AppCurves {
  AppCurves._();

  static const Curve standard = Curves.easeInOutCubic;
  static const Curve quick = Curves.easeOutQuart;
}