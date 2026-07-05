import '../../coaching/workout_feedback_ar.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';

class CurlRuleEngine implements ExerciseRuleEngine {
  CurlRuleEngine({DifficultyLevel difficulty = DifficultyLevel.beginner})
      : _thresholds = CurlThresholds.forDifficulty(difficulty);

  final CurlThresholds _thresholds;
  final _sequence = RepSequenceTracker();
  final _debouncer = CorrectionDebouncer();
  late final _inactivity = InactivityTracker(thresholdMs: _thresholds.inactiveMs);

  int _repCount = 0;
  int _improperRepCount = 0;
  bool _cameraAligned = false;
  RepPhase _phase = RepPhase.idle;
  String? _currentCue;
  final _corrections = <FormCorrection>[];
  final _overlayHints = <FormOverlayHint>[];
  double _romScore = 1.0;

  @override
  String get exerciseName => 'bicep_curl';

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
    _cameraAligned = isCameraAligned(lm, offsetMax: _thresholds.offsetMax);
    if (!_cameraAligned) {
      _currentCue = WorkoutFeedbackAr.turnSideways;
      _addCorrection(WorkoutFeedbackAr.turnSideways, 'warning', timestampMs);
      return;
    }

    final side = selectSideView(lm);
    if (side == null) {
      _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    final elbowAngle = calculateAngle(side.shoulder, side.elbow, side.wrist);
    final shoulderHipAngle = calculateVerticalAngle(side.shoulder, side.hip);
    final elbowShoulderAngle = 180 - calculateVerticalAngle(side.elbow, side.shoulder);
    final elbowForward = side.elbow.x < side.shoulder.x;
    final multiplier = elbowForward ? -1.0 : 1.0;

    _overlayHints
      ..add(FormOverlayHint.guideLine(
        from: PosePoint(side.hip.x, side.hip.y - 30),
        to: PosePoint(side.hip.x, side.hip.y + 20),
      ))
      ..add(FormOverlayHint.arc(
        center: side.hip,
        radius: 30,
        startAngleDeg: -90,
        sweepAngleDeg: multiplier * shoulderHipAngle,
        label: shoulderHipAngle.round().toString(),
      ))
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
    _updatePhase(currentState, elbowAngle);

    final repResult = _sequence.completeRepIfReturned(currentState);
    if (repResult == 'correct') {
      _repCount++;
      _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
    } else if (repResult == 'incorrect') {
      _improperRepCount++;
      _currentCue = WorkoutFeedbackAr.fixNextRep;
      _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
    }

    if (currentState != null && currentState != 's1') {
      if (shoulderHipAngle > _thresholds.hipMax) {
        _sequence.incorrectPosture = true;
        _addCorrection(WorkoutFeedbackAr.straightenBack, 'warning', timestampMs);
        _currentCue = WorkoutFeedbackAr.straightenBack;
      }

      if (elbowShoulderAngle > _thresholds.shoulderMax) {
        _sequence.incorrectPosture = true;
        if (elbowForward) {
          _addCorrection(WorkoutFeedbackAr.moveHandForward, 'warning', timestampMs);
          _currentCue = WorkoutFeedbackAr.moveHandForward;
        } else {
          _addCorrection(WorkoutFeedbackAr.moveHandBackward, 'warning', timestampMs);
          _currentCue = WorkoutFeedbackAr.moveHandBackward;
        }
      } else if (currentState == 's2' && !_sequence.incorrectPosture) {
        _addCorrection(WorkoutFeedbackAr.curlHigher, 'info', timestampMs);
        _currentCue = WorkoutFeedbackAr.curlHigher;
      }
    }

    if (_inactivity.update(currentState, timestampMs)) {
      _repCount = 0;
      _improperRepCount = 0;
      _sequence.reset();
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  void _updatePhase(String? state, double elbowAngle) {
    switch (state) {
      case 's1':
        _phase = RepPhase.bottom;
      case 's2':
        _phase = RepPhase.concentric;
        _currentCue ??= WorkoutFeedbackAr.curlUp;
      case 's3':
        _phase = RepPhase.top;
        _currentCue = WorkoutFeedbackAr.squeezeAtTop;
      default:
        if (elbowAngle > 150) {
          _phase = RepPhase.bottom;
        } else if (elbowAngle < 60) {
          _phase = RepPhase.top;
        } else {
          _phase = RepPhase.eccentric;
        }
    }
  }

  void _addCorrection(String cue, String severity, int timestampMs) {
    if (!_debouncer.shouldEmit(timestampMs)) return;
    _corrections.add(FormCorrection(cue: cue, severity: severity, timestampMs: timestampMs));
  }
}
