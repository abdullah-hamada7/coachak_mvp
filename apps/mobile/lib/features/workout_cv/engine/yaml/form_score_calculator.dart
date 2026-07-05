import 'dart:math';

import '../pose_utils.dart';

/// 0–100 form score inspired by fitness-trainer-pose-estimation.
class FormScoreCalculator {
  FormScoreCalculator({
    this.idealAngles = const {},
    this.tempoMinSec = 1.0,
    this.tempoMaxSec = 3.0,
  });

  final Map<String, double> idealAngles;
  final double tempoMinSec;
  final double tempoMaxSec;

  int _current = 100;
  int _average = 100;
  final _repScores = <int>[];
  final _repDurations = <double>[];
  int? _repStartMs;

  int get currentScore => _current;
  int get averageScore => _average;

  static String gradeFor(int score) => switch (score) {
        >= 90 => 'A',
        >= 80 => 'B',
        >= 70 => 'C',
        >= 60 => 'D',
        _ => 'F',
      };

  void startRep(int timestampMs) => _repStartMs = timestampMs;

  void endRep(int timestampMs) {
    if (_repStartMs != null) {
      _repDurations.add((timestampMs - _repStartMs!) / 1000.0);
      _repStartMs = null;
    }
    _repScores.add(_current);
    if (_repScores.isNotEmpty) {
      _average = (_repScores.reduce((a, b) => a + b) / _repScores.length).round();
    }
  }

  int compute(Map<String, double> angles, List<FormCorrection> activeFeedback) {
    var score = 100.0;

    score -= min(_anglePenalty(angles), 40);
    score -= min(_tempoPenalty(), 30);
    score -= min(activeFeedback.length * 10.0, 30);

    _current = score.round().clamp(0, 100);
    return _current;
  }

  double _anglePenalty(Map<String, double> angles) {
    if (idealAngles.isEmpty) return 0;
    var total = 0.0;
    var count = 0;
    for (final entry in idealAngles.entries) {
      final current = angles['${entry.key}_angle'] ?? angles[entry.key] ?? angles['angle'];
      if (current == null) continue;
      total += (current - entry.value).abs() / 10 * 5;
      count++;
    }
    return count == 0 ? 0 : total / count;
  }

  double _tempoPenalty() {
    if (_repDurations.isEmpty) return 0;
    final last = _repDurations.last;
    if (last < tempoMinSec) return ((tempoMinSec - last) / 0.5) * 15;
    if (last > tempoMaxSec) return (last - tempoMaxSec) * 10;
    return 0;
  }

  void reset() {
    _current = 100;
    _average = 100;
    _repScores.clear();
    _repDurations.clear();
    _repStartMs = null;
  }
}
