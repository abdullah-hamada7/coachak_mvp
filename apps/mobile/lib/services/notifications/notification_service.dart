import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

/// Reminder configuration stored locally.
class ReminderConfig {
  ReminderConfig({
    this.workoutEnabled = true,
    this.workoutHour = 9,
    this.workoutMinute = 0,
    this.habitEnabled = true,
    this.habitHour = 19,
    this.habitMinute = 0,
    this.streakReminderEnabled = true,
  });

  final bool workoutEnabled;
  final int workoutHour;
  final int workoutMinute;
  final bool habitEnabled;
  final int habitHour;
  final int habitMinute;
  final bool streakReminderEnabled;

  Map<String, dynamic> toJson() => {
        'workout_enabled': workoutEnabled,
        'workout_hour': workoutHour,
        'workout_minute': workoutMinute,
        'habit_enabled': habitEnabled,
        'habit_hour': habitHour,
        'habit_minute': habitMinute,
        'streak_reminder_enabled': streakReminderEnabled,
      };

  factory ReminderConfig.fromJson(Map<dynamic, dynamic> json) => ReminderConfig(
        workoutEnabled: json['workout_enabled'] as bool? ?? true,
        workoutHour: json['workout_hour'] as int? ?? 9,
        workoutMinute: json['workout_minute'] as int? ?? 0,
        habitEnabled: json['habit_enabled'] as bool? ?? true,
        habitHour: json['habit_hour'] as int? ?? 19,
        habitMinute: json['habit_minute'] as int? ?? 0,
        streakReminderEnabled: json['streak_reminder_enabled'] as bool? ?? true,
      );

  ReminderConfig copyWith({
    bool? workoutEnabled,
    int? workoutHour,
    int? workoutMinute,
    bool? habitEnabled,
    int? habitHour,
    int? habitMinute,
    bool? streakReminderEnabled,
  }) =>
      ReminderConfig(
        workoutEnabled: workoutEnabled ?? this.workoutEnabled,
        workoutHour: workoutHour ?? this.workoutHour,
        workoutMinute: workoutMinute ?? this.workoutMinute,
        habitEnabled: habitEnabled ?? this.habitEnabled,
        habitHour: habitHour ?? this.habitHour,
        habitMinute: habitMinute ?? this.habitMinute,
        streakReminderEnabled: streakReminderEnabled ?? this.streakReminderEnabled,
      );
}

final reminderConfigProvider = StateNotifierProvider<ReminderConfigNotifier, ReminderConfig>(
  (ref) => ReminderConfigNotifier(),
);

class ReminderConfigNotifier extends StateNotifier<ReminderConfig> {
  static const _key = 'reminder_config';
  static const _boxName = 'coachak';

  ReminderConfigNotifier() : super(ReminderConfig()) {
    _load();
  }

  void _load() {
    try {
      final box = Hive.box(_boxName);
      final raw = box.get(_key);
      if (raw != null) {
        state = ReminderConfig.fromJson(raw as Map);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final box = Hive.box(_boxName);
      await box.put(_key, state.toJson());
    } catch (_) {}
  }

  Future<void> update(ReminderConfig config, NotificationService notifications) async {
    state = config;
    await _persist();
    await notifications.rescheduleAll(config);
  }
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _workoutId = 1001;
  static const _habitId = 1002;
  static const _streakId = 1003;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    final local = tz.local;
    debugPrint('Notification timezone: $local');

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('Notification tapped: ${resp.payload}');
      },
    );
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  Future<void> rescheduleAll(ReminderConfig config) async {
    await cancelAll();

    if (config.workoutEnabled) {
      await _scheduleDaily(
        id: _workoutId,
        hour: config.workoutHour,
        minute: config.workoutMinute,
        title: 'Time to train',
        body: 'Your workout is waiting. Open Coachak and keep the streak alive!',
        payload: 'workout',
      );
    }

    if (config.habitEnabled) {
      await _scheduleDaily(
        id: _habitId,
        hour: config.habitHour,
        minute: config.habitMinute,
        title: 'Daily habits check-in',
        body: 'Tap to check off today\'s habits — small wins compound.',
        payload: 'habit',
      );
    }

    if (config.streakReminderEnabled) {
      await _scheduleDaily(
        id: _streakId,
        hour: 21,
        minute: 0,
        title: 'Don\'t break the streak',
        body: 'One workout today keeps your streak going. You\'ve got this.',
        payload: 'streak',
      );
    }
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'coachak_reminders_v2',
          'Coachak reminders',
          channelDescription: 'Workout, habit, and streak reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
    debugPrint('Scheduled notification $id for $hour:$minute (next at $scheduled)');
  }

  Future<void> showInstantReward({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'coachak_rewards_v2',
          'Coachak rewards',
          channelDescription: 'XP and badge notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancel(_workoutId);
    await _plugin.cancel(_habitId);
    await _plugin.cancel(_streakId);
  }
}
