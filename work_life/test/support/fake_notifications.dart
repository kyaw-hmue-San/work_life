import 'dart:async';

import 'package:work_life/notifications/notification_driver.dart';

class FakeNotifications implements NotificationDriver {
  NotificationPermission state = NotificationPermission.allowed;
  bool failSchedule = false, failCancel = false;
  int permissionRequests = 0, schedules = 0, resets = 0;
  final alerts = <int, PendingAlert>{};
  final scheduledTimes = <int, DateTime>{};
  final active = <int>{};
  Completer<void>? scheduleGate;
  final scheduleStarted = Completer<void>();

  @override
  Future<NotificationPermission> permission({bool request = false}) async {
    if (request) permissionRequests++;
    return state;
  }

  @override
  Future<List<PendingAlert>> pending() async => alerts.values.toList();

  @override
  Future<List<int>> activeIds() async => active.toList();

  @override
  Future<void> schedule(int id, DateTime instant, String payload) async {
    schedules++;
    if (!scheduleStarted.isCompleted) scheduleStarted.complete();
    await scheduleGate?.future;
    if (failSchedule) throw StateError('Scheduling failed');
    alerts[id] = PendingAlert(id, payload);
    scheduledTimes[id] = instant;
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw StateError('Cancellation failed');
    alerts.remove(id);
    active.remove(id);
    scheduledTimes.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    if (failCancel) throw StateError('Cancellation failed');
    resets++;
    alerts.clear();
    active.clear();
    scheduledTimes.clear();
  }

  @override
  Future<bool> openSettings() async => true;
}
