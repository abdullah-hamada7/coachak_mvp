import '../../coaching/workout_feedback_ar.dart';
import '../form_analysis_core.dart';
import '../pose_utils.dart';
import 'clinical_rom_config.dart';

/// Session-level clinical metrics inspired by vr-production rehabilitation tracker.
class ClinicalMetricsTracker {
  ClinicalMetricsTracker({required String exerciseId})
      : _config = ClinicalRomCatalog.forExercise(exerciseId),
        _exerciseId = exerciseId;

  final ClinicalRomConfig? _config;
  final String _exerciseId;

  double _baselineAngle = 165;
  double? _peakAngle;
  double? _prevPrimaryAngle;
  double? _smoothedAngle;
  int _lastRepCount = 0;
  RepPhase? _lastPhase;
  int? _phaseStartMs;

  double _eccentricSec = 0;
  double _concentricSec = 0;
  double _latestStability = 100;
  double _latestAsymmetry = 0;
  double _latestWeightShiftPct = 0;
  double? _latestPrimaryAngle;

  final _repRomScores = <int>[];
  final _stabilitySamples = <double>[];

  bool get isActive => _config != null;

  int get avgRomScore {
    if (_repRomScores.isEmpty) return 0;
    return (_repRomScores.reduce((a, b) => a + b) / _repRomScores.length).round();
  }

  int get latestRomScore => _repRomScores.isEmpty ? 0 : _repRomScores.last;

  double get latestStability => _latestStability;

  double get latestAsymmetry => _latestAsymmetry;

  double get weightShiftPct => _latestWeightShiftPct;

  double get eccentricSec => _eccentricSec;

  double get concentricSec => _concentricSec;

  double? get latestPrimaryAngle => _latestPrimaryAngle;

  void reset() {
    final cfg = _config;
    _baselineAngle = cfg?.startAngle ?? 165;
    _peakAngle = null;
    _prevPrimaryAngle = null;
    _smoothedAngle = null;
    _lastRepCount = 0;
    _lastPhase = null;
    _phaseStartMs = null;
    _eccentricSec = 0;
    _concentricSec = 0;
    _latestStability = 100;
    _latestAsymmetry = 0;
    _latestWeightShiftPct = 0;
    _latestPrimaryAngle = null;
    _repRomScores.clear();
    _stabilitySamples.clear();
  }

  /// Returns an optional Arabic clinical cue to speak alongside engine feedback.
    String? processFrame(
    Map<int, PosePoint> lm,
    int timestampMs, {
    required RepPhase phase,
    required int repCount,
    required bool cameraAligned,
    required bool sideView,
  }) {
    final cfg = _config;
    if (cfg == null || !cameraAligned) return null;

    final metrics = _computeFrameMetrics(lm, cfg, sideView: sideView);
    if (metrics == null) return null;

    _latestPrimaryAngle = metrics.primaryAngle;
    _latestStability = metrics.stabilityScore;
    _latestAsymmetry = metrics.asymmetryDeg;
    _latestWeightShiftPct = metrics.weightShiftPct;
    _stabilitySamples.add(metrics.stabilityScore);

    _trackAngle(cfg, metrics.primaryAngle);
    _trackPhaseTiming(phase, timestampMs);

    if (repCount > _lastRepCount) {
      _onRepCompleted(cfg, metrics.primaryAngle);
      _lastRepCount = repCount;
    }

    return metrics.arabicCue;
  }

  Map<String, dynamic> sessionPayload() {
    final avgStability = _stabilitySamples.isEmpty
        ? _latestStability
        : _stabilitySamples.reduce((a, b) => a + b) / _stabilitySamples.length;

    return {
      'clinical_rom_score': avgRomScore,
      'clinical_stability_score': avgStability.round(),
      'clinical_asymmetry_deg': _latestAsymmetry.round(),
      'clinical_weight_shift_pct': _latestWeightShiftPct.round(),
      'eccentric_seconds': double.parse(_eccentricSec.toStringAsFixed(1)),
      'concentric_seconds': double.parse(_concentricSec.toStringAsFixed(1)),
      'clinical_diagnosis_ar': ClinicalRomCatalog.diagnosisAr(_exerciseId, avgRomScore),
      'clinical_observations_ar': _buildObservationsAr(avgStability.round()),
    };
  }

