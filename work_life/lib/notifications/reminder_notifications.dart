import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../workspace/workspace_repository.dart';
import 'notification_driver.dart';
import 'quiet_hours.dart';

String reminderDeliveryLabel(String status) => switch (status) {
  'scheduled' => 'Scheduled on this device',
  'blocked' => 'Notifications blocked · kept in Today',
  'unsupported' => 'In-app reminder only on this platform',
  'elapsed' => 'Time passed · delivery not confirmed',
  'deferred' => 'Waiting for a device scheduling slot',
  'failed' => 'Device scheduling failed · retry from Today',
  _ => 'Waiting for device scheduling',
};

/// One coordinator owns the app-wide OS notification queue. Generations and a
/// serial queue prevent a previous account's in-flight work from winning a race.
class ReminderNotifications extends ChangeNotifier {
  ReminderNotifications(this.driver, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final NotificationDriver driver;
  final DateTime Function() now;
  static const horizon = 60;
  Future<void> _tail = Future.value();
  int _generation = 0;
  String? _scope;
  bool _reset = false;
  String message = 'Checking device notifications…';
  NotificationPermission? permission;
  bool working = false;

  Future<void> get idle => _tail;

  int attach(String scope) {
    _generation++;
    _reset = _reset || (_scope != null && scope != _scope);
    _scope = scope;
    message = 'Checking device notifications…';
    return _generation;
  }

  void detach(int generation) {
    if (generation != _generation) return;
    _generation++;
    _scope = null;
    _reset = true;
    // Run after any in-flight schedules so sign-out cannot leave old alerts.
    _enqueue(() async {
      if (_scope == null) await driver.cancelAll();
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {
      message = 'Couldn’t update device notifications. Reminders remain in Today. Retry.';
      notifyListeners();
    });
    return _tail;
  }

  /// Unlike normal reconciliation, reset errors must reach the caller. Keep
  /// cancellation and the SQL transaction on the same queue as all schedules.
  Future<void> deleteLocalData(int generation, WorkspaceRepository repository) {
    final operation = _tail.then((_) async {
      if (generation != _generation) {
        throw StateError('Workspace changed before deletion');
      }
      await driver.cancelAll();
      if (generation != _generation) {
        throw StateError('Workspace changed during cancellation');
      }
      await repository.clearLocalData();
    });
    // Keep the queue usable without hiding this operation's failure.
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> reconcile(
    int generation,
    WorkspaceRepository repository, {
    bool requestPermission = false,
  }) => _enqueue(() async {
    if (generation != _generation) return;
    working = true;
    notifyListeners();
    try {
      if (_reset) {
        await driver.cancelAll();
        if (generation != _generation) return;
        _reset = false;
      }
      permission = await driver.permission(request: requestPermission);
      if (generation != _generation) return;
      final data = await repository.readWorkspace();
      final activeIds = data.tasks
          .where((t) => t.active)
          .map((t) => t.id)
          .toSet();
      final reminders =
          data.reminders.where((r) => activeIds.contains(r.taskId)).toList()
            ..sort((a, b) {
              final time = effectiveReminderTime(a.scheduledAt, data.quietHours)
                  .compareTo(
                    effectiveReminderTime(b.scheduledAt, data.quietHours),
                  );
              return time == 0 ? a.id.compareTo(b.id) : time;
            });
      final future = reminders
          .where(
            (r) => effectiveReminderTime(
              r.scheduledAt,
              data.quietHours,
            ).isAfter(now()),
          )
          .take(horizon)
          .toList();
      final wanted = <int, String>{};
      final ids = <String, int>{};
      if (permission == NotificationPermission.allowed) {
        for (final reminder in reminders.where(
          (r) =>
              !effectiveReminderTime(
                r.scheduledAt,
                data.quietHours,
              ).isAfter(now()) ||
              future.any((f) => f.id == r.id),
        )) {
          // Stable IDs also let a changed/removed reminder cancel an alert that
          // has already been delivered. Detect collisions instead of replacing
          // a different task's notification.
          final key = jsonEncode([_scope, reminder.id]);
          final bytes = sha256.convert(utf8.encode(key)).bytes;
          final id =
              ((bytes[0] << 24) |
                  (bytes[1] << 16) |
                  (bytes[2] << 8) |
                  bytes[3]) &
              0x7fffffff;
          if (wanted.containsKey(id)) continue;
          ids[reminder.id] = id;
          wanted[id] = jsonEncode([
            _scope,
            reminder.id,
            effectiveReminderTime(
              reminder.scheduledAt,
              data.quietHours,
            ).toIso8601String(),
          ]);
        }
      }
      final pending = await driver.pending();
      if (generation != _generation) return;
      final existing = {for (final alert in pending) alert.id: alert.payload};
      for (final id in await driver.activeIds()) {
        if (!wanted.containsKey(id) || future.any((r) => ids[r.id] == id)) {
          await driver.cancel(id);
          existing.remove(id);
        }
        if (generation != _generation) return;
      }
      for (final alert in pending) {
        if (wanted[alert.id] != alert.payload ||
            !wanted.containsKey(alert.id)) {
          await driver.cancel(alert.id);
          if (generation != _generation) return;
          existing.remove(alert.id);
        }
      }
      var failed = false;
      for (final reminder in reminders) {
        if (generation != _generation) return;
        final effective = effectiveReminderTime(
          reminder.scheduledAt,
          data.quietHours,
        );
        String status;
        if (!effective.isAfter(now())) {
          status = 'elapsed';
        } else if (permission != NotificationPermission.allowed) {
          status = permission == NotificationPermission.unsupported
              ? 'unsupported'
              : 'blocked';
        } else if (!future.any((r) => r.id == reminder.id)) {
          status = 'deferred';
        } else {
          final id = ids[reminder.id];
          try {
            if (id == null) throw StateError('Notification ID collision');
            if (existing[id] != wanted[id]) {
              await driver.schedule(id, effective, wanted[id]!);
            }
            status = 'scheduled';
          } catch (_) {
            status = 'failed';
            failed = true;
          }
        }
        if (generation != _generation) return;
        if (reminder.deliveryStatus != status) {
          await repository.recordReminderDelivery(reminder, status);
        }
      }
      message = failed
          ? 'Some reminders could not be scheduled. Retry; they remain in Today.'
          : switch (permission) {
              NotificationPermission.allowed =>
                future.length <
                        reminders
                            .where((r) => r.scheduledAt.isAfter(now()))
                            .length
                    ? 'Device notifications enabled. Some later reminders are waiting; open the app to refresh. Your device may delay alerts.'
                    : 'Device notifications enabled. Your device may delay alerts.',
              NotificationPermission.blocked => 'Device notifications are off. Enable permission or change system settings; reminders remain in Today.',
              _ => 'Device notifications are supported on Android and iPhone. Reminders remain in Today.',
            };
    } finally {
      working = false;
      notifyListeners();
    }
  });

  Future<void> openSettings() => _enqueue(() async {
    if (!await driver.openSettings()) {
      message = 'Couldn’t open notification settings. Open this app’s notification settings on your device.';
      notifyListeners();
    }
  });
}
