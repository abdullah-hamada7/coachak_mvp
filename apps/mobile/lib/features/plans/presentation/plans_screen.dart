import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../../../services/api/api_client.dart';
import '../../../services/api/api_errors.dart';
import '../../../services/subscription/subscription_provider.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../../services/notifications/notification_service.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _workoutPlan;
  Map<String, dynamic>? _nutritionPlan;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final workout = await api.getActiveWorkoutPlan();
      final nutrition = await api.getActiveNutritionPlan();
      setState(() {
        _workoutPlan = workout;
        _nutritionPlan = nutrition;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _regenerateWorkout() async {
    try {
      final api = ref.read(apiClientProvider);
      final plan = await api.generateWorkoutPlan();
      setState(() => _workoutPlan = plan);
      ref.invalidate(subscriptionProvider);
    } on DioException catch (e) {
      if (e.response?.statusCode == 402 && mounted) {
        await showSubscriptionLimitPrompt(context, ref, SubscriptionLimitException.fromDio(e));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _regenerateNutrition() async {
    try {
      final api = ref.read(apiClientProvider);
      final plan = await api.generateNutritionPlan();
      setState(() => _nutritionPlan = plan);
      ref.invalidate(subscriptionProvider);
    } on DioException catch (e) {
      if (e.response?.statusCode == 402 && mounted) {
        await showSubscriptionLimitPrompt(context, ref, SubscriptionLimitException.fromDio(e));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _completeSession(String label) async {
    final api = ref.read(apiClientProvider);
    final result = await api.logWorkout({'session_label': label});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workout logged! +50 XP')));
      final badges = (result['new_badges'] as List?) ?? [];
      if (badges.isNotEmpty) {
        await ref.read(notificationServiceProvider).showInstantReward(
              title: 'New badge unlocked!',
              body: 'You earned a new achievement. Tap to see it in Progress.',
            );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Plans'),
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: 'Workout'), Tab(text: 'Nutrition')]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWorkoutTab(),
                _buildNutritionTab(),
              ],
            ),
    );
  }

  Widget _buildWorkoutTab() {
    if (_workoutPlan == null) {
      return Center(
        child: FilledButton(onPressed: _regenerateWorkout, child: const Text('Generate Workout Plan')),
      );
    }

    final plan = _workoutPlan!['plan'] as Map<String, dynamic>? ?? {};
    final sessions = (plan['sessions'] as List?) ?? [];
    final weeks = <int, List<Map<String, dynamic>>>{};
    for (final raw in sessions) {
      final session = Map<String, dynamic>.from(raw as Map);
      final week = (session['week_number'] as num?)?.toInt() ?? 1;
      weeks.putIfAbsent(week, () => []).add(session);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(plan['title']?.toString() ?? 'Workout Plan', style: Theme.of(context).textTheme.titleLarge),
          if (plan['progression_notes'] != null) Text(plan['progression_notes'].toString()),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _regenerateWorkout, child: const Text('Regenerate')),
          const SizedBox(height: 16),
          for (final week in weeks.keys.toList()..sort()) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text('Week $week', style: Theme.of(context).textTheme.titleMedium),
            ),
            ...weeks[week]!.map(_buildWorkoutSessionCard),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutSessionCard(Map<String, dynamic> session) {
    final exercises = (session['exercises'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text('${session['day_label']} — ${session['focus']}'),
        subtitle: Text('${session['estimated_minutes'] ?? 45} min • ${exercises.length} exercises'),
        children: [
          ...exercises.map((e) => _ExerciseDetailsTile(exercise: Map<String, dynamic>.from(e as Map))),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.tonal(
              onPressed: () => _completeSession('${session['day_label']} — ${session['focus']}'),
              child: const Text('Mark Complete'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionTab() {
    if (_nutritionPlan == null) {
      return Center(
        child: FilledButton(onPressed: _regenerateNutrition, child: const Text('Generate Nutrition Plan')),
      );
    }

    final plan = _nutritionPlan!['plan'] as Map<String, dynamic>? ?? {};
    final macros = plan['target_macros'] as Map<String, dynamic>? ?? {};
    final dailyPlans = (plan['daily_plans'] as List?) ?? [];
    final suggestions = plan['food_suggestions'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(plan['title']?.toString() ?? 'Nutrition Plan', style: Theme.of(context).textTheme.titleLarge),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily Targets', style: Theme.of(context).textTheme.titleMedium),
                Text('Calories: ${macros['calories']}'),
                Text('Protein: ${macros['protein_g']}g | Carbs: ${macros['carbs_g']}g | Fat: ${macros['fat_g']}g'),
                Text('Hydration: ${plan['hydration_liters'] ?? 2.5}L'),
              ],
            ),
          ),
        ),
        OutlinedButton(onPressed: _regenerateNutrition, child: const Text('Regenerate')),
        const SizedBox(height: 16),
        if (suggestions.isNotEmpty) _MacroFoodSuggestionsCard(suggestions: suggestions),
        const SizedBox(height: 16),
        Text('7-day plan', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...dailyPlans.map((d) => _NutritionDayCard(day: Map<String, dynamic>.from(d as Map))),
      ],
    );
  }
}

class _ExerciseDetailsTile extends StatelessWidget {
  const _ExerciseDetailsTile({required this.exercise});

  final Map<String, dynamic> exercise;

  @override
  Widget build(BuildContext context) {
    final sets = (exercise['sets'] as List?) ?? [];
    final muscles = (exercise['muscle_groups'] as List?)?.join(', ') ?? '';
    final videoUrl = exercise['video_url']?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card.outlined(
        child: ExpansionTile(
          title: Text(exercise['name']?.toString() ?? 'Exercise'),
          subtitle: Text([
            if (sets.isNotEmpty) '${sets.length} sets',
            if (muscles.isNotEmpty) muscles,
          ].join(' • ')),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            if (sets.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Sets & reps', style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 6),
              ...sets.asMap().entries.map((entry) {
                final set = Map<String, dynamic>.from(entry.value as Map);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Set ${entry.key + 1}: ${set['reps'] ?? '?'} reps'
                    '${set['rpe'] != null ? ' @ RPE ${set['rpe']}' : ''}',
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
            if ((exercise['description']?.toString() ?? '').isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Description', style: Theme.of(context).textTheme.labelLarge),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(exercise['description'].toString()),
              ),
              const SizedBox(height: 10),
            ],
            if ((exercise['mechanism']?.toString() ?? '').isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Mechanism / form cues', style: Theme.of(context).textTheme.labelLarge),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(exercise['mechanism'].toString()),
              ),
              const SizedBox(height: 10),
            ],
            if (videoUrl != null && videoUrl.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final uri = Uri.tryParse(videoUrl);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Watch mechanism video'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MacroFoodSuggestionsCard extends StatelessWidget {
  const _MacroFoodSuggestionsCard({required this.suggestions});

  final Map<String, dynamic> suggestions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Food suggestions by macro', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...suggestions.entries.map((entry) {
              final value = Map<String, dynamic>.from(entry.value as Map);
              final foods = (value['foods'] as List?)?.map((f) => f.toString()).join(', ') ?? '';
              final target = value['target_g'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${entry.key.toUpperCase()}${target != null ? ' ($target g target)' : ''}: $foods'),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _NutritionDayCard extends StatelessWidget {
  const _NutritionDayCard({required this.day});

  final Map<String, dynamic> day;

  @override
  Widget build(BuildContext context) {
    final meals = (day['meals'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(day['day_label']?.toString() ?? 'Day'),
        subtitle: Text('${meals.length} meals'),
        children: [
          ...meals.map((rawMeal) {
            final meal = Map<String, dynamic>.from(rawMeal as Map);
            final items = (meal['items'] as List?) ?? [];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Card.outlined(
                child: ExpansionTile(
                  title: Text(meal['meal_type']?.toString() ?? 'Meal'),
                  subtitle: Text(
                    '${meal['total_calories'] ?? 0} cal'
                    ' • P ${meal['total_protein_g'] ?? '-'}g'
                    ' • C ${meal['total_carbs_g'] ?? '-'}g'
                    ' • F ${meal['total_fat_g'] ?? '-'}g',
                  ),
                  children: [
                    ...items.map((rawItem) {
                      final item = Map<String, dynamic>.from(rawItem as Map);
                      return ListTile(
                        dense: true,
                        title: Text(item['name']?.toString() ?? ''),
                        subtitle: Text(
                          '${item['portion'] ?? ''} • ${item['calories'] ?? 0} cal'
                          ' • P ${item['protein_g'] ?? 0}g'
                          ' • C ${item['carbs_g'] ?? 0}g'
                          ' • F ${item['fat_g'] ?? 0}g',
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
