import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../services/notifications/notification_service.dart';

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool _permissionsGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final notifications = ref.read(notificationServiceProvider);
    final granted = await notifications.requestPermissions();
    if (mounted) {
      setState(() {
        _permissionsGranted = granted;
        _checking = false;
      });
      if (granted) {
        final config = ref.read(reminderConfigProvider);
        await notifications.rescheduleAll(config);
      }
    }
  }

  Future<void> _updateConfig(ReminderConfig newConfig) async {
    final notifications = ref.read(notificationServiceProvider);
    await ref.read(reminderConfigProvider.notifier).update(newConfig, notifications);
  }

  Future<void> _pickTime({
    required String title,
    required int currentHour,
    required int currentMinute,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      helpText: title,
      initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(reminderConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_permissionsGranted
              ? _PermissionsPrompt(onRetry: _checkPermissions)
              : ListView(
                  padding: const EdgeInsets.all(CoachakSpacing.md),
                  children: [
                    Text(
                      'Stay consistent with gentle nudges. You can disable any reminder anytime.',
                      style: CoachakTypography.bodyMuted(context),
                    ),
                    const SizedBox(height: CoachakSpacing.lg),
                    _ReminderSection(
                      icon: Icons.fitness_center,
                      title: 'Workout reminder',
                      subtitle: config.workoutEnabled
                          ? 'Daily at ${_formatTime(config.workoutHour, config.workoutMinute)}'
                          : 'Off',
                      enabled: config.workoutEnabled,
                      onToggle: (v) => _updateConfig(config.copyWith(workoutEnabled: v)),
                      onTimeTap: config.workoutEnabled
                          ? () => _pickTime(
                                title: 'Workout reminder time',
                                currentHour: config.workoutHour,
                                currentMinute: config.workoutMinute,
                                onPicked: (t) => _updateConfig(config.copyWith(
                                  workoutHour: t.hour,
                                  workoutMinute: t.minute,
                                )),
                              )
                          : null,
                    ),
                    const SizedBox(height: CoachakSpacing.sm),
                    _ReminderSection(
                      icon: Icons.check_circle_outline,
                      title: 'Habit check-in',
                      subtitle: config.habitEnabled
                          ? 'Daily at ${_formatTime(config.habitHour, config.habitMinute)}'
                          : 'Off',
                      enabled: config.habitEnabled,
                      onToggle: (v) => _updateConfig(config.copyWith(habitEnabled: v)),
                      onTimeTap: config.habitEnabled
                          ? () => _pickTime(
                                title: 'Habit reminder time',
                                currentHour: config.habitHour,
                                currentMinute: config.habitMinute,
                                onPicked: (t) => _updateConfig(config.copyWith(
                                  habitHour: t.hour,
                                  habitMinute: t.minute,
                                )),
                              )
                          : null,
                    ),
                    const SizedBox(height: CoachakSpacing.sm),
                    _ReminderSection(
                      icon: Icons.local_fire_department,
                      title: 'Streak saver',
                      subtitle: config.streakReminderEnabled ? 'Daily at 21:00' : 'Off',
                      enabled: config.streakReminderEnabled,
                      onToggle: (v) => _updateConfig(config.copyWith(streakReminderEnabled: v)),
                      onTimeTap: null,
                    ),
                    const SizedBox(height: CoachakSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await ref.read(notificationServiceProvider).showInstantReward(
                                title: 'Test notification',
                                body: 'Reminders are working! You\'ll get your daily nudges automatically.',
                              );
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Test notification sent')),
                            );
                          }
                        },
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('Send test notification'),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _formatTime(int hour, int minute) {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PermissionsPrompt extends StatelessWidget {
  const _PermissionsPrompt({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CoachakSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_off, size: 56, color: Colors.grey),
            const SizedBox(height: CoachakSpacing.md),
            Text('Notifications are off', style: CoachakTypography.display(context)),
            const SizedBox(height: CoachakSpacing.sm),
            const Text(
              'Coachak needs notification permission to send workout and habit reminders.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CoachakSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Enable notifications')),
          ],
        ),
      ),
    );
  }
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onToggle,
    this.onTimeTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTimeTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle),
            value: enabled,
            onChanged: onToggle,
          ),
          if (enabled && onTimeTap != null)
            ListTile(
              leading: const Icon(Icons.schedule, size: 20),
              title: const Text('Change time'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTimeTap,
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
            ),
        ],
      ),
    );
  }
}
