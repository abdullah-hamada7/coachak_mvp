import 'dart:math';

import 'package:camera/camera.dart';

import '../../coaching/workout_feedback_ar.dart';
import '../camera_lens_holder.dart';
import '../exercise_thresholds.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';
import 'condition_evaluator.dart';
import 'form_score_calculator.dart';
import 'yaml_exercise_loader.dart';

/// Declarative exercise engine ported from fitness-trainer-pose-estimation YAML FSM.
class YamlExerciseEngine implements ExerciseRuleEngine, CameraLensHolder {
  YamlExerciseEngine(this.definition, {this.difficulty = DifficultyLevel.beginner})
      : _evaluator = ConditionEvaluator(),
        _formScore = FormScoreCalculator(
          idealAngles: _idealAngles(definition),
          tempoMinSec: (definition.formScoreConfig['tempo_range']?['min'] as num?)?.toDouble() ?? 1.0,
          tempoMaxSec: (definition.formScoreConfig['tempo_range']?['max'] as num?)?.toDouble() ?? 3.0,
        ),
        _smoothingWindow = (definition.smoothing['window'] as num?)?.toInt() ?? 3,
        _smoothingEnabled = definition.smoothing['enabled'] != false;

  final YamlExerciseDefinition definition;
  final DifficultyLevel difficulty;
  final ConditionEvaluator _evaluator;
  final FormScoreCalculator _formScore;
  final int _smoothingWindow;
  final bool _smoothingEnabled;

  String? _currentState;
  String? _prevState;
  String? _currentStateLeft;
  String? _prevStateLeft;
  String? _currentStateRight;
  String? _prevStateRight;
  int _repCount = 0;
  int _repCountLeft = 0;
  int _repCountRight = 0;
  int _improperRepCount = 0;
  bool _cameraAligned = false;
  RepPhase _phase = RepPhase.idle;
  String? _currentCue;
  final _corrections = <FormCorrection>[];
  final _overlayHints = <FormOverlayHint>[];
  double _romScore = 1.0;
  int _lastCountMs = 0;
  int _lastCountMsLeft = 0;
  int _lastCountMsRight = 0;
  int _holdStartMs = 0;
  int _holdDurationSec = 0;
  bool _badFormThisRep = false;
  final _angleHistory = <String, List<double>>{};
  final _debouncer = CorrectionDebouncer();
  final _inactivity = InactivityTracker(thresholdMs: 45000);

  /// Active camera — used when [YamlExerciseDefinition.cameraMode] is `auto`.
  @override
  CameraLensDirection? activeCameraLens;