  List<String> _buildObservationsAr(int avgStability) {
    final obs = <String>[];
    if (_latestAsymmetry > 15) {
      obs.add('انحراف زاوية ${_latestAsymmetry.round()}° بين الجانبين — راقب أنماط التعويض.');
    } else if (_config?.primaryJoint == ClinicalJoint.knee) {
      obs.add('تماثل جانبي ضمن الحدود العلاجية الطبيعية.');
    }
    if (avgStability > 85) {
      obs.add('محاذاة ممتازة لسلسلة الحركة (ورك–ركبة–كاحل).');
    } else if (avgStability > 50) {
      obs.add('انحراف طفيف في الاستقرار — ركّز على ثبات قاعدة الدعم.');
    }
    if (_latestWeightShiftPct > 10) {
      obs.add('انزياح وزن جانبي ملحوظ — حاول توسيط جسمك.');
    }
    if (_eccentricSec > 0 && _concentricSec > 0 && _eccentricSec < _concentricSec) {
      obs.add('المرحلة الهابطة أسرع من الصاعدة — أبطئ النزول لتحكم أفضل.');
    } else if (_eccentricSec > 0) {
      obs.add('تحكم جيد في المرحلة الهابطة.');
    }
    if (avgRomScore > 0 && avgRomScore < 70) {
      obs.add('مدى حركة دون المستوى الأمثل — قد يدل على تيبس مفصلي.');
    }
    return obs;
  }

  void _trackAngle(ClinicalRomConfig cfg, double rawAngle) {
    if (rawAngle < 5 || rawAngle > 200) return;

    final prevRaw = _prevPrimaryAngle;
    _prevPrimaryAngle = rawAngle;
    if (prevRaw != null && (rawAngle - prevRaw).abs() > 40) return;

    _smoothedAngle = _smoothedAngle == null
        ? rawAngle
        : (_smoothedAngle! * 0.8) + (rawAngle * 0.2);

    if ((rawAngle - _baselineAngle).abs() < 30 && rawAngle > 10) {
      _baselineAngle = (_baselineAngle * 0.95) + (rawAngle * 0.05);
    }

    _peakAngle = _peakAngle == null
        ? rawAngle
        : cfg.flexionTarget
            ? rawAngle < _peakAngle! ? rawAngle : _peakAngle
            : rawAngle > _peakAngle! ? rawAngle : _peakAngle;
  }

  void _trackPhaseTiming(RepPhase phase, int timestampMs) {
    if (_lastPhase == phase) return;
    if (_lastPhase != null && _phaseStartMs != null) {
      final duration = (timestampMs - _phaseStartMs!) / 1000;
      if (_lastPhase == RepPhase.eccentric || _lastPhase == RepPhase.bottom) {
        _eccentricSec = duration;
      } else if (_lastPhase == RepPhase.concentric || _lastPhase == RepPhase.top) {
        _concentricSec = duration;
      }
    }
    _lastPhase = phase;
    _phaseStartMs = timestampMs;
  }

  void _onRepCompleted(ClinicalRomConfig cfg, double fallbackAngle) {
    final peak = _peakAngle ?? fallbackAngle;
    final score = ClinicalRomCatalog.computeRomScore(cfg, _baselineAngle, peak);
    _repRomScores.add(score);
    _peakAngle = null;
  }

