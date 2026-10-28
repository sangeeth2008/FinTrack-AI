import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class LuxeMotion {
  static const Duration micro = Duration(milliseconds: 140);
  static const Duration fast = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 580);
  static const Duration counter = Duration(milliseconds: 720);
  static const Duration staggerStep = Duration(milliseconds: 55);

  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve decelerate = Curves.easeOutCubic;
  static const Curve bounce = Curves.elasticOut;

  static const SpringDescription spring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 28.0,
  );
}

abstract final class LuxeHaptics {
  static Future<void> light() => HapticFeedback.lightImpact();
  static Future<void> medium() => HapticFeedback.mediumImpact();
  static Future<void> heavy() => HapticFeedback.heavyImpact();
  static Future<void> selection() => HapticFeedback.selectionClick();
}
