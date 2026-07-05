import 'dart:math';
import 'dart:ui' show Offset;

import 'pose_utils.dart';

/// Angle at [ref] between vectors to [a] and [b] (camera alignment check).
double calculateOffsetAngle(PosePoint a, PosePoint b, PosePoint ref) {
  final aRef = Offset(a.x - ref.x, a.y - ref.y);
  final bRef = Offset(b.x - ref.x, b.y - ref.y);
  final magA = sqrt(aRef.dx * aRef.dx + aRef.dy * aRef.dy);
  final magB = sqrt(bRef.dx * bRef.dx + bRef.dy * bRef.dy);
  if (magA == 0 || magB == 0) return 0;
  final cosAngle = ((aRef.dx * bRef.dx + aRef.dy * bRef.dy) / (magA * magB)).clamp(-1.0, 1.0);
  return acos(cosAngle) * 180 / pi;
}

/// Vertical inclination at [vertex] toward [from] (side-view depth metric).
double calculateVerticalAngle(PosePoint from, PosePoint vertex) {
  final vertical = PosePoint(vertex.x, 0);
  return calculateAngle(from, vertex, vertical);
}

class SideBodyLandmarks {
  const SideBodyLandmarks({
    required this.shoulder,
    required this.elbow,
    required this.wrist,
    required this.hip,
    required this.knee,
    required this.ankle,
    required this.foot,
  });

  final PosePoint shoulder;
  final PosePoint elbow;
  final PosePoint wrist;
  final PosePoint hip;
  final PosePoint knee;
  final PosePoint ankle;
  final PosePoint foot;
}

SideBodyLandmarks? selectSideView(Map<int, PosePoint> lm) {
  final leftShoulder = lm[PoseLandmarks.leftShoulder];
  final rightShoulder = lm[PoseLandmarks.rightShoulder];
  final leftFoot = lm[PoseLandmarks.leftAnkle];
  final rightFoot = lm[PoseLandmarks.rightAnkle];

  if (leftShoulder == null ||
      rightShoulder == null ||
      leftFoot == null ||
      rightFoot == null) {
    return null;
  }

  final leftSpan = (leftFoot.y - leftShoulder.y).abs();
  final rightSpan = (rightFoot.y - rightShoulder.y).abs();
  final useLeft = leftSpan > rightSpan;

  PosePoint? pick(int index) {
    final point = lm[index];
    if (point == null || point.likelihood < 0.35) return null;
    return point;
  }

  if (useLeft) {
    final shoulder = pick(PoseLandmarks.leftShoulder);
    final elbow = pick(PoseLandmarks.leftElbow);
    final wrist = pick(PoseLandmarks.leftWrist);
    final hip = pick(PoseLandmarks.leftHip);
    final knee = pick(PoseLandmarks.leftKnee);
    final ankle = pick(PoseLandmarks.leftAnkle);
    final foot = pick(PoseLandmarks.leftAnkle);
    if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || ankle == null) {
      return null;
    }
    return SideBodyLandmarks(
      shoulder: shoulder,
      elbow: elbow,
      wrist: wrist,
      hip: hip,
      knee: knee,
      ankle: ankle,
      foot: foot ?? ankle,
    );
  }

  final shoulder = pick(PoseLandmarks.rightShoulder);
  final elbow = pick(PoseLandmarks.rightElbow);
  final wrist = pick(PoseLandmarks.rightWrist);
  final hip = pick(PoseLandmarks.rightHip);
  final knee = pick(PoseLandmarks.rightKnee);
  final ankle = pick(PoseLandmarks.rightAnkle);
  final foot = pick(PoseLandmarks.rightAnkle);
  if (shoulder == null || elbow == null || wrist == null || hip == null || knee == null || ankle == null) {
    return null;
  }
  return SideBodyLandmarks(
    shoulder: shoulder,
    elbow: elbow,
    wrist: wrist,
    hip: hip,
    knee: knee,
    ankle: ankle,
    foot: foot ?? ankle,
  );
}

bool isCameraAligned(Map<int, PosePoint> lm, {required double offsetMax}) {
  final nose = lm[PoseLandmarks.nose];
  final leftShoulder = lm[PoseLandmarks.leftShoulder];
  final rightShoulder = lm[PoseLandmarks.rightShoulder];
  if (nose == null || leftShoulder == null || rightShoulder == null) return false;
  if (nose.likelihood < 0.35 || leftShoulder.likelihood < 0.35 || rightShoulder.likelihood < 0.35) {
    return false;
  }
  return calculateOffsetAngle(leftShoulder, rightShoulder, nose) <= offsetMax;
}

