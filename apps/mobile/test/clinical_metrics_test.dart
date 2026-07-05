import 'package:flutter_test/flutter_test.dart';

import 'package:coachak/features/workout_cv/engine/clinical/clinical_metrics_tracker.dart';
import 'package:coachak/features/workout_cv/engine/clinical/clinical_rom_config.dart';
import 'package:coachak/features/workout_cv/engine/pose_utils.dart';

void main() {
  group('ClinicalRomCatalog', () {
    test('computes flexion ROM score from baseline and peak', () {
      const cfg = ClinicalRomConfig(
        primaryJoint: ClinicalJoint.knee,
        targetAngle: 120,
        startAngle: 165,
        labelAr: 'ثني الركبة',
      );
      expect(ClinicalRomCatalog.computeRomScore(cfg, 165, 120), 100);
      expect(ClinicalRomCatalog.computeRomScore(cfg, 165, 142), 51);
    });

    test('returns Arabic diagnosis tiers', () {
      expect(
        ClinicalRomCatalog.diagnosisAr('squat', 90),
        contains('كامل'),
      );
      expect(
        ClinicalRomCatalog.diagnosisAr('squat', 50),
        contains('قيود'),
      );
    });
  });

  group('ClinicalMetricsTracker', () {
    test('tracks stability and asymmetry for squat-like landmarks', () {
      final tracker = ClinicalMetricsTracker(exerciseId: 'squat');
      expect(tracker.isActive, isTrue);

      final lm = _squatLandmarks();
      tracker.processFrame(
        lm,
        0,
        phase: RepPhase.eccentric,
        repCount: 0,
        cameraAligned: true,
        sideView: true,
      );
      tracker.processFrame(
        lm,
        500,
        phase: RepPhase.bottom,
        repCount: 0,
        cameraAligned: true,
        sideView: true,
      );

      expect(tracker.latestStability, greaterThan(0));
      expect(tracker.latestAsymmetry, greaterThanOrEqualTo(0));
    });

    test('session payload includes Arabic clinical observations', () {
      final tracker = ClinicalMetricsTracker(exerciseId: 'lunge');
      tracker.processFrame(
        _squatLandmarks(),
        0,
        phase: RepPhase.top,
        repCount: 1,
        cameraAligned: true,
        sideView: true,
      );
      final payload = tracker.sessionPayload();
      expect(payload['clinical_diagnosis_ar'], isA<String>());
      expect(payload['clinical_observations_ar'], isA<List<String>>());
    });

    test('is inactive for unsupported exercises', () {
      expect(ClinicalMetricsTracker(exerciseId: 'jumping_jack').isActive, isFalse);
    });
  });
}

Map<int, PosePoint> _squatLandmarks() {
  return {
    0: PosePoint(100, 90, likelihood: 1),
    11: PosePoint(80, 120, likelihood: 1),
    12: PosePoint(120, 120, likelihood: 1),
    13: PosePoint(70, 160, likelihood: 1),
    14: PosePoint(130, 160, likelihood: 1),
    23: PosePoint(85, 200, likelihood: 1),
    24: PosePoint(115, 200, likelihood: 1),
    25: PosePoint(85, 260, likelihood: 1),
    26: PosePoint(115, 260, likelihood: 1),
    27: PosePoint(85, 320, likelihood: 1),
    28: PosePoint(115, 320, likelihood: 1),
  };
}
