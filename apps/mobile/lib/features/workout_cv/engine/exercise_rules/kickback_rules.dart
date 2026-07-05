import 'package:camera/camera.dart';

import '../../coaching/workout_feedback_ar.dart';
import '../camera_lens_holder.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';

class KickbackRuleEngine implements ExerciseRuleEngine, CameraLensHolder {
  KickbackRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : _thresholds = KickbackThresholds.forDifficulty(difficulty);

  final KickbackThresholds _thresholds;
  final _sequence = RepSequenceTracker();
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

  @override
  String get exerciseName => 'tricep_kickback';

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
    _sequence.reset();
    _debouncer.reset();
    _inactivity.reset(0);
  }

  @override
  void processFrame(Map<int, PosePoint> lm, int timestampMs) {
    _overlayHints.clear();
    _cameraAligned = isCameraAligned(lm, offsetMax: 42);
    final side = selectSideView(lm);
    if (side == null) {
      if (_cameraAligned) _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    if (!_cameraAligned) {
      _currentCue = WorkoutFeedbackAr.turnSideways;
      _addCorrection(WorkoutFeedbackAr.turnSideways, 'warning', timestampMs);
      return;
    }

    final elbowAngle = calculateAngle(side.shoulder, side.elbow, side.wrist);
    final shoulderHipAngle = calculateVerticalAngle(side.shoulder, side.hip);
    final elbowShoulderAngle = 180 - calculateVerticalAngle(side.elbow, side.shoulder);
    final elbowForward = side.elbow.x < side.shoulder.x;
    final multiplier = elbowForward ? -1.0 : 1.0;

    _overlayHints
      ..add(FormOverlayHint.arc(
        center: side.elbow,
        radius: 20,
        startAngleDeg: -90,
        sweepAngleDeg: multiplier * elbowAngle,
        colorArgb: 0xFFFF66CC,
        label: elbowAngle.round().toString(),
      ))
      ..add(FormOverlayHint.label(
        center: side.shoulder,
        label: elbowShoulderAngle.round().toString(),
      ));

    final ranges = (
      normal: _thresholds.normalRange,
      trans: _thresholds.transRange,
      pass: _thresholds.passRange,
    );
    final currentState = _sequence.phaseFromAngle(elbowAngle.round(), ranges);
    _sequence.updateSequence(currentState);
    _updatePhase(currentState);

    final repResult = _sequence.completeRepIfReturned(currentState);
    if (repResult == 'correct') {
      _repCount++;
      _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
    } else if (repResult == 'incorrect') {
      _improperRepCount++;
      _currentCue = WorkoutFeedbackAr.fixNextRep;
      _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
    }

    if (currentState == 's2' || currentState == 's3') {
      if (shoulderHipAngle < _thresholds.hipMin || shoulderHipAngle > _thresholds.hipMax) {
        _sequence.markIncorrectPosture();
        _addCorrection(WorkoutFeedbackAr.straightenBack, 'warning', timestampMs);
        _currentCue = WorkoutFeedbackAr.straightenBack;
      }

      if (elbowShoulderAngle > _thresholds.shoulderMax) {
        _sequence.markIncorrectPosture();
        if (elbowForward) {
          _addCorrection(WorkoutFeedbackAr.moveHandForward, 'warning', timestampMs);
          _currentCue = WorkoutFeedbackAr.moveHandForward;
        } else {
          _addCorrection(WorkoutFeedbackAr.moveHandBackward, 'warning', timestampMs);
          _currentCue = WorkoutFeedbackAr.moveHandBackward;
        }
      } else if (currentState == 's2') {
        _addCorrection(WorkoutFeedbackAr.extendFully, 'info', timestampMs);
        _currentCue = WorkoutFeedbackAr.extendFully;
      }
    } else if (currentState == 's1') {
      _sequence.clearIncorrectPosture();
    }

    if (_inactivity.update(currentState, timestampMs)) {
      _sequence.reset();
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  void _updatePhase(String? state) {
    switch (state) {
      case 's1':
        _phase = RepPhase.bottom;
        _currentCue ??= WorkoutFeedbackAr.startBent;
      case 's2':
        _phase = RepPhase.concentric;
        _currentCue ??= WorkoutFeedbackAr.extendArm;
      case 's3':
        _phase = RepPhase.top;
        _currentCue = WorkoutFeedbackAr.squeezeAtTop;
      default:
        _phase = RepPhase.idle;
    }
  }

  void _addCorrection(String cue, String severity, int timestampMs) {
    if (!_debouncer.shouldEmit(timestampMs)) return;
    _corrections.add(FormCorrection(cue: cue, severity: severity, timestampMs: timestampMs));
  }
}
