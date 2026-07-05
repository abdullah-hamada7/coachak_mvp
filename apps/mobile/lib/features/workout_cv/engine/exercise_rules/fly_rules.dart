import 'package:camera/camera.dart';

import '../../coaching/workout_feedback_ar.dart';
import '../camera_lens_holder.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';

/// Front-view dumbbell fly (AI-Personal-Trainer README: frontal view for symmetry).
class FlyRuleEngine implements ExerciseRuleEngine, CameraLensHolder {
  FlyRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : _thresholds = FlyThresholds.forDifficulty(difficulty);

  final FlyThresholds _thresholds;
  final _debouncer = CorrectionDebouncer();
  late final _inactivity = InactivityTracker(thresholdMs: _thresholds.inactiveMs);

  @override
  CameraLensDirection? activeCameraLens;

  int _repCount = 0;
  int _improperRepCount = 0;
  bool _cameraAligned = false;
  RepPhase _phase = RepPhase.idle;
  String? _currentCue;
  final _corrections = <FormCorrection>[];
  final _overlayHints = <FormOverlayHint>[];
  double _romScore = 1.0;
  bool _wasClosed = false;
  bool _badFormThisRep = false;

  @override
  String get exerciseName => 'dumbbell_fly';

  @override
  int get repCount => _repCount;

  @override
  int get improperRepCount => _improperRepCount;

  @override
  bool get cameraAligned => _cameraAligned;

  @override
  RepPhase get phase => _phase;

  @override
  String? get currentCue => _currentCue;

  @override
  List<FormCorrection> get corrections => List.unmodifiable(_corrections);

  @override
  List<FormOverlayHint> get overlayHints => List.unmodifiable(_overlayHints);

  @override
  double get romScore => _romScore;

  @override
  void reset() {
    _repCount = 0;
    _improperRepCount = 0;
    _cameraAligned = false;
    _phase = RepPhase.idle;
    _currentCue = null;
    _corrections.clear();
    _overlayHints.clear();
    _romScore = 1.0;
    _wasClosed = false;
    _badFormThisRep = false;
    _debouncer.reset();
    _inactivity.reset(0);
  }

  @override
  void processFrame(Map<int, PosePoint> lm, int timestampMs) {
    _overlayHints.clear();
    _cameraAligned = isFrontCameraAligned(lm, offsetMin: 22);
    if (!_cameraAligned) {
      _currentCue = WorkoutFeedbackAr.faceCamera;
      _addCorrection(WorkoutFeedbackAr.faceCamera, 'warning', timestampMs);
      return;
    }

    final leftShoulder = lm[PoseLandmarks.leftShoulder];
    final rightShoulder = lm[PoseLandmarks.rightShoulder];
    final leftElbow = lm[PoseLandmarks.leftElbow];
    final rightElbow = lm[PoseLandmarks.rightElbow];
    final leftWrist = lm[PoseLandmarks.leftWrist];
    final rightWrist = lm[PoseLandmarks.rightWrist];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftWrist == null ||
        rightWrist == null) {
      if (_cameraAligned) _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    final midShoulder = midpoint(leftShoulder, rightShoulder)!;
    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    if (shoulderWidth < 20) {
      _currentCue = WorkoutFeedbackAr.stepBackFromCamera;
      return;
    }

    final leftSpread = (leftWrist.x - midShoulder.x).abs() / shoulderWidth;
    final rightSpread = (rightWrist.x - midShoulder.x).abs() / shoulderWidth;
    final avgSpread = (leftSpread + rightSpread) / 2;

    final leftElbowAngle = calculateAngle(leftShoulder, leftElbow, leftWrist);
    final rightElbowAngle = calculateAngle(rightShoulder, rightElbow, rightWrist);
    final avgElbow = (leftElbowAngle + rightElbowAngle) / 2;

    _overlayHints
      ..add(FormOverlayHint.guideLine(from: leftShoulder, to: leftWrist, colorArgb: 0xFF66CCFF))
      ..add(FormOverlayHint.guideLine(from: rightShoulder, to: rightWrist, colorArgb: 0xFF66CCFF))
      ..add(FormOverlayHint.label(center: leftWrist, label: leftSpread.toStringAsFixed(1)))
      ..add(FormOverlayHint.label(center: rightWrist, label: rightSpread.toStringAsFixed(1)));

    final spreadDiff = (leftSpread - rightSpread).abs();
    if (spreadDiff > 0.35) {
      _badFormThisRep = true;
      _addCorrection(WorkoutFeedbackAr.keepArmsSymmetrical, 'warning', timestampMs);
      _currentCue = WorkoutFeedbackAr.keepArmsSymmetrical;
    }

    if (avgElbow < 150) {
      _addCorrection(WorkoutFeedbackAr.keepElbowsSoft, 'info', timestampMs);
    }

    final state = avgSpread >= _thresholds.wideSpreadMin
        ? 'wide'
        : avgSpread <= _thresholds.closedSpreadMax
            ? 'closed'
            : 'mid';

    if (state == 'wide') {
      _phase = RepPhase.bottom;
      _currentCue ??= WorkoutFeedbackAr.openWide;
      if (_wasClosed) {
        if (_badFormThisRep) {
          _improperRepCount++;
          _currentCue = WorkoutFeedbackAr.fixNextRep;
          _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
        } else {
          _repCount++;
          _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
        }
        _wasClosed = false;
        _badFormThisRep = false;
      }
    } else if (state == 'closed') {
      _phase = RepPhase.top;
      _wasClosed = true;
      _currentCue = WorkoutFeedbackAr.squeezeChest;
    } else if (avgSpread < _thresholds.midSpreadMin) {
      _phase = RepPhase.concentric;
      _addCorrection(WorkoutFeedbackAr.bringArmsTogether, 'info', timestampMs);
      _currentCue = WorkoutFeedbackAr.bringArmsTogether;
    } else {
      _phase = RepPhase.eccentric;
      _currentCue = WorkoutFeedbackAr.lowerWithControl;
    }

    if (_inactivity.update(state, timestampMs)) {
      _wasClosed = false;
      _badFormThisRep = false;
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  void _addCorrection(String cue, String severity, int timestampMs) {
    if (!_debouncer.shouldEmit(timestampMs)) return;
    _corrections.add(FormCorrection(cue: cue, severity: severity, timestampMs: timestampMs));
  }
}
