import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router_refresh.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/json_utils.dart';
import '../../../services/api/api_client.dart';
import '../../../services/storage/token_storage.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../../services/user/profile_provider.dart';
import '../../../shared/widgets/coachak_components.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _gamification;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final progress = await api.getProgressSummary();
      final gamification = await api.getGamificationState();
      ref.invalidate(subscriptionProvider);
      setState(() {
        _progress = progress;
        _gamification = gamification;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await TokenStorage.clear();
    await ref.read(profileCacheProvider.notifier).clear();
    RouterRefresh.instance.refresh();
    if (mounted) context.go('/login');
  }

  int _xpInCurrentLevel(int totalXp) => totalXp % 200;
  double _levelProgress(int totalXp) => _xpInCurrentLevel(totalXp) / 200;

  double _macroNum(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(profileCacheProvider).displayName ?? 'Athlete';
    final xp = jsonInt(_progress?['xp'] ?? _gamification?['total_xp']);
    final level = jsonInt(_progress?['level'] ?? _gamification?['level'], 1);
    final workoutStreak = jsonInt(_gamification?['workout_streak']);
    final workoutsDone = jsonInt(_progress?['workouts_completed']);
    final todayMacros = _progress?['today_macros'] is Map ? (_progress!['today_macros'] as Map).map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    final targetMacros = _progress?['target_macros'] is Map ? (_progress!['target_macros'] as Map).map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    final subscription = ref.watch(subscriptionProvider).valueOrNull;
    final unlimitedForm = subscription?.isUnlimited('form_sessions') ?? false;
    final formUsed = subscription?.usedFor('form_sessions') ?? 0;
    final formLimit = subscription?.isOwner == true ? null : subscription?.limitFor('form_sessions');
    final formQuestSubtitle = unlimitedForm
        ? '∞ unlimited on your plan • repeat anytime'
        : formLimit != null
            ? '$formUsed / $formLimit sessions this month'
            : 'Camera rep tracking • repeat anytime';

    final mealsLoggedToday = _macroNum(todayMacros['calories']) > 0;
    final unlimitedMeals = subscription?.isUnlimited('food_scans') ?? false;
    final mealUsed = subscription?.usedFor('food_scans') ?? 0;
    final mealLimit = subscription?.isOwner == true ? null : subscription?.limitFor('food_scans');
    final mealQuestSubtitle = mealsLoggedToday
        ? 'Logged today — tap to add more meals'
        : unlimitedMeals
            ? '∞ unlimited — snap or log manually'
            : mealLimit == 0
                ? 'Manual log free • photo scan needs Fuel'
                : mealLimit != null
                    ? '$mealUsed / $mealLimit photo scans • manual always free'
                    : 'Snap a photo or log manually';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: Icon(subscription?.isActive == true ? Icons.workspace_premium : Icons.star_outline),
            tooltip: 'Subscription',
            onPressed: () => context.push('/paywall'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(CoachakSpacing.md),
                children: [
                  _GreetingHeader(name: name, streak: workoutStreak),
                  if (subscription != null && subscription.isFree) ...[
                    const SizedBox(height: CoachakSpacing.sm),
                    _UpgradeBanner(onTap: () => context.push('/paywall')),
                  ],
                  const SizedBox(height: CoachakSpacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(CoachakSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: CoachakColors.xp.withValues(alpha: 0.15),
                                child: Text(
                                  'L$level',
                                  style: TextStyle(
                                    color: CoachakColors.xp,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: CoachakSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Level $level', style: CoachakTypography.sectionTitle(context)),
                                    Text('$xp total XP', style: CoachakTypography.bodyMuted(context)),
                                  ],
                                ),
                              ),
                              if (workoutStreak > 0)
                                _StreakBadge(days: workoutStreak),
                            ],
                          ),
                          const SizedBox(height: CoachakSpacing.md),
                          CoachakProgressBar(
                            value: _levelProgress(xp),
                            label: '${_xpInCurrentLevel(xp)} / 200 XP to Level ${level + 1}',
                            color: CoachakColors.xp,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CoachakSpacing.md),
                  _DailyMacrosDashboardCard(
                    todayMacros: todayMacros,
                    targetMacros: targetMacros,
                  ),
                  const SizedBox(height: CoachakSpacing.lg),
                  CoachakSectionHeader(title: 'Daily quests'),
                  CoachakQuestCard(
                    title: 'Complete a workout',
                    subtitle: 'Mark a session done in Plans',
                    xpReward: 50,
                    icon: Icons.fitness_center,
                    completed: workoutsDone > 0 && workoutStreak > 0,
                    onTap: () => context.go('/plans'),
                  ),
                  const SizedBox(height: CoachakSpacing.sm),
                  CoachakQuestCard(
                    title: 'Log your meals',
                    subtitle: mealQuestSubtitle,
                    xpReward: 20,
                    icon: Icons.restaurant,
                    completed: mealsLoggedToday,
                    repeatable: true,
                    onTap: () async {
                      final logged = await context.push<bool>('/food');
                      if (logged == true) _load();
                    },
                  ),
                  const SizedBox(height: CoachakSpacing.sm),
                  CoachakQuestCard(
                    title: 'Form check session',
                    subtitle: formQuestSubtitle,
                    xpReward: 40,
                    icon: Icons.videocam_outlined,
                    completed: false,
                    onTap: () async {
                      await context.push('/workout-cv');
                      _load();
                    },
                  ),
                  const SizedBox(height: CoachakSpacing.lg),
                  CoachakSectionHeader(title: 'Quick actions'),
                  _QuickActionRow(
                    actions: [
                      _QuickAction(Icons.chat_bubble_outline, 'Ask coach', () => context.go('/coach')),
                      _QuickAction(Icons.calendar_today_outlined, 'View plans', () => context.go('/plans')),
                      _QuickAction(Icons.notifications_outlined, 'Reminders', () => context.push('/reminders')),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _DailyMacrosDashboardCard extends StatelessWidget {
  const _DailyMacrosDashboardCard({
    required this.todayMacros,
    required this.targetMacros,
  });

  final Map<String, dynamic> todayMacros;
  final Map<String, dynamic> targetMacros;

  double _numVal(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final calConsumed = _numVal(todayMacros['calories']);
    final calTargetRaw = _numVal(targetMacros['calories']);
    final calTarget = calTargetRaw > 0 ? calTargetRaw : 2000.0;

    final pConsumed = _numVal(todayMacros['protein_g']);
    final pTargetRaw = _numVal(targetMacros['protein_g']);
    final pTarget = pTargetRaw > 0 ? pTargetRaw : 150.0;

    final cConsumed = _numVal(todayMacros['carbs_g']);
    final cTargetRaw = _numVal(targetMacros['carbs_g']);
    final cTarget = cTargetRaw > 0 ? cTargetRaw : 220.0;

    final fConsumed = _numVal(todayMacros['fat_g']);
    final fTargetRaw = _numVal(targetMacros['fat_g']);
    final fTarget = fTargetRaw > 0 ? fTargetRaw : 65.0;

    final calRemaining = (calTarget - calConsumed).clamp(0.0, double.infinity);
    final calProgress = (calConsumed / calTarget).clamp(0.0, 1.0);

    final pProgress = (pConsumed / pTarget).clamp(0.0, 1.0);
    final cProgress = (cConsumed / cTarget).clamp(0.0, 1.0);
    final fProgress = (fConsumed / fTarget).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline, color: Colors.orangeAccent),
                const SizedBox(width: CoachakSpacing.sm),
                Text('Daily Nutrition Dashboard', style: CoachakTypography.sectionTitle(context)),
              ],
            ),
            const SizedBox(height: CoachakSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Calories Still Needed Today', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('${calRemaining.toStringAsFixed(0)} kcal remaining', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                Text('${calConsumed.toStringAsFixed(0)} / ${calTarget.toStringAsFixed(0)} kcal', style: CoachakTypography.bodyMuted(context)),
              ],
            ),
            const SizedBox(height: 8),
            CoachakProgressBar(
              value: calProgress,
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: CoachakSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _MacroStatItem(
                    label: 'Protein',
                    consumed: pConsumed,
                    target: pTarget,
                    progress: pProgress,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroStatItem(
                    label: 'Carbs',
                    consumed: cConsumed,
                    target: cTarget,
                    progress: cProgress,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MacroStatItem(
                    label: 'Fat',
                    consumed: fConsumed,
                    target: fTarget,
                    progress: fProgress,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroStatItem extends StatelessWidget {
  const _MacroStatItem({
    required this.label,
    required this.consumed,
    required this.target,
    required this.progress,
    required this.color,
  });

  final String label;
  final double consumed;
  final double target;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final remaining = (target - consumed).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(CoachakSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CoachakRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text('${consumed.toStringAsFixed(0)}g', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(remaining > 0 ? '${remaining.toStringAsFixed(0)}g needed' : 'Goal met!', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.name, required this.streak});
  final String name;
  final int streak;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_greeting, $name', style: CoachakTypography.display(context)),
          const SizedBox(height: CoachakSpacing.xs),
          Text(
            streak > 0
                ? 'You\'re on a $streak-day streak — keep the momentum!'
                : 'Start a streak today with any workout or habit.',
            style: CoachakTypography.bodyMuted(context),
          ),
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CoachakColors.streak.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CoachakRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, color: CoachakColors.streak, size: 18),
          const SizedBox(width: 4),
          Text('$days', style: TextStyle(color: CoachakColors.streak, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _QuickAction {
  _QuickAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _UpgradeBanner extends StatelessWidget {
  const _UpgradeBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CoachakColors.xp.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoachakRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(CoachakSpacing.md),
          child: Row(
            children: [
              Icon(Icons.workspace_premium, color: CoachakColors.xp),
              const SizedBox(width: CoachakSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upgrade to Coach Pro', style: CoachakTypography.sectionTitle(context)),
                    Text(
                      '599 EGP/mo · 7-day free trial · unlimited AI coach',
                      style: CoachakTypography.bodyMuted(context),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({required this.actions});
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: actions.map((a) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: a == actions.last ? 0 : CoachakSpacing.sm),
            child: Card(
              child: InkWell(
                onTap: a.onTap,
                borderRadius: BorderRadius.circular(CoachakRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: CoachakSpacing.lg),
                  child: Column(
                    children: [
                      Icon(a.icon, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: CoachakSpacing.sm),
                      Text(a.label, style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
