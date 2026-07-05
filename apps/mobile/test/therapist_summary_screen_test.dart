import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coachak/features/workout_cv/presentation/form_session_summary.dart';
import 'package:coachak/features/workout_cv/presentation/therapist_summary_screen.dart';

void main() {
  test('FormSessionSummary detects clinical metrics', () {
    final summary = FormSessionSummary(
      exerciseId: 'squat',
      exerciseNameAr: 'سكوات',
      repCount: 5,
      targetReps: 10,
      improperRepCount: 0,
      durationSeconds: 60,
      difficultyAr: 'مبتدئ',
      formScore: 80,
      formGrade: 'B',
      targetMet: false,
      xpAwarded: 0,
      formBonus: 0,
      timestamp: DateTime.now(),
      clinicalRomScore: 70,
    );
    expect(summary.hasClinicalMetrics, isTrue);
  });

  testWidgets('TherapistSummaryScreen renders Arabic report header', (tester) async {
    final summary = FormSessionSummary(
      exerciseId: 'squat',
      exerciseNameAr: 'سكوات',
      repCount: 10,
      targetReps: 10,
      improperRepCount: 1,
      durationSeconds: 120,
      difficultyAr: 'مبتدئ',
      formScore: 88,
      formGrade: 'B',
      targetMet: true,
      xpAwarded: 55,
      formBonus: 15,
      timestamp: DateTime(2026, 6, 28, 14, 30),
      clinicalRomScore: 82,
      clinicalStabilityScore: 91,
      clinicalAsymmetryDeg: 8,
      clinicalWeightShiftPct: 5,
      eccentricSeconds: 2.1,
      concentricSeconds: 1.4,
      clinicalDiagnosisAr: 'مدى حركة كامل ضمن الأهداف السريرية.',
      clinicalObservationsAr: const ['تحكم جيد في المرحلة الهابطة.'],
    );

    expect(summary.hasClinicalMetrics, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 2400)),
          child: TherapistSummaryScreen(summary: summary),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('ملخص الأداء'), findsOneWidget);
    expect(find.text('سكوات'), findsOneWidget);
    expect(find.text('تقييم الشكل'), findsOneWidget);
    expect(find.text('درجة الشكل'), findsOneWidget);
    expect(find.text('88 (B)'), findsOneWidget);
  });
}
