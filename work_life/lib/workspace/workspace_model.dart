import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notifications/reminder_notifications.dart';

import 'records.dart';
import 'local_data_export.dart';
import 'local_data_import.dart';
import 'workspace_repository.dart';

class WorkspaceModel extends ChangeNotifier {
  WorkspaceModel(
    this.repository, {
    this.notifications,
    this.afterChange,
    String notificationScope = 'guest',
  }) {
    _notificationLease = notifications?.attach(notificationScope);
    notifications?.addListener(_changed);
  }
  final WorkspaceRepository repository;
  final ReminderNotifications? notifications;
  final Future<void> Function()? afterChange;
  int? _notificationLease;
  bool _refreshingNotifications = false;
  WorkspaceData data = const WorkspaceData();
  bool loading = true, busy = false;
  String? error;
  Object? lastFailure;
  bool _disposed = false;
  int resetRevision = 0;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    lastFailure = null;
    _changed();
    try {
      data = await repository.readWorkspace();
      await _advanceRecurringReminders();
      data = await repository.readWorkspace();
      await _syncNotifications();
    } catch (_) {
      error = 'Couldn’t load your saved workspace. Please retry.';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<bool> change(Future<void> Function() operation) async {
    if (busy || loading) return false;
    busy = true;
    error = null;
    lastFailure = null;
    _changed();
    try {
      await operation();
      data = await repository.readWorkspace();
      await _syncNotifications();
      final callback = afterChange;
      if (callback != null) {
        unawaited(Future<void>.delayed(Duration.zero, callback));
      }
      return true;
    } catch (failure) {
      lastFailure = failure;
      error = 'Couldn’t finish that change. Your saved records are kept. Please retry.';
      return false;
    } finally {
      busy = false;
      _changed();
    }
  }

  Task? task(String id) {
    for (final t in data.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _syncNotifications({bool requestPermission = false}) async {
    if (_disposed || notifications == null) return;
    await notifications!.reconcile(
      _notificationLease!,
      repository,
      requestPermission: requestPermission,
    );
    if (_disposed) return;
    // Notification failure must not turn a successful task save into an error.
    try {
      data = await repository.readWorkspace();
    } catch (_) {
      // Keep the last committed view; normal load can retry later.
    }
  }

  Future<void> _advanceRecurringReminders() async {
    final now = DateTime.now().toUtc();
    for (final reminder in data.reminders) {
      if (reminder.recurrence == ReminderRecurrence.none ||
          reminder.scheduledAt.isAfter(now)) {
        continue;
      }
      var next = reminder.scheduledAt;
      final increment = reminder.recurrence == ReminderRecurrence.daily
          ? const Duration(days: 1)
          : const Duration(days: 7);
      while (!next.isAfter(now)) {
        next = next.add(increment);
      }
      await repository.saveReminder(
        TaskReminder(
          id: reminder.id,
          taskId: reminder.taskId,
          scheduledAt: next,
          origin: reminder.origin,
          basis: reminder.basis,
          recurrence: reminder.recurrence,
        ),
      );
    }
  }

  Future<void> refreshNotifications({bool requestPermission = false}) async {
    if (busy || loading || _refreshingNotifications || _disposed) return;
    _refreshingNotifications = true;
    try {
      await _advanceRecurringReminders();
      data = await repository.readWorkspace();
      await _syncNotifications(requestPermission: requestPermission);
    } finally {
      _refreshingNotifications = false;
      _changed();
    }
  }

  FocusSession? get activeSession {
    for (final s in data.sessions) {
      if (s.outcome == null) return s;
    }
    return null;
  }

  TaskReminder? reminderFor(String taskId) {
    for (final reminder in data.reminders) {
      if (reminder.taskId == taskId) return reminder;
    }
    return null;
  }

  List<Task> tasksForDay(DateTime day) {
    final key = dayKey(day);
    final ids = data.plans
        .where((p) => p.occursOn(day))
        .map((p) => p.taskId)
        .toSet();
    return data.tasks
        .where(
          (t) =>
              t.active &&
              (ids.contains(t.id) ||
                  (t.deadline != null && t.deadline!.compareTo(key) <= 0)),
        )
        .toList();
  }

  List<TaskReminder> get pendingReminders {
    final activeIds = data.tasks
        .where((t) => t.active)
        .map((t) => t.id)
        .toSet();
    return data.reminders.where((r) => activeIds.contains(r.taskId)).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Future<bool> setStatus(Task task, TaskStatus status) =>
      change(() => repository.saveTask(task.withStatus(status)));

  Future<String> exportLocalData() => LocalDataExport(repository).buildJson();

  Future<String> exportReadableReport() =>
      LocalDataExport(repository).buildMarkdown();

  Future<String> exportTasksCsv() =>
      LocalDataExport(repository).buildTasksCsv();

  Future<bool> importLocalData(String json) async => change(() async {
    await LocalDataImport(repository).restore(json);
  });

  Future<bool> deleteLocalData() async {
    if (busy || loading || _disposed) return false;
    busy = true;
    error = null;
    _changed();
    try {
      if (notifications == null) {
        await repository.clearLocalData();
      } else {
        await notifications!.deleteLocalData(_notificationLease!, repository);
      }
      // Discard stale records even if the subsequent read fails.
      data = const WorkspaceData(
        areas: ['Work', 'Study', 'Health', 'Relationships', 'Rest'],
      );
      resetRevision++;
      final callback = afterChange;
      if (callback != null) {
        unawaited(Future<void>.delayed(Duration.zero, callback));
      }
      try {
        data = await repository.readWorkspace();
      } catch (_) {
        error =
            'Local data was deleted. Couldn’t reload settings; please retry.';
      }
      await _syncNotifications();
      return true;
    } catch (_) {
      error = 'Couldn’t delete local data. Notification cleanup or storage failed. Please retry.';
      return false;
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    notifications?.removeListener(_changed);
    if (_notificationLease != null) notifications!.detach(_notificationLease!);
    super.dispose();
  }
}
