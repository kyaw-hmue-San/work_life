import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/notifications/notification_driver.dart';
import 'package:work_life/notifications/reminder_notifications.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_model.dart';

import 'support/fake_notifications.dart';
import 'support/memory_workspace.dart';

void main() {
  final now = DateTime.utc(2030, 1, 1);
  MemoryWorkspace workspace([String taskId = 'task']) {
    final repo = MemoryWorkspace();
    repo.tasks.add(Task(id: taskId, title: 'A personal task', area: 'Rest'));
    repo.reminders.add(
      TaskReminder(
        id: 'reminder-$taskId',
        taskId: taskId,
        scheduledAt: now.add(const Duration(hours: 1)),
      ),
    );
    return repo;
  }

  test('schedule is idempotent; reschedule replaces; removal cancels delivered alerts', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => now);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    expect(repo.reminders.single.deliveryStatus, 'scheduled');
    expect(driver.alerts, hasLength(1));
    final id = driver.alerts.keys.single;
    await service.reconcile(lease, repo);
    expect(driver.schedules, 1);
    await repo.saveReminder(
      TaskReminder(
        id: 'reminder-task',
        taskId: 'task',
        scheduledAt: now.add(const Duration(hours: 2)),
      ),
    );
    await service.reconcile(lease, repo);
    expect(driver.alerts.keys.single, id);
    expect(driver.schedules, 2);
    driver.alerts.clear();
    driver.active.add(id);
    await repo.removeReminder('task');
    await service.reconcile(lease, repo);
    expect(driver.active, isEmpty);
    expect(repo.tasks.single.status, TaskStatus.open);
  });

  test('blocked permission cancels OS reminders but retains intent; request is explicit', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => now);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    driver.state = NotificationPermission.blocked;
    await service.reconcile(lease, repo);
    expect(driver.alerts, isEmpty);
    expect(repo.reminders.single.deliveryStatus, 'blocked');
    expect(driver.permissionRequests, 0);
    driver.state = NotificationPermission.allowed;
    await service.reconcile(lease, repo, requestPermission: true);
    expect(driver.permissionRequests, 1);
    expect(driver.alerts, hasLength(1));
    expect(repo.tasks.single.status, TaskStatus.open);
  });

  test(
    'failure leaves saved intent and successful retry repairs scheduling',
    () async {
      final driver = FakeNotifications()..failSchedule = true;
      final service = ReminderNotifications(driver, now: () => now);
      final repo = workspace();
      final model = WorkspaceModel(repo, notifications: service);
      await model.load();
      expect(model.error, isNull);
      expect(model.data.reminders.single.deliveryStatus, 'failed');
      driver.failSchedule = false;
      await model.refreshNotifications();
      expect(model.data.reminders.single.deliveryStatus, 'scheduled');
      expect(driver.alerts, hasLength(1));
      await model.setStatus(repo.tasks.single, TaskStatus.completed);
      expect(driver.alerts, isEmpty);
      model.dispose();
      await service.idle;
    },
  );

  test('elapsed inexact alerts stay queued, but are never reissued after dismissal', () async {
    var clock = now;
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => clock);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    clock = now.add(const Duration(hours: 2));
    await service.reconcile(lease, repo);
    expect(
      driver.alerts,
      hasLength(1),
      reason: 'Android may still deliver an inexact alarm',
    );
    expect(repo.reminders.single.deliveryStatus, 'elapsed');
    driver.alerts.clear();
    final restarted = ReminderNotifications(driver, now: () => clock);
    await restarted.reconcile(restarted.attach('guest'), repo);
    expect(driver.schedules, 1);
    expect(repo.reminders, hasLength(1));
    expect(repo.tasks.single.status, TaskStatus.open);
  });

  test(
    'horizon keeps the nearest 60 and refills when a task completes',
    () async {
      final driver = FakeNotifications();
      final service = ReminderNotifications(driver, now: () => now);
      final repo = MemoryWorkspace();
      for (var i = 0; i < 62; i++) {
        repo.tasks.add(Task(id: 'task-$i', title: 'Task $i', area: 'Work'));
        repo.reminders.add(
          TaskReminder(
            id: 'r-$i',
            taskId: 'task-$i',
            scheduledAt: now.add(Duration(minutes: i + 1)),
          ),
        );
      }
      final lease = service.attach('guest');
      await service.reconcile(lease, repo);
      expect(driver.alerts, hasLength(60));
      expect(
        repo.reminders.where((r) => r.deliveryStatus == 'deferred'),
        hasLength(2),
      );
      await repo.saveTask(repo.tasks.first.withStatus(TaskStatus.completed));
      await service.reconcile(lease, repo);
      expect(driver.alerts, hasLength(60));
      expect(
        repo.reminders.where((r) => r.deliveryStatus == 'deferred'),
        hasLength(1),
      );
    },
  );

  test('account switch during scheduling drains old work before installing new alerts', () async {
    final driver = FakeNotifications()..scheduleGate = Completer<void>();
    final service = ReminderNotifications(driver, now: () => now);
    final a = workspace('a'), b = workspace('b');
    final leaseA = service.attach('account-a');
    final first = service.reconcile(leaseA, a);
    await driver.scheduleStarted.future;
    final leaseB = service.attach('account-b');
    service.detach(leaseA);
    final second = service.reconcile(leaseB, b);
    driver.scheduleGate!.complete();
    await Future.wait([first, second]);
    expect(driver.alerts, hasLength(1));
    expect(driver.alerts.values.single.payload, contains('account-b'));
    expect(a.reminders.single.deliveryStatus, 'pending');
    service.detach(leaseB);
    await service.idle;
    expect(driver.alerts, isEmpty);
  });

  test('cancellation failure blocks replacement until retry', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => now);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    final oldPayload = driver.alerts.values.single.payload;
    await repo.saveReminder(
      TaskReminder(
        id: 'reminder-task',
        taskId: 'task',
        scheduledAt: now.add(const Duration(hours: 3)),
      ),
    );
    driver.failCancel = true;
    await service.reconcile(lease, repo);
    expect(driver.alerts.values.single.payload, oldPayload);
    expect(service.message, contains('Couldn’t update'));
    driver.failCancel = false;
    await service.reconcile(lease, repo);
    expect(driver.alerts, hasLength(1));
    expect(driver.alerts.values.single.payload, isNot(oldPayload));
  });

  test('quiet hours reschedules inside reminders and changing settings is idempotent', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(
      driver,
      now: () => DateTime(2029, 12, 31).toUtc(),
    );
    final repo = MemoryWorkspace();
    final task = Task(id: 'quiet-task', title: 'Sleep', area: 'Rest');
    repo.tasks.add(task);
    final localReminder = DateTime(2030, 1, 1, 23, 30);
    repo.reminders.add(
      TaskReminder(
        id: 'quiet-reminder',
        taskId: task.id,
        scheduledAt: localReminder.toUtc(),
      ),
    );
    repo.quietHours = const QuietHours(
      enabled: true,
      startMinute: 23 * 60,
      endMinute: 7 * 60,
    );
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    expect(driver.scheduledTimes.values.single, DateTime(2030, 1, 2, 7).toUtc());
    expect(repo.reminders.single.scheduledAt, localReminder.toUtc());
    expect(driver.schedules, 1);

    repo.quietHours = const QuietHours();
    await service.reconcile(lease, repo);
    expect(driver.scheduledTimes.values.single, localReminder.toUtc());
    expect(driver.schedules, 2);
    await service.reconcile(lease, repo);
    expect(driver.schedules, 2);
  });

  test('default-generated reminders still pass through Quiet Hours', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(
      driver,
      now: () => DateTime(2029, 12, 31).toUtc(),
    );
    final repo = MemoryWorkspace()
      ..reminderDefault = ReminderDefault.atTime
      ..quietHours = const QuietHours(
        enabled: true,
        startMinute: 23 * 60,
        endMinute: 7 * 60,
      );
    final task = Task(id: 'default-quiet-task', title: 'Sleep', area: 'Rest');
    repo.tasks.add(task);
    final plan = PlanBlock(
      id: 'default-quiet-plan',
      title: task.title,
      taskId: task.id,
      start: DateTime(2030, 1, 1, 23, 30),
      minutes: 30,
      area: task.area,
    );
    await repo.savePlan(plan);
    expect(repo.reminders.single.origin, ReminderOrigin.defaulted);
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    expect(driver.scheduledTimes.values.single, DateTime(2030, 1, 2, 7).toUtc());
  });

  test('reconciliation cancels notifications after local data deletion', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => now);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    expect(driver.alerts, hasLength(1));
    await repo.clearLocalData();
    await service.reconcile(lease, repo);
    expect(driver.alerts, isEmpty);
    expect(driver.active, isEmpty);
  });

  test('repeated snooze replacement keeps one scheduled notification', () async {
    final driver = FakeNotifications();
    final service = ReminderNotifications(driver, now: () => now);
    final repo = workspace();
    final lease = service.attach('guest');
    await service.reconcile(lease, repo);
    final reminder = repo.reminders.single;
    await repo.saveReminder(
      TaskReminder(
        id: reminder.id,
        taskId: reminder.taskId,
        scheduledAt: now.add(const Duration(hours: 2)),
      ),
    );
    await service.reconcile(lease, repo);
    expect(driver.alerts, hasLength(1));
    expect(driver.schedules, 2);
    await repo.saveReminder(
      TaskReminder(
        id: reminder.id,
        taskId: reminder.taskId,
        scheduledAt: now.add(const Duration(hours: 3)),
      ),
    );
    await service.reconcile(lease, repo);
    expect(driver.alerts, hasLength(1));
    expect(driver.schedules, 3);
  });
}
