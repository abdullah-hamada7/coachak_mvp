import 'package:camera/camera.dart';

import 'camera_lens_holder.dart';
import 'exercise_thresholds.dart';
import 'exercise_rules/curl_rules.dart';
import 'exercise_rules/fly_rules.dart';
import 'exercise_rules/kickback_rules.dart';
import 'exercise_rules/pushup_rules.dart';
import 'exercise_rules/squat_rules.dart';
import 'pose_utils.dart';
import 'yaml/yaml_exercise_engine.dart';
import 'yaml/yaml_exercise_loader.dart';

/// Custom engines without YAML definitions (specialized camera logic).
const kCustomExercises = ['tricep_kickback', 'dumbbell_fly'];

/// Exercises with hand-tuned Dart engines (more accurate than generic YAML FSM).
const kNativeEngineExercises = {'squat', 'lunge', 'push_up'};

Future<void> ensureExerciseCatalogLoaded() => YamlExerciseCatalog.load();

List<String> supportedExercises() {
  final yaml = YamlExerciseCatalog.exerciseIds();
  return [...yaml, ...kCustomExercises.where((e) => !yaml.contains(e))];
}

ExerciseRuleEngine createExerciseEngine({
  required String exercise,
  DifficultyLevel difficulty = DifficultyLevel.beginner,
}) {
  if (kNativeEngineExercises.contains(exercise)) {
    return switch (exercise) {
      'push_up' => PushUpRuleEngine(difficulty: difficulty),
      'lunge' => LungeRuleEngine(difficulty: difficulty),
      'squat' => SquatRuleEngine(difficulty: difficulty),
      _ => throw ArgumentError('Unhandled native engine exercise: $exercise. '
          'Add it to the switch or define a YAML definition.'),
    };
  }

  final yamlDef = YamlExerciseCatalog.get(exercise);
  if (yamlDef != null) {
    return YamlExerciseEngine(yamlDef, difficulty: difficulty);
  }

  return switch (exercise) {
    'bicep_curl' => CurlRuleEngine(difficulty: difficulty),
    'tricep_kickback' => KickbackRuleEngine(difficulty: difficulty),
    'dumbbell_fly' => FlyRuleEngine(difficulty: difficulty),
    _ => throw ArgumentError('No engine available for exercise: $exercise. '
        'Ensure the exercise has a YAML definition in assets/exercises/'),
  };
}

void syncEngineCameraLens(ExerciseRuleEngine? engine, CameraLensDirection? lens) {
  if (engine is CameraLensHolder) {
    (engine as CameraLensHolder).activeCameraLens = lens;
  }
}

String exerciseDisplayName(String id) {
  return YamlExerciseCatalog.get(id)?.displayName ??
      switch (id) {
        'tricep_kickback' => 'Tricep Kickback',
        'dumbbell_fly' => 'Dumbbell Fly',
        _ => id.replaceAll('_', ' '),
      };
}