/// Front-view exercises (dumbbell fly) need the athlete facing the camera.
bool isFrontCameraAligned(Map<int, PosePoint> lm, {required double offsetMin}) {
  final nose = lm[PoseLandmarks.nose];
  final leftShoulder = lm[PoseLandmarks.leftShoulder];
  final rightShoulder = lm[PoseLandmarks.rightShoulder];
  if (nose == null || leftShoulder == null || rightShoulder == null) return false;
  if (nose.likelihood < 0.35 || leftShoulder.likelihood < 0.35 || rightShoulder.likelihood < 0.35) {
    return false;
  }
  return calculateOffsetAngle(leftShoulder, rightShoulder, nose) > offsetMin;
}

PosePoint? midpoint(PosePoint? a, PosePoint? b, {double minLikelihood = 0.5}) {
  if (a == null || b == null) return null;
  if (a.likelihood < minLikelihood || b.likelihood < minLikelihood) return null;
  return PosePoint((a.x + b.x) / 2, (a.y + b.y) / 2);
}

/// s1 → s2 → s3 → s2 → s1 rep validation from AI-Personal-Trainer.
class RepSequenceTracker {
  RepSequenceTracker();

  final List<String> _stateSeq = [];
  bool incorrectPosture = false;

  String? phaseFromAngle(int angle, ({(int, int) normal, (int, int) trans, (int, int) pass}) ranges) {
    // Deepest range first — overlapping bands otherwise never register bottom phase.
    if (_inRange(angle, ranges.pass)) return 's3';
    if (_inRange(angle, ranges.trans)) return 's2';
    if (_inRange(angle, ranges.normal)) return 's1';
    return null;
  }

  void updateSequence(String? state) {
    if (state == null) return;
    if (state == 's2') {
      final hasS3 = _stateSeq.contains('s3');
      final s2Count = _stateSeq.where((s) => s == 's2').length;
      if ((!hasS3 && s2Count == 0) || (hasS3 && s2Count == 1)) {
        _stateSeq.add(state);
      }
    } else if (state == 's3' && !_stateSeq.contains('s3') && _stateSeq.contains('s2')) {
      _stateSeq.add(state);
    }
  }

  /// Returns `correct`, `incorrect`, or null when still mid-rep.
  String? completeRepIfReturned(String? state) {
    if (state != 's1') return null;

    final visitedBottom = _stateSeq.contains('s3');
    final visitedTrans = _stateSeq.contains('s2');

    String? result;
    if (visitedBottom) {
      result = incorrectPosture ? 'incorrect' : 'correct';
    } else if (visitedTrans && _stateSeq.isNotEmpty) {
      // Count partial-depth reps for beginners instead of dropping them.
      result = incorrectPosture ? 'incorrect' : 'correct';
    }

    _stateSeq.clear();
    incorrectPosture = false;
    return result;
  }

  void markIncorrectPosture() => incorrectPosture = true;

  void clearIncorrectPosture() => incorrectPosture = false;

  void reset() {
    _stateSeq.clear();
    incorrectPosture = false;
  }

  bool _inRange(int value, (int, int) range) {
    final lo = min(range.$1, range.$2);
    final hi = max(range.$1, range.$2);
    return value >= lo && value <= hi;
  }
}

class CorrectionDebouncer {
  CorrectionDebouncer({this.cooldownMs = 1600});

  final int cooldownMs;
  int _lastMs = 0;

  bool shouldEmit(int timestampMs) {
    if (timestampMs - _lastMs < cooldownMs) return false;
    _lastMs = timestampMs;
    return true;
  }

  void reset() => _lastMs = 0;
}

class InactivityTracker {
  InactivityTracker({required this.thresholdMs});

  final int thresholdMs;
  int _lastChangeMs = 0;
  String? _lastState;

  bool update(String? state, int timestampMs) {
    if (state != _lastState) {
      _lastChangeMs = timestampMs;
      _lastState = state;
      return false;
    }
    return timestampMs - _lastChangeMs >= thresholdMs;
  }

  void reset(int timestampMs) {
    _lastChangeMs = timestampMs;
    _lastState = null;
  }
}
