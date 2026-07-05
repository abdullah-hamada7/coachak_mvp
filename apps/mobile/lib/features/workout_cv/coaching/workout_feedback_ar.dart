/// Arabic-only live coaching cues for form analysis (voice + on-screen).
class WorkoutFeedbackAr {
  WorkoutFeedbackAr._();

  static const faceCamera = 'قف أمام الكاميرا مباشرة.';
  static const turnSideways = 'قف بجانب الكاميرا حتى يرى جسمك من الجانب.';
  static const stepIntoFrame = 'تأكد أن جسمك بالكامل داخل إطار الكاميرا.';
  static const stepBackFromCamera = 'ابتعد قليلاً عن الكاميرا حتى يظهر جسمك بالكامل.';
  static const fixNextRep = 'صحّح وضعيتك في التكرار التالي.';
  static const sessionReset = 'تم إعادة العداد بسبب التوقف — استمر بالحركة.';
  static const getIntoPosition = 'خذ وضع البداية الصحيح.';
  static const adjustForm = 'عدّل وضعيتك.';

  static String repComplete(int n) => 'تكرار $n! ممتاز، استمر.';
  static String holdProgress(int current, int target) => 'ثبّت الوضع $current / ${target}ث';
  static String holdComplete(int set) => 'اكتمل الثبات! المجموعة $set';
  static String holdSetComplete(int set) => 'اكتمل الثبات! المجموعة $set';

  // Squat / lunge
  static const pushKneesOut = 'ادفع ركبتيك للخارج، لا تدعها تنحني للداخل.';
  static const bendBackwards = 'لا تميل للخلف — شدّ عضلات البطن.';
  static const bendForward = 'انحنِ قليلاً للأمام مع إبقاء الظهر مستقيماً.';
  static const lowerHips = 'انزل بوسط جسمك أكثر لأسفل.';
  static const squatTooDeep = 'لا تنزل أكثر من اللازم — ارفع قليلاً.';
  static const kneeOverToe = 'لا تدع ركبتك تتجاوز أصابع قدميك.';
  static const goodDepth = 'عمق ممتاز، استمر بنفس الشكل.';

  // Push-up
  static const braceCore = 'شدّ عضلات البطن وحافظ على جسمك مستقيماً.';
  static const chestToFloor = 'اقترب بصدرك من الأرض قبل أن تدفع لأعلى.';
  static const pushUp = 'ادفع لأعلى بقوة مع الحفاظ على استقامة الجسم.';

  // Curl / kickback
  static const straightenBack = 'افرد ظهرك ولا تميل للخلف.';
  static const moveHandForward = 'لا تحرّك يدك للأمام — ثبّت المرفق.';
  static const moveHandBackward = 'لا تحرّك يدك للخلف — ثبّت المرفق.';
  static const curlHigher = 'ارفع الوزن أعلى قبل أن تنزل.';
  static const extendFully = 'مدّ ذراعك بالكامل.';
  static const curlUp = 'ارفع الوزن ببطء مع شدّ العضلة.';
  static const squeezeAtTop = 'اضغط في أعلى الحركة قبل أن تنزل ببطء.';
  static const keepElbowsPinned = 'ثبّت المرفقين بجانب جسمك.';
  static const elbowsStill = 'ابقِ المرفقين ثابتين بجانبك.';
  static const fullExtension = 'مدّ ذراعك بالكامل في الأسفل قبل التكرار التالي.';
  static const startBent = 'ابدأ والمرفق مثني.';
  static const extendArm = 'مدّ الذراع للخلف.';

  // Fly
  static const keepArmsSymmetrical = 'حافظ على تساوي حركة الذراعين.';
  static const keepElbowsSoft = 'أبقِ مرفقيك مثنيين قليلاً — لا تفرّغهما بالكامل.';
  static const openWide = 'افتح ذراعيك على مستوى الكتف.';
  static const squeezeChest = 'اضغط في منتصف الحركة.';
  static const bringArmsTogether = 'اجمع ذراعيك ببطء أمام صدرك.';
  static const keepBackUpright = 'حافظ على استقامة ظهرك — ارفع صدرك.';
  static const watchKneeAlignment = 'راقب محاذاة الركبة — لا تدعها تنحرف للداخل.';
  static const centerBodyWeight = 'وسّط وزن جسمك — لا تميل للجانب.';
  static const lowerWithControl = 'انزل ببطء مع التحكم.';
  static const keepBodyStraight = 'حافظ على استقامة الجسم من الرأس للكعب وشدّ المؤخرة.';
}
