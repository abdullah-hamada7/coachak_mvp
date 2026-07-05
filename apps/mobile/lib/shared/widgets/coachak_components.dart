import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

class CoachakProgressBar extends StatelessWidget {
  const CoachakProgressBar({
    super.key,
    required this.value,
    this.label,
    this.color,
    this.semanticLabel,
  });

  final double value;
  final String? label;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barColor = color ?? CoachakColors.xp;

    return Semantics(
      label: semanticLabel ?? label ?? 'Progress ${(value * 100).round()} percent',
      value: '${(value * 100).round()}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: CoachakTypography.bodyMuted(context)),
            const SizedBox(height: CoachakSpacing.xs),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(CoachakRadius.pill),
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

class CoachakStatTile extends StatelessWidget {
  const CoachakStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label: $value',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(CoachakSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (color ?? scheme.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CoachakRadius.md),
                ),
                child: Icon(icon, color: color ?? scheme.primary),
              ),
              const SizedBox(width: CoachakSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: CoachakTypography.bodyMuted(context),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: CoachakSpacing.xs),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.start,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoachakEmptyState extends StatelessWidget {
  const CoachakEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: CoachakSpacing.md),
            Text(title, style: CoachakTypography.display(context), textAlign: TextAlign.center),
            const SizedBox(height: CoachakSpacing.sm),
            Text(message, style: CoachakTypography.bodyMuted(context), textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: CoachakSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class CoachakSectionHeader extends StatelessWidget {
  const CoachakSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CoachakSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(title, style: CoachakTypography.sectionTitle(context))),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class CoachakStepIndicator extends StatelessWidget {
  const CoachakStepIndicator({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Row(
        children: List.generate(total, (i) {
          final active = i <= current;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(CoachakRadius.pill),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class CoachakGoalCard extends StatelessWidget {
  const CoachakGoalCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoachakRadius.lg),
        child: AnimatedContainer(
          duration: CoachakDurations.normal,
          padding: const EdgeInsets.all(CoachakSpacing.md),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surface,
            borderRadius: BorderRadius.circular(CoachakRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: CoachakSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: CoachakTypography.bodyMuted(context)),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class CoachakQuestCard extends StatelessWidget {
  const CoachakQuestCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.xpReward,
    required this.icon,
    required this.completed,
    required this.onTap,
    this.repeatable = false,
  });

  final String title;
  final String subtitle;
  final int xpReward;
  final IconData icon;
  final bool completed;
  final VoidCallback onTap;
  final bool repeatable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locked = completed && !repeatable;
    return Semantics(
      button: true,
      enabled: !locked,
      label: locked ? '$title completed' : '$title. $subtitle. Earn $xpReward XP',
      child: Card(
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(CoachakRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(CoachakSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: locked
                      ? scheme.tertiaryContainer
                      : completed
                          ? CoachakColors.seed.withValues(alpha: 0.15)
                          : CoachakColors.accent.withValues(alpha: 0.15),
                  child: Icon(
                    locked ? Icons.check : icon,
                    color: locked ? scheme.tertiary : completed ? CoachakColors.seed : CoachakColors.accent,
                  ),
                ),
                const SizedBox(width: CoachakSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              decoration: locked ? TextDecoration.lineThrough : null,
                            ),
                      ),
                      Text(subtitle, style: CoachakTypography.bodyMuted(context)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CoachakColors.xp.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(CoachakRadius.pill),
                  ),
                  child: Text(
                    locked
                        ? 'Done'
                        : completed && repeatable
                            ? 'Add more'
                            : '+$xpReward XP',
                    style: TextStyle(color: CoachakColors.xp, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
