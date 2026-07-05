// Arabic coaching copy for live form-analysis sessions.

class ExerciseCoachingAr {
  static const waitingForPose = 'قف أمام الكاميرا حتى يظهر الهيكل العظمي على جسمك.';

  static String sessionIntro(String exercise, int targetReps) {
    final exerciseName = _exerciseName(exercise);
    final tips = _exerciseTips(exercise);
    return 'ابدأ جلسة $exerciseName. هدفك $targetReps تكرار. $tips';
  }

  static String sessionComplete(int reps, int target, bool targetMet, {int xp = 0, int formBonus = 0}) {
    if (targetMet) {
      final bonus = formBonus > 0 ? ' مكافأة الشكل: +$formBonus نقطة.' : '';
      return 'أحسنت! أنهيت $reps من $target تكرار. +$xp نقطة خبرة.$bonus';
    }
    return 'انتهت الجلسة: $reps من $target تكرار. حاول الوصول للهدف في المرة القادمة.';
  }

  static String sessionSavedSnackBar(int reps, int target, bool met, int xp, int formBonus) {
    if (met) {
      final bonus = formBonus > 0 ? ' (مكافأة الشكل: +$formBonus)' : '';
      return 'تم الوصول للهدف: $reps/$target تكرار. +$xp نقطة خبرة$bonus';
    }
    return 'تم حفظ الجلسة: $reps/$target تكرار. حقّق هدفك لتحصل على نقاط الخبرة.';
  }

  /// Cues are already Arabic from engines/YAML — pass through with minimal pattern handling.
  static String translateCue(String? cue, String exercise) {
    if (cue == null || cue.isEmpty) return waitingForPose;
    return cue;
  }

  static String exerciseNameAr(String exercise) => _exerciseName(exercise);

  static String _exerciseName(String exercise) => switch (exercise) {
        'push_up' => 'ضغط',
        'bicep_curl' => 'ثني الذراع',
        'hammer_curl' => 'ثني المطرقة',
        'lunge' => 'اندفاع',
        'side_lunge' => 'اندفاع جانبي',
        'tricep_kickback' => 'ركلة خلفية',
        'tricep_dip' => 'غطس التراiceps',
        'dumbbell_fly' => 'رفرفة دمبل',
        'deadlift' => 'رفعة ميتة',
        'plank' => 'لوح',
        'wall_sit' => 'جلوس على الحائط',
        'shoulder_press' => 'ضغط الكتف',
        'glute_bridge' => 'جسر المؤخرة',
        'lateral_raise' => 'رفع جانبي',
        'leg_raise' => 'رفع الساق',
        'calf_raise' => 'رفع الساق الخلفية',
        'jumping_jack' => 'قفز النجمة',
        'high_knees' => 'رفع الركبة',
        'mountain_climber' => 'متسلق الجبل',
        'heel_slides' => 'انزلاق الكعب',
        'straight_leg_raise' => 'رفع الساق المستقيم',
        'ankle_pump' => 'ضخ الكاحل',
        'quad_sets' => 'تمرين الرباعية',
        _ => 'سكوات',
      };

  static String _exerciseTips(String exercise) => switch (exercise) {
        'push_up' =>
          'ابدأ بوضع اللوح، شدّ الجسم من الرأس للكعب، انزل بصدرك نحو الأرض ثم ادفع لأعلى ببطء.',
        'bicep_curl' || 'hammer_curl' =>
          'قف بجانب الكاميرا، ثبّت المرفقين بجانب جسمك، ارفع الوزن ببطء، ومدّ ذراعك بالكامل في الأسفل.',
        'lunge' || 'side_lunge' =>
          'قف بجانب الكاميرا، خطوة للأمام أو للجانب، انزل حتى 90° في الركبة، ثم ادفع للعودة.',
        'tricep_kickback' =>
          'قف بجانب الكاميرا، انحنِ للأمام، ثبّت المرفق ومدّ الذراع للخلف بالكامل.',
        'tricep_dip' =>
          'قف بجانب الكاميرا، انزل بمرفقيك حتى زاوية 90° ثم ادفع للأعلى.',
        'dumbbell_fly' =>
          'قف أمام الكاميرا مباشرة، افتح ذراعيك على مستوى الكتف ثم اجمعهما ببطء أمام صدرك.',
        'deadlift' =>
          'قف بجانب الكاميرا، افرد ظهرك، انزل بتحكم ثم ادفع الورك للأمام.',
        'plank' || 'wall_sit' =>
          'قف بجانب الكاميرا، شدّ عضلات البطن، وحافظ على جسم مستقيم.',
        'shoulder_press' || 'lateral_raise' =>
          'قف أمام الكاميرا، ارفع الذراعين ببطء وبشكل متساوٍ.',
        'glute_bridge' =>
          'استلقِ بجانب الكاميرا، ارفع الورك واضغط المؤخرة في الأعلى.',
        'jumping_jack' || 'high_knees' || 'mountain_climber' =>
          'قف أمام الكاميرا، حافظ على إيقاع ثابت وحركة كاملة.',
        'leg_raise' || 'calf_raise' || 'heel_slides' || 'straight_leg_raise' || 'ankle_pump' =>
          'قف أو استلقِ بجانب الكاميرا، تحكم في الحركة دون تأرجح.',
        'quad_sets' || 'wall_sit' || 'plank' =>
          'استلقِ أو قف بجانب الكاميرا، شدّ العضلة المستهدفة طوال الثبات.',
        _ =>
          'قف بجانب الكاميرا، قدميك بعرض الكتفين، انزل ببطء مع إبقاء صدرك مرفوعاً.',
      };
}
