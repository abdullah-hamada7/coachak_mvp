import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/json_utils.dart';
import '../../../services/api/api_client.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../shared/widgets/coachak_components.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _gamification;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final progress = await api.getProgressSummary();
      final gamification = await api.getGamificationState();
      setState(() {
        _progress = progress;
        _gamification = gamification;
      });
    } catch (_) {
      setState(() => _error = 'Could not load progress. Pull to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addHabit() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('New daily habit'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'e.g. Drink 3L water',
              labelText: 'Habit name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Add')),
          ],
        );
      },
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(apiClientProvider).createHabit(name);
      _load();
    }
  }

  Future<void> _checkHabit(String id) async {
    final result = await ref.read(apiClientProvider).checkHabit(id);
    final streak = result['streak'] ?? 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Habit checked! +10 XP • $streak day streak')),
      );
      // Fire a small reward notification when milestones hit.
      if (streak == 7 || streak == 30 || streak == 100) {
        await ref.read(notificationServiceProvider).showInstantReward(
              title: '${streak}-day habit streak!',
              body: 'Consistency is paying off. Keep showing up — you\'re building something real.',
            );
      }
    }
    _load();
  }

  int _xpInLevel(int xp) => xp % 200;

  @override
  Widget build(BuildContext context) {
    final badges = (_gamification?['badges'] as List?) ?? [];
    final habits = (_gamification?['habits'] as List?) ?? [];
    final xp = jsonInt(_progress?['xp'] ?? _gamification?['total_xp']);
    final level = jsonInt(_progress?['level'] ?? _gamification?['level'], 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Reminders',
            onPressed: () => context.push('/reminders'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHabit,
        icon: const Icon(Icons.add),
        label: const Text('Add habit'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? CoachakEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Offline?',
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(CoachakSpacing.md),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(CoachakSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your journey', style: CoachakTypography.sectionTitle(context)),
                              const SizedBox(height: CoachakSpacing.md),
                              CoachakProgressBar(
                                value: _xpInLevel(xp) / 200,
                                label: 'Level $level • ${_xpInLevel(xp)} / 200 XP',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: CoachakSpacing.md),
                      CoachakStatTile(
                        icon: Icons.fitness_center,
                        label: 'Workouts completed',
                        value: '${_progress?['workouts_completed'] ?? 0}',
                      ),
                      const SizedBox(height: CoachakSpacing.sm),
                      CoachakStatTile(
                        icon: Icons.repeat,
                        label: 'Reps tracked',
                        value: '${_progress?['total_reps_tracked'] ?? 0}',
                        color: CoachakColors.accent,
                      ),
                      const SizedBox(height: CoachakSpacing.sm),
                      CoachakStatTile(
                        icon: Icons.local_fire_department,
                        label: 'Workout streak',
                        value: '${_gamification?['workout_streak'] ?? 0} days',
                        color: CoachakColors.streak,
                      ),
                      const SizedBox(height: CoachakSpacing.lg),
                      CoachakSectionHeader(title: 'Badges'),
                      if (badges.isEmpty)
                        CoachakEmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'No badges yet',
                          message: 'Complete workouts and form sessions to unlock your first badge.',
                        )
                      else
                        Wrap(
                          spacing: CoachakSpacing.sm,
                          runSpacing: CoachakSpacing.sm,
                          children: badges.map((b) {
                            final badge = b as Map<String, dynamic>;
                            return _BadgeChip(
                              name: badge['name']?.toString() ?? '',
                              description: badge['description']?.toString() ?? '',
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: CoachakSpacing.lg),
                      CoachakSectionHeader(title: 'Daily habits'),
                      if (habits.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: CoachakSpacing.md),
                          child: Text(
                            'Small daily habits compound into big results. Tap + to add one.',
                            style: CoachakTypography.bodyMuted(context),
                          ),
                        )
                      else
                        ...habits.map((h) {
                          final habit = h as Map<String, dynamic>;
                          final checked = habit['checked_today'] == true;
                          return Card(
                            margin: const EdgeInsets.only(bottom: CoachakSpacing.sm),
                            child: CheckboxListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(habit['name']?.toString() ?? ''),
                              subtitle: Text('${habit['streak'] ?? 0} day streak'),
                              value: checked,
                              onChanged: checked ? null : (_) => _checkHabit(habit['id'].toString()),
                            ),
                          );
                        }),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: description,
      child: Semantics(
        label: 'Badge: $name. $description',
        child: Chip(
          avatar: const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
          label: Text(name),
        ),
      ),
    );
  }
}