  _FrameMetrics? _computeFrameMetrics(
    Map<int, PosePoint> lm,
    ClinicalRomConfig cfg, {
    required bool sideView,
  }) {
    final ls = lm[PoseLandmarks.leftShoulder];
    final rs = lm[PoseLandmarks.rightShoulder];
    final lh = lm[PoseLandmarks.leftHip];
    final rh = lm[PoseLandmarks.rightHip];
    final lk = lm[PoseLandmarks.leftKnee];
    final rk = lm[PoseLandmarks.rightKnee];
    final la = lm[PoseLandmarks.leftAnkle];
    final ra = lm[PoseLandmarks.rightAnkle];
    final le = lm[PoseLandmarks.leftElbow];
    final re = lm[PoseLandmarks.rightElbow];
    final lw = lm[PoseLandmarks.leftWrist];
    final rw = lm[PoseLandmarks.rightWrist];

    if (ls == null || rs == null) return null;

    final shoulderWidth = (ls.x - rs.x).abs().clamp(40.0, double.infinity);

    double? primary;
    String? cue;

    switch (cfg.primaryJoint) {
      case ClinicalJoint.knee:
        if (lh == null || rh == null || lk == null || rk == null || la == null || ra == null) {
          return null;
        }
        final kneeL = calculateAngle(lh, lk, la);
        final kneeR = calculateAngle(rh, rk, ra);
        primary = sideView ? kneeL : (kneeL < kneeR ? kneeL : kneeR);
        _latestAsymmetry = (kneeL - kneeR).abs();

        final backAngle = calculateAngle(ls, lh, lk);
        final driftL = _kneeDrift(lh, lk, la) / shoulderWidth;
        final driftR = _kneeDrift(rh, rk, ra) / shoulderWidth;
        final maxDrift = driftL > driftR ? driftL : driftR;
        final stability = (100 - maxDrift * 500).clamp(0, 100);

        final shoulderMidX = (ls.x + rs.x) / 2;
        final baseMidX = (la.x + ra.x) / 2;
        final weightShift = ((shoulderMidX - baseMidX).abs() / shoulderWidth) * 100;

        if (backAngle <= 130) {
          cue = WorkoutFeedbackAr.keepBackUpright;
        } else if (stability <= 50) {
          cue = WorkoutFeedbackAr.watchKneeAlignment;
        } else if (weightShift >= 15) {
          cue = WorkoutFeedbackAr.centerBodyWeight;
        }

        return _FrameMetrics(
          primaryAngle: primary,
          stabilityScore: stability.toDouble(),
          asymmetryDeg: _latestAsymmetry,
          weightShiftPct: weightShift,
          arabicCue: cue,
        );

      case ClinicalJoint.elbow:
        final useLeft = (le?.likelihood ?? 0) >= (re?.likelihood ?? 0);
        final shoulder = useLeft ? ls : rs;
        final elbow = useLeft ? le : re;
        final wrist = useLeft ? lw : rw;
        if (elbow == null || wrist == null) return null;
        primary = calculateAngle(shoulder, elbow, wrist);
        final elbowDrift = (elbow.x - shoulder.x).abs() / shoulderWidth;
        if (elbowDrift >= 0.25) cue = WorkoutFeedbackAr.keepElbowsPinned;
        return _FrameMetrics(
          primaryAngle: primary,
          stabilityScore: 100,
          asymmetryDeg: 0,
          weightShiftPct: 0,
          arabicCue: cue,
        );

      case ClinicalJoint.hip:
      case ClinicalJoint.ankle:
      case ClinicalJoint.holdTime:
        if (lh == null || lk == null || la == null) return null;
        primary = calculateAngle(ls, lh, lk);
        return _FrameMetrics(
          primaryAngle: primary,
          stabilityScore: 100,
          asymmetryDeg: 0,
          weightShiftPct: 0,
          arabicCue: cue,
        );
    }
  }

  double _kneeDrift(PosePoint hip, PosePoint knee, PosePoint ankle) {
    final mid = (hip.x + ankle.x) / 2;
    return (knee.x - mid).abs();
  }
}

class _FrameMetrics {
  _FrameMetrics({
    required this.primaryAngle,
    required this.stabilityScore,
    required this.asymmetryDeg,
    required this.weightShiftPct,
    this.arabicCue,
  });

  final double primaryAngle;
  final double stabilityScore;
  final double asymmetryDeg;
  final double weightShiftPct;
  final String? arabicCue;
}
