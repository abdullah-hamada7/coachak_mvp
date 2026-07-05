import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _benefits = [
    (icon: Icons.auto_awesome, title: 'AI coach that adapts', subtitle: 'Personalized guidance every day'),
    (icon: Icons.videocam_outlined, title: 'Form feedback in real time', subtitle: 'Rep counting and corrections on-device'),
    (icon: Icons.restaurant_menu, title: 'Nutrition made simple', subtitle: 'Snap meals and track macros effortlessly'),
    (icon: Icons.local_fire_department, title: 'Build streaks that stick', subtitle: 'XP, badges, and daily quests keep you moving'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CoachakSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: CoachakSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  'Welcome to Coachak',
                  style: CoachakTypography.display(context),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: CoachakSpacing.sm),
              Text(
                'Answer a few quick questions and we\'ll build your workout and nutrition plan.',
                style: CoachakTypography.bodyMuted(context),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: CoachakSpacing.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: _benefits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: CoachakSpacing.sm),
                  itemBuilder: (context, i) {
                    final b = _benefits[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(b.icon, color: Theme.of(context).colorScheme.primary),
                        ),
                        title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(b.subtitle),
                      ),
                    );
                  },
                ),
              ),
              FilledButton(
                onPressed: () => context.go('/onboarding'),
                child: const Text('Get started — 2 min setup'),
              ),
              const SizedBox(height: CoachakSpacing.sm),
              Text(
                'You can update your profile anytime in Progress.',
                style: CoachakTypography.bodyMuted(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
