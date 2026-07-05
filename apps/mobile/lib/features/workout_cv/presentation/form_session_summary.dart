/// Session data shown on the Arabic therapist summary screen.
class FormSessionSummary {
  const FormSessionSummary({
    required this.exerciseId,
    required this.exerciseNameAr,
    required this.repCount,
    required this.targetReps,
    required this.improperRepCount,
    required this.durationSeconds,
    required this.difficultyAr,
    required this.formScore,
    required this.formGrade,
    required this.targetMet,
    required this.xpAwarded,
    required this.formBonus,
    required this.timestamp,
    this.clinicalRomScore,
    this.clinicalStabilityScore,
    this.clinicalAsymmetryDeg,
    this.clinicalWeightShiftPct,
    this.eccentricSeconds,
    this.concentricSeconds,
    this.clinicalDiagnosisAr,
    this.clinicalObservationsAr = const [],
  });

  final String exerciseId;
  final String exerciseNameAr;
  final int repCount;
  final int targetReps;
  final int improperRepCount;
  final int durationSeconds;
  final String difficultyAr;
  final int formScore;
  final String formGrade;
  final bool targetMet;
  final int xpAwarded;
  final int formBonus;
  final DateTime timestamp;

  final int? clinicalRomScore;
  final int? clinicalStabilityScore;
  final int? clinicalAsymmetryDeg;
  final int? clinicalWeightShiftPct;
  final double? eccentricSeconds;
  final double? concentricSeconds;
  final String? clinicalDiagnosisAr;
  final List<String> clinicalObservationsAr;

  bool get hasClinicalMetrics =>
      clinicalRomScore != null ||
      clinicalStabilityScore != null ||
      (clinicalObservationsAr.isNotEmpty);
}
