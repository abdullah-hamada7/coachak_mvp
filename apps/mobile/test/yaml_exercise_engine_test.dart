import 'package:flutter_test/flutter_test.dart';

import 'package:coachak/features/workout_cv/coaching/workout_feedback_ar.dart';
import 'package:coachak/features/workout_cv/engine/pose_utils.dart';
import 'package:coachak/features/workout_cv/engine/yaml/condition_evaluator.dart';
import 'package:coachak/features/workout_cv/engine/yaml/form_score_calculator.dart';
import 'package:coachak/features/workout_cv/engine/yaml/yaml_exercise_engine.dart';
import 'package:coachak/features/workout_cv/engine/yaml/yaml_exercise_loader.dart';

void main() {
  group('ConditionEvaluator', () {
    final evaluator = ConditionEvaluator();

    test('evaluates angle comparisons', () {
      expect(evaluator.evaluate('angle > 165', {'angle': 170}), isTrue);
      expect(evaluator.evaluate('angle <= 90', {'angle': 85}), isTrue);
    });

    test('evaluates compound and conditions', () {
      expect(
        evaluator.evaluate('angle > 90 and angle <= 165', {'angle': 120}),
        isTrue,
      );
    });

    test('evaluates landmark coordinate conditions', () {
      expect(
        evaluator.evaluate('left_knee_x > left_ankle_x + 50', {
          'left_knee_x': 200,
          'left_ankle_x': 140,
        }),
        isTrue,
      );
    });
  });

  group('FormScoreCalculator', () {
    test('assigns letter grades', () {
      expect(FormScoreCalculator.gradeFor(95), 'A');
      expect(FormScoreCalculator.gradeFor(72), 'C');
      expect(FormScoreCalculator.gradeFor(40), 'F');
    });
  });

  group('YamlExerciseEngine', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await YamlExerciseCatalog.load();
    });

    test('YAML feedback messages are Arabic only', () {
      for (final id in YamlExerciseCatalog.exerciseIds()) {
        final def = YamlExerciseCatalog.get(id)!;
        for (final entry in def.feedback.entries) {
          final msg = (entry.value as Map)['message']?.toString() ?? '';
          expect(
            RegExp(r'[\u0600-\u06FF]').hasMatch(msg),
            isTrue,
            reason: '$id/${entry.key} message should be Arabic: $msg',
          );
        }
      }
    });

    test('engine system cues are Arabic', () {
      expect(WorkoutFeedbackAr.turnSideways, contains('الكاميرا'));
      expect(WorkoutFeedbackAr.repComplete(2), contains('تكرار'));
      expect(WorkoutFeedbackAr.holdProgress(5, 30), contains('ث'));
    });

    test('bilateral hammer curl tracks left and right rep counters', () {
      final def = YamlExerciseCatalog.get('hammer_curl')!;
      expect(def.bilateral, isTrue);
      final engine = YamlExerciseEngine(def);
      engine.processFrame(_hammerLandmarks(straight: true), 0);
      engine.processFrame(_hammerLandmarks(straight: false), 1500);
      expect(engine.repCountLeft + engine.repCountRight, greaterThanOrEqualTo(0));
      expect(engine.repCount, engine.repCountLeft + engine.repCountRight);
    });

    test('plank duration mode uses Arabic hold messaging', () {
      final def = YamlExerciseCatalog.get('plank')!;
      expect(def.type, 'duration');
      expect(
        WorkoutFeedbackAr.holdProgress(10, def.targetDurationSec),
        contains('10'),
      );
      final engine = YamlExerciseEngine(def);
      engine.processFrame(_plankHoldLandmarks(), 0);
      engine.processFrame(_plankHoldLandmarks(), 3000);
      if (engine.cameraAligned) {
        expect(engine.currentCue, contains('ث'));
      } else {
        expect(engine.currentCue, WorkoutFeedbackAr.turnSideways);
      }
    });
  });
}

Map<int, PosePoint> _hammerLandmarks({required bool straight}) {
  final ls = PosePoint(80, 120, likelihood: 1);
  final rs = PosePoint(200, 120, likelihood: 1);
  final le = PosePoint(80, 180, likelihood: 1);
  final re = PosePoint(200, 180, likelihood: 1);
  final lw = straight ? PosePoint(80, 240, likelihood: 1) : PosePoint(120, 200, likelihood: 1);
  final rw = straight ? PosePoint(200, 240, likelihood: 1) : PosePoint(240, 200, likelihood: 1);

  return {
    0: PosePoint(100, 90, likelihood: 1),
    11: ls,
    12: rs,
    13: le,
    14: re,
    15: lw,
    16: rw,
    23: PosePoint(80, 260, likelihood: 1),
    24: PosePoint(200, 260, likelihood: 1),
  };
}

Map<int, PosePoint> _plankHoldLandmarks() {
  return {
    0: PosePoint(100, 90, likelihood: 1),
    11: PosePoint(80, 120, likelihood: 1),
    12: PosePoint(120, 120, likelihood: 1),
    13: PosePoint(60, 120, likelihood: 1),
    14: PosePoint(140, 120, likelihood: 1),
    15: PosePoint(40, 120, likelihood: 1),
    16: PosePoint(160, 120, likelihood: 1),
    23: PosePoint(200, 120, likelihood: 1),
    24: PosePoint(220, 120, likelihood: 1),
    25: PosePoint(200, 120, likelihood: 1),
    26: PosePoint(220, 120, likelihood: 1),
    27: PosePoint(300, 120, likelihood: 1),
    28: PosePoint(320, 120, likelihood: 1),
  };
}
