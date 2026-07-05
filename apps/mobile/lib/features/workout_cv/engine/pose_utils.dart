import 'dart:math';
import 'dart:ui' show Offset;

import 'yaml/form_score_calculator.dart';
import 'yaml/yaml_exercise_engine.dart';

/// Pose landmark indices matching ML Kit PoseDetection.
class PoseLandmarks {
  static const nose = 0;
  static const leftShoulder = 11;
  static const rightShoulder = 12;
  static const leftElbow = 13;
  static const rightElbow = 14;
  static const leftWrist = 15;
  static const rightWrist = 16;
  static const leftHip = 23;
  static const rightHip = 24;
  static const leftKnee = 25;
  static const rightKnee = 26;
  static const leftAnkle = 27;
  static const rightAnkle = 28;
}

class PosePoint {
  PosePoint(this.x, this.y, {this.likelihood = 1.0});
  final double x;
  final double y;
  final double likelihood;
}

double calculateAngle(PosePoint a, PosePoint b, PosePoint c) {
  final ab = Offset(a.x - b.x, a.y - b.y);
  final cb = Offset(c.x - b.x, c.y - b.y);
  final dot = ab.dx * cb.dx + ab.dy * cb.dy;
  final magAb = sqrt(ab.dx * ab.dx + ab.dy * ab.dy);
  final magCb = sqrt(cb.dx * cb.dx + cb.dy * cb.dy);
  if (magAb == 0 || magCb == 0) return 180;
  final cosAngle = (dot / (magAb * magCb)).clamp(-1.0, 1.0);
  return acos(cosAngle) * 180 / pi;
}

class FormCorrection {
  FormCorrection({required this.cue, required this.severity, required this.timestampMs});
  final String cue;
  final String severity;
  final int timestampMs;
}

enum RepPhase { idle, eccentric, bottom, concentric, top }

/// Visual hints rendered over the camera preview (OpenCV-style angle arcs).
class FormOverlayHint {
  const FormOverlayHint.arc({
    required this.center,
    required this.radius,
    required this.startAngleDeg,
    required this.sweepAngleDeg,
    this.colorArgb = 0xFFFFFFFF,
    this.label,
  })  : from = null,
        to = null,
        kind = FormOverlayKind.arc;

  const FormOverlayHint.guideLine({
    required this.from,
    required this.to,
    this.colorArgb = 0xFF00BFFF,
  })  : center = null,
        radius = null,
        startAngleDeg = null,
        sweepAngleDeg = null,
        label = null,
        kind = FormOverlayKind.guideLine;

  const FormOverlayHint.label({
    required this.center,
    required this.label,
    this.colorArgb = 0xFF64FF96,
  })  : from = null,
        to = null,
        radius = null,
        startAngleDeg = null,
        sweepAngleDeg = null,
        kind = FormOverlayKind.label;

  final FormOverlayKind kind;
  final PosePoint? center;
  final PosePoint? from;
  final PosePoint? to;
  final double? radius;
  final double? startAngleDeg;
  final double? sweepAngleDeg;
  final int colorArgb;
  final String? label;
}

enum FormOverlayKind { arc, guideLine, label }

abstract class ExerciseRuleEngine {
  String get exerciseName;
  int get repCount;
  int get improperRepCount;
  bool get cameraAligned;
  RepPhase get phase;
  String? get currentCue;
  List<FormCorrection> get corrections;
  List<FormOverlayHint> get overlayHints;
  double get romScore;

  void processFrame(Map<int, PosePoint> landmarks, int timestampMs);
  void reset();
}

extension ExerciseFormScoring on ExerciseRuleEngine {
  int get formScore => this is YamlExerciseEngine
      ? (this as YamlExerciseEngine).formScoreValue
      : (romScore * 100).round();

  int get avgFormScore => this is YamlExerciseEngine
      ? (this as YamlExerciseEngine).avgFormScoreValue
      : formScore;

  String get formGrade => FormScoreCalculator.gradeFor(avgFormScore);
}
