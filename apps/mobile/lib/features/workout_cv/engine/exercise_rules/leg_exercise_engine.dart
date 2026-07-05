import '../../coaching/workout_feedback_ar.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';

/// Shared squat/lunge analyzer — identical logic in AI-Personal-Trainer.
class LegExerciseRuleEngine implements ExerciseRuleEngine {
  LegExerciseRuleEngine({
    required this.exerciseName,
    SquatThresholds? thresholds,
  }) : _thresholds = thresholds ?? SquatThresholds.forDifficulty(DifficultyLevel.beginner);

  @override
  final String exerciseName;

  final SquatThresholds _thresholds;
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

    final side = selectSideView(lm);
    if (side == null) {
      _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    if (!_cameraAligned) {
      _currentCue = WorkoutFeedbackAr.turnSideways;
      _addCorrection(WorkoutFeedbackAr.turnSideways, 'warning', timestampMs);
      return;
    }

    final hipVertical = calculateVerticalAngle(side.shoulder, side.hip);
    final kneeVertical = calculateVerticalAngle(side.hip, side.knee);
    final ankleVertical = calculateVerticalAngle(side.knee, side.ankle);
    _buildLegOverlays(side, hipVertical, kneeVertical, ankleVertical);

    final ranges = (
      normal: _thresholds.normalRange,
      trans: _thresholds.transRange,
      pass: _thresholds.passRange,
    );
    final currentState = _sequence.phaseFromAngle(kneeVertical.round(), ranges);
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
      if (hipVertical > _thresholds.hipBack) {
        _sequence.markIncorrectPosture();
        _addCorrection(WorkoutFeedbackAr.bendBackwards, 'warning', timestampMs);
        _currentCue = WorkoutFeedbackAr.bendBackwards;
      } else if (hipVertical < _thresholds.hipForward && currentState == 's2') {
        _addCorrection(WorkoutFeedbackAr.bendForward, 'info', timestampMs);
        _currentCue = WorkoutFeedbackAr.bendForward;
      }

      if (kneeVertical > _thresholds.kneeLow &&
          kneeVertical < _thresholds.kneeMid &&
          currentState == 's2') {
        _addCorrection(WorkoutFeedbackAr.lowerHips, 'info', timestampMs);
        _currentCue = WorkoutFeedbackAr.lowerHips;
      }

      if (kneeVertical > _thresholds.kneeDeep) {
        _sequence.markIncorrectPosture();
        _addCorrection(WorkoutFeedbackAr.squatTooDeep, 'warning', timestampMs);
        _currentCue = WorkoutFeedbackAr.squatTooDeep;
      }

      if (ankleVertical > _thresholds.ankleMax) {
        _sequence.markIncorrectPosture();
        _addCorrection(WorkoutFeedbackAr.kneeOverToe, 'warning', timestampMs);
        _currentCue = WorkoutFeedbackAr.kneeOverToe;
      }
    } else if (currentState == 's1') {
      _sequence.clearIncorrectPosture();
    }

    if (exerciseName == 'lunge') {
      if (currentState == 's2' || currentState == 's3') {
        _checkLungeFrontKnee(lm, timestampMs);
      }
    } else if (currentState == 's2' || currentState == 's3') {
      _checkKneeValgus(lm, timestampMs);
    }

    if (_inactivity.update(currentState, timestampMs)) {
      _sequence.reset();
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  void _checkKneeValgus(Map<int, PosePoint> lm, int timestampMs) {
    final leftKnee = lm[PoseLandmarks.leftKnee];
    final rightKnee = lm[PoseLandmarks.rightKnee];
    final leftAnkle = lm[PoseLandmarks.leftAnkle];
    final rightAnkle = lm[PoseLandmarks.rightAnkle];
    if (leftKnee == null || rightKnee == null || leftAnkle == null || rightAnkle == null) return;

    final kneeSpread = (leftKnee.x - rightKnee.x).abs();
    final ankleSpread = (leftAnkle.x - rightAnkle.x).abs();
    if (ankleSpread > 0 && kneeSpread < ankleSpread * 0.55) {
      _sequence.markIncorrectPosture();
      _addCorrection(WorkoutFeedbackAr.pushKneesOut, 'warning', timestampMs);
      _currentCue = WorkoutFeedbackAr.pushKneesOut;
    }
  }

  void _checkLungeFrontKnee(Map<int, PosePoint> lm, int timestampMs) {
    final leftKnee = lm[PoseLandmarks.leftKnee];
    final rightKnee = lm[PoseLandmarks.rightKnee];
    final leftAnkle = lm[PoseLandmarks.leftAnkle];
    final rightAnkle = lm[PoseLandmarks.rightAnkle];
    if (leftKnee == null || rightKnee == null || leftAnkle == null || rightAnkle == null) return;

    final leftForward = leftKnee.x - leftAnkle.x;
    final rightForward = rightKnee.x - rightAnkle.x;
    if (leftForward.abs() > 55 || rightForward.abs() > 55) {
      _sequence.markIncorrectPosture();
      _addCorrection(WorkoutFeedbackAr.kneeOverToe, 'warning', timestampMs);
      _currentCue = WorkoutFeedbackAr.kneeOverToe;
    }
  }

  void _buildLegOverlays(
    SideBodyLandmarks side,
    double hipVertical,
    double kneeVertical,
    double ankleVertical,
  ) {
    final multiplier = side.shoulder.x < side.hip.x ? -1.0 : 1.0;
    _overlayHints
      ..add(FormOverlayHint.guideLine(
        from: PosePoint(side.hip.x, side.hip.y - 80),
        to: PosePoint(side.hip.x, side.hip.y + 20),
      ))
      ..add(FormOverlayHint.arc(
        center: side.hip,
        radius: 30,
        startAngleDeg: -90,
        sweepAngleDeg: multiplier * hipVertical,
        label: hipVertical.round().toString(),
      ))
      ..add(FormOverlayHint.guideLine(
        from: PosePoint(side.knee.x, side.knee.y - 50),
        to: PosePoint(side.knee.x, side.knee.y + 20),
      ))
      ..add(FormOverlayHint.arc(
        center: side.knee,
        radius: 20,
        startAngleDeg: -90,
        sweepAngleDeg: -multiplier * kneeVertical,
        colorArgb: 0xFFFFFFFF,
        label: kneeVertical.round().toString(),
      ))
      ..add(FormOverlayHint.guideLine(
        from: PosePoint(side.ankle.x, side.ankle.y - 50),
        to: PosePoint(side.ankle.x, side.ankle.y + 20),
      ))
      ..add(FormOverlayHint.arc(
        center: side.ankle,
        radius: 30,
        startAngleDeg: -90,
        sweepAngleDeg: multiplier * ankleVertical,
        label: ankleVertical.round().toString(),
      ));
  }

  void _updatePhase(String? state) {
    switch (state) {
      case 's1':
        _phase = RepPhase.top;
      case 's2':
        _phase = RepPhase.eccentric;
      case 's3':
        _phase = RepPhase.bottom;
        _currentCue ??= WorkoutFeedbackAr.goodDepth;
      default:
        _phase = RepPhase.idle;
    }
  }

  void _addCorrection(String cue, String severity, int timestampMs) {
    if (!_debouncer.shouldEmit(timestampMs)) return;
    _corrections.add(FormCorrection(cue: cue, severity: severity, timestampMs: timestampMs));
  }
}
