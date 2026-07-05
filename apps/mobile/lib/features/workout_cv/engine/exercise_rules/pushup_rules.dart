import 'package:camera/camera.dart';

import '../../coaching/workout_feedback_ar.dart';
import '../camera_lens_holder.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';

class PushUpRuleEngine implements ExerciseRuleEngine, CameraLensHolder {
  PushUpRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : _thresholds = PushUpThresholds.forDifficulty(difficulty);

  final PushUpThresholds _thresholds;
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
  bool _wasAtBottom = false;
  bool _badFormThisRep = false;

  @override
  String get exerciseName => 'push_up';

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

  bool get _frontView => activeCameraLens == CameraLensDirection.front;

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
    _wasAtBottom = false;
    _badFormThisRep = false;
    _debouncer.reset();
    _inactivity.reset(0);
  }

  @override
  void processFrame(Map<int, PosePoint> lm, int timestampMs) {
    _overlayHints.clear();
    _cameraAligned = _frontView
        ? isFrontCameraAligned(lm, offsetMin: 22)
        : isCameraAligned(lm, offsetMax: 42);

    if (!_cameraAligned) {
      _currentCue = _frontView ? WorkoutFeedbackAr.faceCamera : WorkoutFeedbackAr.turnSideways;
      _addCorrection(_currentCue!, 'warning', timestampMs);
      return;
    }

    final metrics = _frontView ? _frontMetrics(lm) : _sideMetrics(lm);
    if (metrics == null) {
      if (_cameraAligned) _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    final elbowAngle = metrics.elbowAngle;
    final alignmentAngle = metrics.alignmentAngle;
    final state = elbowAngle > _topElbowMin
        ? 'top'
        : (elbowAngle < _bottomElbowMax ? 'bottom' : 'mid');

    if (metrics.overlayElbow != null) {
      _overlayHints
        ..add(FormOverlayHint.arc(
          center: metrics.overlayElbow!,
          radius: 22,
          startAngleDeg: -90,
          sweepAngleDeg: elbowAngle,
          colorArgb: 0xFFFF66CC,
          label: elbowAngle.round().toString(),
        ))
        ..add(FormOverlayHint.label(
          center: metrics.overlayHip ?? metrics.overlayElbow!,
          label: alignmentAngle.round().toString(),
        ));
    }

    if (alignmentAngle < _thresholds.alignmentMin) {
      _badFormThisRep = true;
      _addCorrection(WorkoutFeedbackAr.keepBodyStraight, 'warning', timestampMs);
      _currentCue = WorkoutFeedbackAr.braceCore;
    }

    if (elbowAngle > _topElbowMin && alignmentAngle > _thresholds.alignmentMin) {
      _phase = RepPhase.top;
      if (_wasAtBottom) {
        if (_badFormThisRep) {
          _improperRepCount++;
          _currentCue = WorkoutFeedbackAr.fixNextRep;
          _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
        } else {
          _repCount++;
          _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
        }
        _wasAtBottom = false;
        _badFormThisRep = false;
      }
    } else if (elbowAngle < _bottomElbowMax) {
      _phase = RepPhase.bottom;
      _wasAtBottom = true;
      _currentCue = WorkoutFeedbackAr.goodDepth;
    } else if (elbowAngle < _partialElbowMax) {
      _phase = RepPhase.eccentric;
      _addCorrection(WorkoutFeedbackAr.chestToFloor, 'info', timestampMs);
      _currentCue = WorkoutFeedbackAr.chestToFloor;
      _romScore = (_romScore * 0.97).clamp(0.0, 1.0);
    } else {
      _phase = RepPhase.concentric;
      _currentCue = WorkoutFeedbackAr.pushUp;
    }

    if (_inactivity.update(state, timestampMs)) {
      _wasAtBottom = false;
      _badFormThisRep = false;
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  int get _topElbowMin => _frontView ? _thresholds.topElbowMin - 10 : _thresholds.topElbowMin;

  int get _bottomElbowMax => _frontView ? _thresholds.bottomElbowMax + 15 : _thresholds.bottomElbowMax;

  int get _partialElbowMax => _frontView ? _thresholds.partialElbowMax + 10 : _thresholds.partialElbowMax;

  _PushMetrics? _sideMetrics(Map<int, PosePoint> lm) {
    final side = selectSideView(lm);
    if (side == null) return null;
    return _PushMetrics(
      elbowAngle: calculateAngle(side.shoulder, side.elbow, side.wrist),
      alignmentAngle: calculateAngle(side.shoulder, side.hip, side.ankle),
      overlayElbow: side.elbow,
      overlayHip: side.hip,
    );
  }

  _PushMetrics? _frontMetrics(Map<int, PosePoint> lm) {
    final left = _armAngle(lm, PoseLandmarks.leftShoulder, PoseLandmarks.leftElbow, PoseLandmarks.leftWrist);
    final right = _armAngle(lm, PoseLandmarks.rightShoulder, PoseLandmarks.rightElbow, PoseLandmarks.rightWrist);
    if (left == null && right == null) return null;

    final elbowAngle = left != null && right != null
        ? (left.angle + right.angle) / 2
        : (left ?? right)!.angle;

    final leftShoulder = lm[PoseLandmarks.leftShoulder];
    final rightShoulder = lm[PoseLandmarks.rightShoulder];
    final leftHip = lm[PoseLandmarks.leftHip];
    final rightHip = lm[PoseLandmarks.rightHip];
    final shoulder = midpoint(leftShoulder, rightShoulder);
    final hip = midpoint(leftHip, rightHip);
    final alignmentAngle = shoulder != null && hip != null && leftShoulder != null && leftHip != null
        ? calculateAngle(leftShoulder, hip, lm[PoseLandmarks.leftAnkle] ?? hip)
        : 170.0;

    return _PushMetrics(
      elbowAngle: elbowAngle,
      alignmentAngle: alignmentAngle,
      overlayElbow: left?.elbow ?? right?.elbow,
      overlayHip: hip,
    );
  }

  ({double angle, PosePoint elbow})? _armAngle(
    Map<int, PosePoint> lm,
    int shoulderIdx,
    int elbowIdx,
    int wristIdx,
  ) {
    final shoulder = lm[shoulderIdx];
    final elbow = lm[elbowIdx];
    final wrist = lm[wristIdx];
    if (shoulder == null || elbow == null || wrist == null) return null;
    if (shoulder.likelihood < 0.35 || elbow.likelihood < 0.35 || wrist.likelihood < 0.35) {
      return null;
    }
    return (angle: calculateAngle(shoulder, elbow, wrist), elbow: elbow);
  }

  void _addCorrection(String cue, String severity, int timestampMs) {
    if (!_debouncer.shouldEmit(timestampMs)) return;
    _corrections.add(FormCorrection(cue: cue, severity: severity, timestampMs: timestampMs));
  }
}

class _PushMetrics {
  const _PushMetrics({
    required this.elbowAngle,
    required this.alignmentAngle,
    this.overlayElbow,
    this.overlayHip,
  });

  final double elbowAngle;
  final double alignmentAngle;
  final PosePoint? overlayElbow;
  final PosePoint? overlayHip;
}
