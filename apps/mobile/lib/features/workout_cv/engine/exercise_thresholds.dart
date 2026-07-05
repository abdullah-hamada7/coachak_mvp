enum DifficultyLevel { beginner, pro }

/// Side-view leg exercise thresholds (squat + lunge) from AI-Personal-Trainer.
class SquatThresholds {
  const SquatThresholds({
    required this.normalRange,
    required this.transRange,
    required this.passRange,
    required this.hipBack,
    required this.hipForward,
    required this.ankleMax,
    required this.kneeLow,
    required this.kneeMid,
    required this.kneeDeep,
    this.offsetMax = 35,
    this.inactiveMs = 15000,
    this.feedbackDebounceMs = 1600,
  });

  final (int, int) normalRange;
  final (int, int) transRange;
  final (int, int) passRange;
  final int hipBack;
  final int hipForward;
  final int ankleMax;
  final int kneeLow;
  final int kneeMid;
  final int kneeDeep;
  final double offsetMax;
  final int inactiveMs;
  final int feedbackDebounceMs;

  static SquatThresholds forDifficulty(DifficultyLevel level) => switch (level) {
        DifficultyLevel.beginner => const SquatThresholds(
            normalRange: (0, 40),
            transRange: (28, 72),
            passRange: (58, 115),
            hipBack: 12,
            hipForward: 55,
            ankleMax: 50,
            kneeLow: 45,
            kneeMid: 75,
            kneeDeep: 100,
            offsetMax: 42,
            inactiveMs: 45000,
          ),
        DifficultyLevel.pro => const SquatThresholds(
            normalRange: (0, 32),
            transRange: (35, 65),
            passRange: (80, 95),
            hipBack: 15,
            hipForward: 50,
            ankleMax: 30,
            kneeLow: 50,
            kneeMid: 80,
            kneeDeep: 95,
          ),
      };
}

class CurlThresholds {
  const CurlThresholds({
    required this.normalRange,
    required this.transRange,
    required this.passRange,
    required this.hipMax,
    required this.shoulderMax,
    this.offsetMax = 35,
    this.inactiveMs = 15000,
    this.feedbackDebounceMs = 1600,
  });

  final (int, int) normalRange;
  final (int, int) transRange;
  final (int, int) passRange;
  final int hipMax;
  final int shoulderMax;
  final double offsetMax;
  final int inactiveMs;
  final int feedbackDebounceMs;

  static CurlThresholds forDifficulty(DifficultyLevel level) => switch (level) {
        DifficultyLevel.beginner => const CurlThresholds(
            normalRange: (145, 200),
            transRange: (85, 144),
            passRange: (35, 84),
            hipMax: 7,
            shoulderMax: 15,
          ),
        DifficultyLevel.pro => const CurlThresholds(
            normalRange: (150, 200),
            transRange: (80, 149),
            passRange: (30, 79),
            hipMax: 5,
            shoulderMax: 12,
          ),
      };
}

/// Tricep kickback thresholds from AI-Personal-Trainer threshold_kickback.py.
class KickbackThresholds {
  const KickbackThresholds({
    required this.normalRange,
    required this.transRange,
    required this.passRange,
    required this.hipMin,
    required this.hipMax,
    required this.shoulderMax,
    this.offsetMax = 35,
    this.inactiveMs = 15000,
    this.feedbackDebounceMs = 1600,
  });

  final (int, int) normalRange;
  final (int, int) transRange;
  final (int, int) passRange;
  final int hipMin;
  final int hipMax;
  final int shoulderMax;
  final double offsetMax;
  final int inactiveMs;
  final int feedbackDebounceMs;

  static KickbackThresholds forDifficulty(DifficultyLevel level) => switch (level) {
        DifficultyLevel.beginner => const KickbackThresholds(
            normalRange: (65, 100),
            transRange: (95, 145),
            passRange: (146, 200),
            hipMin: 30,
            hipMax: 60,
            shoulderMax: 20,
            offsetMax: 42,
            inactiveMs: 45000,
          ),
        DifficultyLevel.pro => const KickbackThresholds(
            normalRange: (65, 95),
            transRange: (96, 145),
            passRange: (146, 200),
            hipMin: 30,
            hipMax: 50,
            shoulderMax: 12,
          ),
      };
}

class PushUpThresholds {
  const PushUpThresholds({
    required this.topElbowMin,
    required this.bottomElbowMax,
    required this.partialElbowMax,
    required this.alignmentMin,
    this.offsetMax = 35,
    this.inactiveMs = 15000,
    this.feedbackDebounceMs = 1600,
  });

  final int topElbowMin;
  final int bottomElbowMax;
  final int partialElbowMax;
  final int alignmentMin;
  final double offsetMax;
  final int inactiveMs;
  final int feedbackDebounceMs;

  static PushUpThresholds forDifficulty(DifficultyLevel level) => switch (level) {
        DifficultyLevel.beginner => const PushUpThresholds(
            topElbowMin: 155,
            bottomElbowMax: 95,
            partialElbowMax: 125,
            alignmentMin: 155,
            offsetMax: 42,
            inactiveMs: 45000,
          ),
        DifficultyLevel.pro => const PushUpThresholds(
            topElbowMin: 165,
            bottomElbowMax: 85,
            partialElbowMax: 110,
            alignmentMin: 170,
          ),
      };
}

/// Front-view dumbbell fly thresholds (README: frontal view for symmetry).
class FlyThresholds {
  const FlyThresholds({
    required this.wideSpreadMin,
    required this.midSpreadMin,
    required this.closedSpreadMax,
    required this.elbowBendMax,
    this.offsetMin = 35,
    this.inactiveMs = 15000,
    this.feedbackDebounceMs = 1600,
  });

  final double wideSpreadMin;
  final double midSpreadMin;
  final double closedSpreadMax;
  final int elbowBendMax;
  final double offsetMin;
  final int inactiveMs;
  final int feedbackDebounceMs;

  static FlyThresholds forDifficulty(DifficultyLevel level) => switch (level) {
        DifficultyLevel.beginner => const FlyThresholds(
            wideSpreadMin: 0.75,
            midSpreadMin: 0.5,
            closedSpreadMax: 0.4,
            elbowBendMax: 25,
            offsetMin: 22,
            inactiveMs: 45000,
          ),
        DifficultyLevel.pro => const FlyThresholds(
            wideSpreadMin: 0.95,
            midSpreadMin: 0.6,
            closedSpreadMax: 0.28,
            elbowBendMax: 18,
          ),
      };
}
