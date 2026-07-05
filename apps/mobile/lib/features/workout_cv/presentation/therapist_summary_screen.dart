import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../shared/widgets/coachak_components.dart';
import 'form_session_summary.dart';

/// Arabic form session summary after a camera workout.
class TherapistSummaryScreen extends StatelessWidget {
  const TherapistSummaryScreen({super.key, required this.summary});

  final FormSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final dt = summary.timestamp;
    final dateStr =
        '${dt.day}/${dt.month}/${dt.year} — ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ملخص جلسة التمرين'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => context.pop(),
            tooltip: 'رجوع',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(CoachakSpacing.md),
          children: [
            _HeaderCard(dateStr: dateStr, summary: summary),
            const SizedBox(height: CoachakSpacing.md),
            _SectionCard(
              title: 'تفاصيل التمرين',
              icon: Icons.fitness_center_outlined,
              children: [
                _FieldRow(label: 'التمرين', value: summary.exerciseNameAr),
                _FieldRow(label: 'التكرارات', value: '${summary.repCount} / ${summary.targetReps}'),
                _FieldRow(label: 'المدة', value: '${summary.durationSeconds} ثانية'),
                _FieldRow(label: 'المستوى', value: summary.difficultyAr),
                if (summary.improperRepCount > 0)
                  _FieldRow(
                    label: 'تكرارات بحاجة تصحيح',
                    value: '${summary.improperRepCount}',
                  ),
                _FieldRow(
                  label: 'الهدف',
                  value: summary.targetMet ? 'تم تحقيقه ✓' : 'لم يُحقَّق',
                ),
              ],
            ),
            const SizedBox(height: CoachakSpacing.md),
            _SectionCard(
              title: 'تقييم الشكل',
              icon: Icons.verified_outlined,
              children: [
                CoachakStatTile(
                  icon: Icons.star_outline,
                  label: 'درجة الشكل',
                  value: '${summary.formScore} (${summary.formGrade})',
                  color: _gradeColor(summary.formGrade),
                ),
                if (summary.xpAwarded > 0) ...[
                  const SizedBox(height: CoachakSpacing.sm),
                  CoachakStatTile(
                    icon: Icons.bolt_outlined,
                    label: 'نقاط الخبرة',
                    value: '+${summary.xpAwarded}',
                    color: CoachakColors.xp,
                  ),
                ],
                if (summary.formBonus > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: CoachakSpacing.sm),
                    child: Text(
                      'مكافأة الشكل: +${summary.formBonus} نقطة',
                      style: CoachakTypography.bodyMuted(context),
                      textAlign: TextAlign.start,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: CoachakSpacing.xl),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.check),
              label: const Text('إغلاق الملخص'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: CoachakSpacing.md),
          ],
        ),
      ),
    );
  }

  static Color _gradeColor(String grade) {
    return switch (grade) {
      'A' => CoachakColors.seed,
      'B' => const Color(0xFF43A047),
      'C' => CoachakColors.accent,
      'D' => CoachakColors.streak,
      _ => Colors.red.shade700,
    };
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.dateStr, required this.summary});

  final String dateStr;
  final FormSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coachak',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: CoachakColors.seed,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: CoachakSpacing.xs),
            Text(
              'ملخص الأداء',
              style: CoachakTypography.display(context),
            ),
            const SizedBox(height: CoachakSpacing.xs),
            Text(dateStr, style: CoachakTypography.bodyMuted(context)),
            if (summary.targetMet) ...[
              const SizedBox(height: CoachakSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CoachakSpacing.md,
                  vertical: CoachakSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: CoachakColors.seed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CoachakRadius.md),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: CoachakColors.seed, size: 20),
                    SizedBox(width: CoachakSpacing.sm),
                    Text(
                      'جلسة ناجحة — تم تحقيق الهدف',
                      style: TextStyle(
                        color: CoachakColors.seed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: CoachakSpacing.sm),
                Text(title, style: CoachakTypography.sectionTitle(context)),
              ],
            ),
            const SizedBox(height: CoachakSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CoachakSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: CoachakTypography.bodyMuted(context),
              textAlign: TextAlign.start,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}
