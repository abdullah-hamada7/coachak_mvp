/// Clinical ROM targets ported from vr-production/src/utils/romConfig.js
class ClinicalRomConfig {
  const ClinicalRomConfig({
    required this.primaryJoint,
    required this.targetAngle,
    required this.startAngle,
    required this.labelAr,
  });

  final ClinicalJoint primaryJoint;
  final double targetAngle;
  final double startAngle;
  final String labelAr;

  bool get flexionTarget => targetAngle < startAngle;
}

enum ClinicalJoint { knee, elbow, hip, ankle, holdTime }

class ClinicalRomCatalog {
  ClinicalRomCatalog._();

  static const _configs = <String, ClinicalRomConfig>{
    'squat': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.knee,
      targetAngle: 120,
      startAngle: 165,
      labelAr: 'ثني الركبة',
    ),
    'lunge': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.knee,
      targetAngle: 115,
      startAngle: 165,
      labelAr: 'ثني الركبة',
    ),
    'side_lunge': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.knee,
      targetAngle: 115,
      startAngle: 165,
      labelAr: 'ثني الركبة',
    ),
    'bicep_curl': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.elbow,
      targetAngle: 65,
      startAngle: 155,
      labelAr: 'ثني المرفق',
    ),
    'hammer_curl': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.elbow,
      targetAngle: 47,
      startAngle: 155,
      labelAr: 'ثني المرفق',
    ),
    'push_up': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.elbow,
      targetAngle: 90,
      startAngle: 170,
      labelAr: 'ثني المرفق',
    ),
    'heel_slides': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.knee,
      targetAngle: 110,
      startAngle: 160,
      labelAr: 'ثني الركبة',
    ),
    'straight_leg_raise': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.hip,
      targetAngle: 120,
      startAngle: 170,
      labelAr: 'ثني الورك',
    ),
    'ankle_pump': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.ankle,
      targetAngle: 90,
      startAngle: 120,
      labelAr: 'مدى الكاحل',
    ),
    'leg_raise': ClinicalRomConfig(
      primaryJoint: ClinicalJoint.hip,
      targetAngle: 120,
      startAngle: 170,
      labelAr: 'رفع الساق',
    ),
  };

  static ClinicalRomConfig? forExercise(String exerciseId) => _configs[exerciseId];

  static bool supports(String exerciseId) => _configs.containsKey(exerciseId);

  static int computeRomScore(ClinicalRomConfig cfg, double baseline, double peak) {
    final range = (cfg.startAngle - cfg.targetAngle).abs();
    if (range <= 0) return 100;
    final achieved = cfg.flexionTarget
        ? (baseline - peak).clamp(0, range)
        : (peak - baseline).clamp(0, range);
    return ((achieved / range) * 100).round().clamp(0, 100);
  }

  static String diagnosisAr(String exerciseId, int romScore) {
    if (romScore >= 88) return 'مدى حركة كامل ضمن الأهداف السريرية.';
    if (romScore >= 65) return 'قيود خفيفة في مدى الحركة — استمر بالتمدد التدريجي.';
    if (romScore >= 40) return 'قيود متوسطة — راجع المعالج إذا استمرت.';
    return 'قيود شديدة في مدى الحركة — يُنصح بتقييم سريري.';
  }
}
