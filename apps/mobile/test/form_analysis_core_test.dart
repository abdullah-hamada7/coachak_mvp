import 'package:flutter_test/flutter_test.dart';

import 'package:coachak/features/workout_cv/engine/exercise_engine_factory.dart';
import 'package:coachak/features/workout_cv/engine/exercise_rules/fly_rules.dart';
import 'package:coachak/features/workout_cv/engine/exercise_thresholds.dart';
import 'package:coachak/features/workout_cv/engine/form_analysis_core.dart';
import 'package:coachak/features/workout_cv/engine/pose_utils.dart';
import 'package:coachak/features/workout_cv/engine/yaml/yaml_exercise_loader.dart';

void main() {
  group('RepSequenceTracker', () {
    test('counts correct rep after s2-s3-s2-s1 sequence', () {
      final tracker = RepSequenceTracker();
      final ranges = (normal: (0, 32), trans: (35, 65), pass: (70, 95));

      tracker.updateSequence(tracker.phaseFromAngle(20, ranges));
      expect(tracker.completeRepIfReturned('s1'), isNull);

      tracker.updateSequence('s2');
      tracker.updateSequence('s3');
      tracker.updateSequence('s2');

      expect(tracker.completeRepIfReturned('s1'), 'correct');
    });

    test('flags incorrect rep when posture breaks mid sequence', () {
      final tracker = RepSequenceTracker();
      tracker.updateSequence('s2');
      tracker.incorrectPosture = true;
      tracker.updateSequence('s3');
      tracker.updateSequence('s2');

      expect(tracker.completeRepIfReturned('s1'), 'incorrect');
    });
  });

  group('camera alignment', () {
    test('side view requires low shoulder-nose offset', () {
      final lm = {
        0: PosePoint(100, 100, likelihood: 1),
        11: PosePoint(80, 100, likelihood: 1),
        12: PosePoint(120, 100, likelihood: 1),
      };

      expect(isCameraAligned(lm, offsetMax: 35), isFalse);
    });

    test('front view requires high shoulder-nose offset', () {
      final lm = {
        0: PosePoint(100, 100, likelihood: 1),
        11: PosePoint(80, 100, likelihood: 1),
        12: PosePoint(120, 100, likelihood: 1),
      };

      expect(isFrontCameraAligned(lm, offsetMin: 35), isTrue);
    });
  });

  group('createExerciseEngine', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await YamlExerciseCatalog.load();
    });

    test('creates yaml and custom exercises', () {
      for (final exercise in supportedExercises()) {
        final engine = createExerciseEngine(exercise: exercise);
        expect(engine.exerciseName, exercise);
      }
    });

    test('pro squat uses stricter pass range than beginner', () {
      final beginner = SquatThresholds.forDifficulty(DifficultyLevel.beginner);
      final pro = SquatThresholds.forDifficulty(DifficultyLevel.pro);
      expect(pro.passRange.$1, greaterThan(beginner.passRange.$1));
      expect(pro.ankleMax, lessThan(beginner.ankleMax));
    });
  });

  group('FlyRuleEngine', () {
    test('counts rep when arms return wide after closed position', () {
      final engine = FlyRuleEngine();
      engine.processFrame(_frontFlyLandmarks(spreadFactor: 1.0), 0);
      engine.processFrame(_frontFlyLandmarks(spreadFactor: 0.25), 1000);
      engine.processFrame(_frontFlyLandmarks(spreadFactor: 1.0), 2500);
      expect(engine.repCount + engine.improperRepCount, 1);
    });
  });
}

Map<int, PosePoint> _frontFlyLandmarks({required double spreadFactor}) {
  const midX = 200.0;
  const shoulderWidth = 120.0;
  const y = 120.0;
  final leftShoulderX = midX - shoulderWidth / 2;
  final rightShoulderX = midX + shoulderWidth / 2;
  final leftWristX = midX - shoulderWidth * spreadFactor;
  final rightWristX = midX + shoulderWidth * spreadFactor;
  final leftElbowX = leftShoulderX + (leftWristX - leftShoulderX) * 0.5;
  final rightElbowX = rightShoulderX + (rightWristX - rightShoulderX) * 0.5;
  return {
    0: PosePoint(midX, 80, likelihood: 1),
    11: PosePoint(leftShoulderX, y, likelihood: 1),
    12: PosePoint(rightShoulderX, y, likelihood: 1),
    13: PosePoint(leftElbowX, y, likelihood: 1),
    14: PosePoint(rightElbowX, y, likelihood: 1),
    15: PosePoint(leftWristX, y, likelihood: 1),
    16: PosePoint(rightWristX, y, likelihood: 1),
  };
}
