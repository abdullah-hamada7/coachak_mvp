import 'package:flutter/material.dart';

/// Coachak design tokens — single source for spacing, radius, and motion.
abstract final class CoachakSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class CoachakRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class CoachakDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
}

abstract final class CoachakColors {
  static const seed = Color(0xFF1B8A5A);
  static const seedDark = Color(0xFF23A96E);
  static const accent = Color(0xFFFF8A3D);
  static const streak = Color(0xFFFF6B35);
  static const xp = Color(0xFF5C6BC0);
  static const surfaceMuted = Color(0xFFF4F7F5);
}

abstract final class CoachakTypography {
  static TextStyle display(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5);

  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600);

  static TextStyle bodyMuted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}

/// Minimum accessible touch target per WCAG / Material guidance.
const double kMinTouchTarget = 48;
