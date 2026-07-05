import '../exercise_thresholds.dart';
import 'leg_exercise_engine.dart';

class SquatRuleEngine extends LegExerciseRuleEngine {
  SquatRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : super(
          exerciseName: 'squat',
          thresholds: SquatThresholds.forDifficulty(difficulty),
        );
}

class LungeRuleEngine extends LegExerciseRuleEngine {
  LungeRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : super(
          exerciseName: 'lunge',
          thresholds: SquatThresholds.forDifficulty(difficulty),
        );
}