  static Map<String, double> _idealAngles(YamlExerciseDefinition def) {
    final raw = def.formScoreConfig['ideal_angles'];
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  @override
  String get exerciseName => definition.name;

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

  int get formScoreValue => _formScore.currentScore;

  int get avgFormScoreValue => _formScore.averageScore;

  int get repCountLeft => _repCountLeft;

  int get repCountRight => _repCountRight;

  @override
  void reset() {
    _currentState = null;
    _prevState = null;
    _currentStateLeft = null;
    _prevStateLeft = null;
    _currentStateRight = null;
    _prevStateRight = null;
    _repCount = 0;
    _repCountLeft = 0;
    _repCountRight = 0;
    _improperRepCount = 0;
    _cameraAligned = false;
    _phase = RepPhase.idle;
    _currentCue = null;
    _corrections.clear();
    _overlayHints.clear();
    _romScore = 1.0;
    _lastCountMs = 0;
    _lastCountMsLeft = 0;
    _lastCountMsRight = 0;
    _holdStartMs = 0;
    _holdDurationSec = 0;
    _badFormThisRep = false;
    _angleHistory.clear();
    _formScore.reset();
    _debouncer.reset();
    _inactivity.reset(0);
  }

  @override
  void processFrame(Map<int, PosePoint> lm, int timestampMs) {
    _overlayHints.clear();
    _cameraAligned = _checkCamera(lm);
    final alignmentCue = _alignmentCue();
    if (!_cameraAligned) {
      _currentCue = alignmentCue;
      return;
    }

    final context = _buildContext(lm);
    if (context.isEmpty) {
      if (_cameraAligned) _currentCue = WorkoutFeedbackAr.stepIntoFrame;
      return;
    }

    if (definition.type == 'duration') {
      _prevState = _currentState;
      _currentState = _resolveState(context);
      _processDuration(timestampMs);
    } else if (definition.bilateral) {
      _processBilateralRepetition(context, timestampMs);
    } else {
      _prevState = _currentState;
      _currentState = _resolveState(context);
      _processRepetition(context, timestampMs);
    }

    final activeFeedback = _collectFeedback(context, timestampMs);
    _formScore.compute(context, activeFeedback);
    _buildOverlays(context);

    final inactivityKey = definition.bilateral
        ? '${_currentStateLeft ?? ''}|${_currentStateRight ?? ''}'
        : _currentState;
    if (_inactivity.update(inactivityKey, timestampMs)) {
      _currentState = null;
      _prevState = null;
      _currentStateLeft = null;
      _prevStateLeft = null;
      _currentStateRight = null;
      _prevStateRight = null;
      _currentCue = WorkoutFeedbackAr.sessionReset;
    }
  }

  String _alignmentCue() {
    final mode = definition.cameraMode;
    final useFront = mode == 'front' ||
        (mode == 'auto' && activeCameraLens == CameraLensDirection.front);
    return useFront ? WorkoutFeedbackAr.faceCamera : WorkoutFeedbackAr.turnSideways;
  }

  bool _usesFrontCamera() {
    final mode = definition.cameraMode;
    return mode == 'front' ||
        (mode == 'auto' && activeCameraLens == CameraLensDirection.front);
  }

  bool _checkCamera(Map<int, PosePoint> lm) {
    if (_usesFrontCamera()) {
      return isFrontCameraAligned(lm, offsetMin: 22);
    }
    return isCameraAligned(lm, offsetMax: 42);
  }

  Map<String, double> _buildContext(Map<int, PosePoint> lm) {
    final ctx = <String, double>{};
    for (final entry in definition.angles.entries) {
      final def = Map<String, dynamic>.from(entry.value as Map);
      final points = (def['points'] as List).map((e) => e.toString()).toList();
      if (points.length != 3) continue;
      final p1 = _landmark(lm, points[0]);
      final p2 = _landmark(lm, points[1]);
      final p3 = _landmark(lm, points[2]);
      if (p1 == null || p2 == null || p3 == null) continue;
      var angle = calculateAngle(p1, p2, p3);
      if (_smoothingEnabled) {
        angle = _smooth(entry.key, angle);
      }
      ctx['${entry.key}_angle'] = angle;
      if (entry.key == 'primary') ctx['angle'] = angle;
      if (entry.key == 'left' || entry.key == 'primary') ctx['left_angle'] = angle;
      if (entry.key == 'right' || entry.key == 'right_arm') ctx['right_angle'] = angle;
    }

    for (final entry in definition.validateAngles.entries) {
      final def = Map<String, dynamic>.from(entry.value as Map);
      final points = (def['points'] as List).map((e) => e.toString()).toList();
      if (points.length != 3) continue;
      final p1 = _landmark(lm, points[0]);
      final p2 = _landmark(lm, points[1]);
      final p3 = _landmark(lm, points[2]);
      if (p1 == null || p2 == null || p3 == null) continue;
      var angle = calculateAngle(p1, p2, p3);
      if (_smoothingEnabled) {
        angle = _smooth('validate_${entry.key}', angle);
      }
      ctx[entry.key] = angle;
    }

    for (final name in _landmarkNames) {
      final idx = _landmarkIndex[name];
      if (idx == null) continue;
      final p = lm[idx];
      if (p == null || p.likelihood < 0.5) continue;
      ctx['${name}_x'] = p.x;
      ctx['${name}_y'] = p.y;
    }
    _applyCombinedAngle(ctx);
    return ctx;
  }

  bool _checkValidation(Map<String, double> context) {
    final validationDef = definition.validation;
    if (validationDef.isEmpty) return true;

    for (final entry in validationDef.entries) {
      final def = Map<String, dynamic>.from(entry.value as Map);
      final condition = def['condition']?.toString() ?? '';
      if (condition.isEmpty) continue;
      if (!_evaluator.evaluate(condition, context)) return false;
    }
    return true;
  }

  void _applyCombinedAngle(Map<String, double> ctx) {
    if (definition.angleStrategy == 'primary') return;

    final samples = <double>[];
    for (final entry in ctx.entries) {
      if (!entry.key.endsWith('_angle')) continue;
      if (entry.key.contains('alignment') || entry.key.contains('torso')) continue;
      samples.add(entry.value);
    }
    if (samples.isEmpty) return;

    ctx['angle'] = definition.angleStrategy == 'min'
        ? samples.reduce((a, b) => a < b ? a : b)
        : samples.reduce((a, b) => a + b) / samples.length;
  }

  bool _isValidRepTransition({
    required String? prev,
    required String? current,
    required String? fromState,
    required String? trigger,
  }) {
    if (fromState == null || prev == fromState) return true;
    if (prev == 'down' && current == trigger) return true;
    if (prev == 'start' && current == trigger) return true;
    if (prev == 'descent' && current == trigger) return true;
    if (prev == 'ascent' && current == trigger) return true;
    if (prev == 'bottom' && current == trigger) return true;
    if (trigger == 'start' &&
        (prev == 'descent' || prev == 'ascent' || prev == 'bottom' || prev == 'curl')) {
      return true;
    }
    return false;
  }

  double _smooth(String key, double angle) {
    final history = _angleHistory.putIfAbsent(key, () => []);
    history.add(angle);
    if (history.length > _smoothingWindow) history.removeAt(0);
    return history.reduce((a, b) => a + b) / history.length;
  }

  String? _resolveStateForContext(Map<String, double> context) {
    for (final state in definition.stateOrder) {
      final def = Map<String, dynamic>.from(definition.states[state] as Map? ?? {});
      final condition = def['condition']?.toString() ?? 'false';
      if (_evaluator.evaluate(condition, context)) return state;
    }
    return null;
  }

  String? _resolveState(Map<String, double> context) =>
      _resolveStateForContext(context) ?? _currentState;

  void _processBilateralRepetition(Map<String, double> context, int timestampMs) {
    _prevStateLeft = _currentStateLeft;
    _prevStateRight = _currentStateRight;

    final leftCtx = Map<String, double>.from(context)
      ..['angle'] = context['left_angle'] ?? context['angle'] ?? 0;
    final rightCtx = Map<String, double>.from(context)
      ..['angle'] = context['right_angle'] ?? context['angle'] ?? 0;

    _currentStateLeft = _resolveStateForContext(leftCtx) ?? _currentStateLeft;
    _currentStateRight = _resolveStateForContext(rightCtx) ?? _currentStateRight;
    _currentState = _currentStateLeft;
    _prevState = _prevStateLeft;

    final trigger = definition.counter['trigger_state']?.toString();
    final fromState = definition.counter['from_state']?.toString();
    final minMs = (definition.minRepDurationSec * 1000).round();

    var counted = false;
    counted |= _countBilateralSide(
      prev: _prevStateLeft,
      current: _currentStateLeft,
      context: context,
      trigger: trigger,
      fromState: fromState,
      minMs: minMs,
      timestampMs: timestampMs,
      onCount: () => _repCountLeft++,
      lastCountMs: _lastCountMsLeft,
      setLastCountMs: (v) => _lastCountMsLeft = v,
    );
    counted |= _countBilateralSide(
      prev: _prevStateRight,
      current: _currentStateRight,
      context: context,
      trigger: trigger,
      fromState: fromState,
      minMs: minMs,
      timestampMs: timestampMs,
      onCount: () => _repCountRight++,
      lastCountMs: _lastCountMsRight,
      setLastCountMs: (v) => _lastCountMsRight = v,
    );

    _repCount = definition.countMode == 'unified'
        ? max(_repCountLeft, _repCountRight)
        : _repCountLeft + _repCountRight;

    if (counted) {
      if (_badFormThisRep) {
        _improperRepCount++;
        _currentCue = WorkoutFeedbackAr.fixNextRep;
        _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
      } else {
        _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
      }
      _badFormThisRep = false;
    }

    _phase = switch (_currentStateLeft ?? _currentStateRight) {
      'start' || 'down' || 'rest' || 'extended' || 'down' => RepPhase.top,
      'descent' || 'curl' || 'lift' || 'driving' || 'up' => RepPhase.eccentric,
      'ascent' || 'bottom' || 'flex' || 'tucked' => RepPhase.bottom,
      _ => RepPhase.idle,
    };
  }

  bool _countBilateralSide({
    required String? prev,
    required String? current,
    required Map<String, double> context,
    required String? trigger,
    required String? fromState,
    required int minMs,
    required int timestampMs,
    required void Function() onCount,
    required int lastCountMs,
    required void Function(int) setLastCountMs,
  }) {
    final stateChanged = prev != current;
    final reachedTrigger = current == trigger;
    final fromValid = _isValidRepTransition(
      prev: prev,
      current: current,
      fromState: fromState,
      trigger: trigger,
    );
    final timeValid = timestampMs - lastCountMs >= minMs;

    if (stateChanged && reachedTrigger && fromValid && timeValid) {
      setLastCountMs(timestampMs);
      if (!_checkValidation(context)) {
        _badFormThisRep = true;
        _currentCue = WorkoutFeedbackAr.fixNextRep;
        return true;
      }

      _formScore.endRep(timestampMs);
      onCount();
      return true;
    }
    if (prev == fromState && current == trigger) {
      _formScore.startRep(timestampMs);
    }
    return false;
  }

  void _processRepetition(Map<String, double> context, int timestampMs) {
    final trigger = definition.counter['trigger_state']?.toString();
    final fromState = definition.counter['from_state']?.toString();
    final minMs = (definition.minRepDurationSec * 1000).round();

    if (_prevState == fromState && _currentState == trigger) {
      _formScore.startRep(timestampMs);
    }

    final stateChanged = _prevState != _currentState;
    final reachedTrigger = _currentState == trigger;
    final fromValid = _isValidRepTransition(
      prev: _prevState,
      current: _currentState,
      fromState: fromState,
      trigger: trigger,
    );
    final timeValid = timestampMs - _lastCountMs >= minMs;

    if (stateChanged && reachedTrigger && fromValid && timeValid) {
      if (!_checkValidation(context)) {
        _badFormThisRep = true;
        _currentCue = WorkoutFeedbackAr.fixNextRep;
        return;
      }

      _formScore.endRep(timestampMs);
      if (_badFormThisRep) {
        _improperRepCount++;
        _currentCue = WorkoutFeedbackAr.fixNextRep;
        _romScore = (_romScore * 0.9).clamp(0.0, 1.0);
      } else {
        _repCount++;
        _currentCue = WorkoutFeedbackAr.repComplete(_repCount);
      }
      _badFormThisRep = false;
      _lastCountMs = timestampMs;
    }

    _phase = switch (_currentState) {
      'start' || 'down' || 'rest' => RepPhase.top,
      'descent' || 'curl' => RepPhase.eccentric,
      'ascent' || 'bottom' || 'flex' => RepPhase.bottom,
      _ => RepPhase.idle,
    };
  }

  void _processDuration(int timestampMs) {
    if (_currentState == definition.holdState) {
      if (_holdStartMs == 0) _holdStartMs = timestampMs;
      _holdDurationSec = ((timestampMs - _holdStartMs) / 1000).floor();
      _phase = RepPhase.bottom;
      _currentCue = WorkoutFeedbackAr.holdProgress(_holdDurationSec, definition.targetDurationSec);
      if (_holdDurationSec >= definition.targetDurationSec && _holdStartMs > 0) {
        _repCount++;
        _currentCue = WorkoutFeedbackAr.holdComplete(_repCount);
        _holdStartMs = 0;
        _holdDurationSec = 0;
      }
    } else {
      _holdStartMs = 0;
      _holdDurationSec = 0;
      _phase = RepPhase.top;
      _currentCue ??= WorkoutFeedbackAr.getIntoPosition;
    }
  }

  List<FormCorrection> _collectFeedback(Map<String, double> context, int timestampMs) {
    final active = <FormCorrection>[];
    for (final entry in definition.feedback.entries) {
      final def = Map<String, dynamic>.from(entry.value as Map);
      final condition = def['condition']?.toString() ?? 'false';
      if (!_evaluator.evaluate(condition, context)) continue;

      final message = def['message']?.toString() ?? WorkoutFeedbackAr.adjustForm;
      final severity = def['severity']?.toString() ?? 'warning';
      if (severity == 'warning' || severity == 'error') _badFormThisRep = true;
      if (_debouncer.shouldEmit(timestampMs)) {
        final c = FormCorrection(cue: message, severity: severity, timestampMs: timestampMs);
        _corrections.add(c);
        active.add(c);
        final holdActive = definition.type == 'duration' && _currentState == definition.holdState;
        if (!holdActive || severity == 'warning' || severity == 'error') {
          _currentCue = message;
        }
      }
    }
    return active;
  }

  void _buildOverlays(Map<String, double> context) {
    for (final entry in definition.angles.entries) {
      final angle = context['${entry.key}_angle'];
      if (angle == null) continue;
      final def = Map<String, dynamic>.from(entry.value as Map);
      final points = (def['points'] as List).map((e) => e.toString()).toList();
      if (points.length != 3) continue;
      final vertexName = points[1];
      final x = context['${vertexName}_x'];
      final y = context['${vertexName}_y'];
      if (x == null || y == null) continue;
      _overlayHints.add(FormOverlayHint.label(
        center: PosePoint(x, y),
        label: angle.round().toString(),
      ));
    }
  }

  PosePoint? _landmark(Map<int, PosePoint> lm, String name) {
    final idx = _landmarkIndex[name];
    if (idx == null) return null;
    final p = lm[idx];
    if (p == null || p.likelihood < 0.35) return null;
    return p;
  }

  static const _landmarkNames = [
    'nose',
    'left_shoulder',
    'right_shoulder',
    'left_elbow',
    'right_elbow',
    'left_wrist',
    'right_wrist',
    'left_hip',
    'right_hip',
    'left_knee',
    'right_knee',
    'left_ankle',
    'right_ankle',
  ];

  static const _landmarkIndex = {
    'nose': PoseLandmarks.nose,
    'left_shoulder': PoseLandmarks.leftShoulder,
    'right_shoulder': PoseLandmarks.rightShoulder,
    'left_elbow': PoseLandmarks.leftElbow,
    'right_elbow': PoseLandmarks.rightElbow,
    'left_wrist': PoseLandmarks.leftWrist,
    'right_wrist': PoseLandmarks.rightWrist,
    'left_hip': PoseLandmarks.leftHip,
    'right_hip': PoseLandmarks.rightHip,
    'left_knee': PoseLandmarks.leftKnee,
    'right_knee': PoseLandmarks.rightKnee,
    'left_ankle': PoseLandmarks.leftAnkle,
    'right_ankle': PoseLandmarks.rightAnkle,
  };
}
