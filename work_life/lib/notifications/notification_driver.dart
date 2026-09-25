import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

enum NotificationPermission { allowed, blocked, unsupported }

class PendingAlert {
  const PendingAlert(this.id, this.payload);
  final int id;
  final String? payload;
}

abstract interface class NotificationDriver {
  Future<NotificationPermission> permission({bool request = false});
  Future<List<PendingAlert>> pending();
  Future<List<int>> activeIds();
  Future<void> schedule(int id, DateTime instant, String payload);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<bool> openSettings();
}

class LocalNotificationDriver implements NotificationDriver {
  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _initialize() async {
    if (_ready || !supported) return;
    final initialized = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      // Opening or dismissing an alert never mutates a task. The pending list
      // remains available in Today; no background task actions are registered.
    );
    if (initialized != true) {
      throw StateError('Notifications could not initialize');
    }
    _ready = true;
  }

  @override
  Future<NotificationPermission> permission({bool request = false}) async {
    if (!supported) return NotificationPermission.unsupported;
    await _initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      if (request) await android.requestNotificationsPermission();
      final channels = await android.getNotificationChannels();
      if (channels?.any(
            (channel) =>
                channel.id == 'task_reminders' &&
                channel.importance == Importance.none,
          ) ==
          true) {
        return NotificationPermission.blocked;
      }
      return await android.areNotificationsEnabled() == true
          ? NotificationPermission.allowed
          : NotificationPermission.blocked;
    }
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()!;
    if (request) {
      await ios.requestPermissions(alert: true, sound: true, badge: false);
    }
    final status = await ios.checkPermissions();
    return status?.isEnabled == true
        ? NotificationPermission.allowed
        : NotificationPermission.blocked;
  }

  @override
  Future<List<PendingAlert>> pending() async {
    if (!supported) return [];
    await _initialize();
    return (await plugin.pendingNotificationRequests())
        .map((r) => PendingAlert(r.id, r.payload))
        .toList();
  }

  @override
  Future<List<int>> activeIds() async {
    if (!supported) return [];
    await _initialize();
    return (await plugin.getActiveNotifications())
        .map((r) => r.id)
        .whereType<int>()
        .toList();
  }

  @override
  Future<void> schedule(int id, DateTime instant, String payload) async {
    await _initialize();
    // This slice preserves a confirmed instant through timezone changes.
    // UTC is built into timezone; no device-zone lookup or recurrence needed.
    await plugin.zonedSchedule(
      id: id,
      title: 'Time to revisit a task',
      body: 'Open Today to review your pending reminders.',
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task reminders',
          channelDescription: 'Reminders for tasks you choose',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!supported) return;
    await _initialize();
    await plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (!supported) return;
    await _initialize();
    await plugin.cancelAll();
  }

  @override
  Future<bool> openSettings() async {
    if (!supported) return false;
    await _initialize();
    return await plugin.openAppNotificationSettings() == true;
  }
}
