import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_model.dart';
import 'package:work_life/workspace/workspace_repository.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late SqliteWorkspaceRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('work_life_workspace_');
    repository = SqliteWorkspaceRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/app.db',
    );
  });
  tearDown(() async {
    await repository.close();
    await directory.delete(recursive: true);
  });

  test(
    'overnight plans appear on both days and invalid dates are rejected',
    () async {
      final task = Task(id: newId(), title: 'Late study', area: 'Study');
      await repository.saveTask(task);
      await repository.savePlan(
        PlanBlock(
          id: newId(),
          title: task.title,
          taskId: task.id,
          start: DateTime(2026, 9, 7, 23, 30),
          minutes: 60,
          area: 'Study',
        ),
      );
      final model = WorkspaceModel(repository);
      await model.load();
      expect(model.tasksForDay(DateTime(2026, 9, 7)).single.id, task.id);
      expect(model.tasksForDay(DateTime(2026, 9, 8)).single.id, task.id);
      expect(model.tasksForDay(DateTime(2026, 9, 9)), isEmpty);
      await expectLater(
        repository.saveTask(
          Task(
            id: newId(),
            title: 'Invalid deadline',
            area: 'Work',
            deadline: '2026-02-31',
          ),
        ),
        throwsArgumentError,
      );
      model.dispose();
    },
  );

  test('reminder rescheduling persists and inactive tasks clear it', () async {
    final task = Task(id: newId(), title: 'Call the dentist', area: 'Health');
    await repository.saveTask(task);
    final first = DateTime.now().toUtc().add(const Duration(hours: 1));
    await repository.saveReminder(
      TaskReminder(id: newId(), taskId: task.id, scheduledAt: first),
    );
    final second = first.add(const Duration(hours: 2));
    await repository.saveReminder(
      TaskReminder(id: newId(), taskId: task.id, scheduledAt: second),
    );
    await repository.close();
    var data = await repository.readWorkspace();
    expect(data.reminders, hasLength(1));
    expect(data.reminders.single.scheduledAt, second);
    await repository.saveTask(task.withStatus(TaskStatus.completed));
    data = await repository.readWorkspace();
    expect(data.reminders, isEmpty);
  });

  test('quiet hours persist across database reopen', () async {
    await repository.saveQuietHours(
      const QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 6 * 60),
    );
    await repository.close();
    final data = await repository.readWorkspace();
    expect(data.quietHours.enabled, isTrue);
    expect(data.quietHours.startMinute, 22 * 60);
    expect(data.quietHours.endMinute, 6 * 60);
  });

  test('reminder default persists and can be changed across reopen', () async {
    expect((await repository.readWorkspace()).reminderDefault, ReminderDefault.none);
    await repository.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
    await repository.close();
    expect(
      (await repository.readWorkspace()).reminderDefault,
      ReminderDefault.thirtyMinutesBefore,
    );
    await repository.saveReminderDefault(ReminderDefault.oneHourBefore);
    expect(
      (await repository.readWorkspace()).reminderDefault,
      ReminderDefault.oneHourBefore,
    );
  });

  test('a planned task receives the default once without rewriting existing intent', () async {
    final task = Task(id: newId(), title: 'Submit assignment', area: 'Study');
    await repository.saveTask(task);
    await repository.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
    final plan = PlanBlock(
      id: newId(),
      title: task.title,
      taskId: task.id,
      start: DateTime.now().add(const Duration(hours: 2)),
      minutes: 30,
      area: task.area,
    );
    await repository.savePlan(plan);
    var data = await repository.readWorkspace();
    expect(data.reminders, hasLength(1));
    expect(data.reminders.single.origin, ReminderOrigin.defaulted);
    final generated = data.reminders.single.scheduledAt;
    await repository.saveReminderDefault(ReminderDefault.tenMinutesBefore);
    data = await repository.readWorkspace();
    expect(data.reminders.single.scheduledAt, generated);

    final explicit = TaskReminder(
      id: data.reminders.single.id,
      taskId: task.id,
      scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
    );
    await repository.saveReminder(explicit);
    await repository.savePlan(
      PlanBlock(
        id: plan.id,
        title: plan.title,
        taskId: plan.taskId,
        start: plan.start.add(const Duration(minutes: 5)),
        minutes: plan.minutes,
        area: plan.area,
        fixed: plan.fixed,
      ),
    );
    data = await repository.readWorkspace();
    expect(data.reminders.single.scheduledAt, explicit.scheduledAt);
    expect(data.reminders.single.origin, ReminderOrigin.explicit);
  });

  test('removing a reminder explicitly suppresses future defaults', () async {
    final task = Task(id: newId(), title: 'Read', area: 'Rest');
    await repository.saveTask(task);
    await repository.saveReminderDefault(ReminderDefault.atTime);
    final plan = PlanBlock(
      id: newId(),
      title: task.title,
      taskId: task.id,
      start: DateTime.now().add(const Duration(hours: 2)),
      minutes: 20,
      area: task.area,
    );
    await repository.savePlan(plan);
    expect((await repository.readWorkspace()).reminders, hasLength(1));
    await repository.removeReminder(task.id);
    await repository.savePlan(
      PlanBlock(
        id: plan.id,
        title: plan.title,
        taskId: plan.taskId,
        start: plan.start.add(const Duration(minutes: 5)),
        minutes: plan.minutes,
        area: plan.area,
        fixed: plan.fixed,
      ),
    );
    expect((await repository.readWorkspace()).reminders, isEmpty);
  });

  test('clearLocalData removes workspace content and resets settings after reopen', () async {
    final task = Task(id: newId(), title: 'Delete me', area: 'Work');
    await repository.saveTask(task);
    await repository.saveReminderDefault(ReminderDefault.atTime);
    await repository.saveQuietHours(
      const QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 6 * 60),
    );
    await repository.saveReminder(
      TaskReminder(
        id: newId(),
        taskId: task.id,
        scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await repository.removeReminder(task.id);
    await repository.clearLocalData();
    await repository.close();
    final data = await repository.readWorkspace();
    expect(data.tasks, isEmpty);
    expect(data.projects, isEmpty);
    expect(data.plans, isEmpty);
    expect(data.reminders, isEmpty);
    expect(data.suppressedTaskIds, isEmpty);
    expect(data.routines, isEmpty);
    expect(data.routineRecords, isEmpty);
    expect(data.sessions, isEmpty);
    expect(data.quietHours.enabled, isFalse);
    expect(data.reminderDefault, ReminderDefault.none);
    expect(data.areas, ['Work', 'Study', 'Health', 'Relationships', 'Rest']);
  });

  test('v4 upgrade preserves intent and delivery status survives reopen without overwriting reschedules', () async {
    final task = Task(id: newId(), title: 'Rest', area: 'Rest');
    await repository.saveTask(task);
    final reminder = TaskReminder(
      id: newId(),
      taskId: task.id,
      scheduledAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    await repository.saveReminder(reminder);
    // Reconstruct the previous schema from the current one before reopening.
    final db = await repository.database.open();
    await db.execute('ALTER TABLE reminders DROP COLUMN delivery_status');
    await db.execute('PRAGMA user_version = 4');
    await repository.close();
    var data = await repository.readWorkspace();
    expect(data.reminders.single.scheduledAt, reminder.scheduledAt);
    expect(data.reminders.single.deliveryStatus, 'pending');
    await repository.recordReminderDelivery(reminder, 'scheduled');
    await repository.close();
    data = await repository.readWorkspace();
    expect(data.reminders.single.deliveryStatus, 'scheduled');
    final moved = TaskReminder(
      id: reminder.id,
      taskId: task.id,
      scheduledAt: reminder.scheduledAt.add(const Duration(hours: 1)),
    );
    await repository.saveReminder(moved);
    await repository.recordReminderDelivery(reminder, 'failed');
    data = await repository.readWorkspace();
    expect(data.reminders.single.deliveryStatus, 'pending');
    expect(data.reminders.single.scheduledAt, moved.scheduledAt);
  });

  test('removal preserves deadline and task; invalid reminders preserve existing time', () async {
    final task = Task(
      id: newId(),
      title: 'Call family',
      area: 'Relationships',
      deadline: '2099-12-31',
    );
    await repository.saveTask(task);
    final future = DateTime.now().toUtc().add(const Duration(days: 1));
    await repository.saveReminder(
      TaskReminder(id: newId(), taskId: task.id, scheduledAt: future),
    );
    for (final time in [
      DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      future.toLocal(),
    ]) {
      await expectLater(
        repository.saveReminder(
          TaskReminder(id: newId(), taskId: task.id, scheduledAt: time),
        ),
        throwsArgumentError,
      );
    }
    expect(
      (await repository.readWorkspace()).reminders.single.scheduledAt,
      future,
    );
    await repository.removeReminder(task.id);
    await repository.close();
    final data = await repository.readWorkspace();
    expect(data.reminders, isEmpty);
    expect(data.tasks.single.status, TaskStatus.open);
    expect(data.tasks.single.deadline, task.deadline);
    await repository.saveTask(task.withStatus(TaskStatus.cancelled));
    await expectLater(
      repository.saveReminder(
        TaskReminder(id: newId(), taskId: task.id, scheduledAt: future),
      ),
      throwsArgumentError,
    );
  });

  test(
    'finishing Focus clears reminder only for explicit task completion',
    () async {
      for (final outcome in FocusOutcome.values) {
        final task = Task(id: newId(), title: 'Walk', area: 'Health');
        await repository.saveTask(task);
        final now = DateTime.now().toUtc();
        await repository.saveReminder(
          TaskReminder(
            id: newId(),
            taskId: task.id,
            scheduledAt: now.add(const Duration(hours: 1)),
          ),
        );
        final session = FocusSession(
          id: newId(),
          taskId: task.id,
          minutes: 10,
          startedAt: now,
          runningSince: now,
        );
        await repository.saveSession(session);
        await repository.saveSession(
          session.finish(now.add(const Duration(minutes: 5)), outcome, ''),
        );
        final data = await repository.readWorkspace();
        expect(
          data.reminders.any((r) => r.taskId == task.id),
          outcome != FocusOutcome.completed,
        );
      }
    },
  );

  test('upgrades v1 without losing captures, links task once, and reopens workspace', () async {
    final original = Capture.create(
      '  Visa form by Friday?\nAsk partner about photo.  ',
    );
    final old = await databaseFactoryFfi.openDatabase(
      '${directory.path}/app.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE captures (id TEXT PRIMARY KEY, original_text TEXT NOT NULL, created_at TEXT NOT NULL)',
        ),
      ),
    );
    await old.insert('captures', {
      'id': original.id,
      'original_text': original.originalText,
      'created_at': original.createdAt.toIso8601String(),
    });
    await old.close();
    final data = await repository.readWorkspace();
    expect(
      data.areas,
      containsAll(['Work', 'Health', 'Relationships', 'Rest']),
    );
    final project = Project(
      id: newId(),
      title: 'Family paperwork',
      area: 'Relationships',
    );
    await repository.saveProject(project);
    final task = Task(
      id: newId(),
      title: 'Confirm form date',
      area: 'Relationships',
      captureId: original.id,
      projectId: project.id,
      checklist: [ChecklistItem(id: newId(), text: 'Ask about photo')],
    );
    await repository.saveTask(task);
    await repository.saveTask(task);
    await expectLater(
      repository.saveTask(
        Task(
          id: newId(),
          title: 'Duplicate conversion',
          area: 'Work',
          captureId: original.id,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    await repository.close();
    final reopened = await repository.readWorkspace();
    expect(reopened.tasks, hasLength(1));
    expect(reopened.tasks.single.deadline, isNull);
    expect(reopened.tasks.single.projectId, project.id);
    expect(reopened.tasks.single.checklist.single.text, 'Ask about photo');
    expect(
      (await repository.load()).single.originalText,
      original.originalText,
    );
  });

  test('plan move preserves task identity, confirmed deadline, and fixed appointment', () async {
    final task = Task(
      id: newId(),
      title: 'Prepare form',
      area: 'Relationships',
      deadline: '2026-09-11',
    );
    await repository.saveTask(task);
    final fixed = PlanBlock(
      id: newId(),
      title: 'Dinner together',
      start: DateTime(2026, 9, 10, 19),
      minutes: 60,
      area: 'Relationships',
      fixed: true,
    );
    final block = PlanBlock(
      id: newId(),
      title: task.title,
      taskId: task.id,
      start: DateTime(2026, 9, 10, 18),
      minutes: 30,
      area: task.area,
    );
    await repository.savePlan(fixed);
    await repository.savePlan(block);
    await repository.savePlan(
      PlanBlock(
        id: block.id,
        title: block.title,
        taskId: task.id,
        start: DateTime(2026, 9, 10, 17),
        minutes: 30,
        area: task.area,
      ),
    );
    final model = WorkspaceModel(repository);
    await model.load();
    expect(model.tasksForDay(DateTime(2026, 9, 10)).single.id, task.id);
    expect(model.data.tasks.single.deadline, '2026-09-11');
    expect(
      model.data.plans.firstWhere((p) => p.id == fixed.id).start,
      fixed.start,
    );
    expect(model.data.tasks, hasLength(1));
    await model.setStatus(task, TaskStatus.completed);
    expect(model.tasksForDay(DateTime(2026, 9, 10)), isEmpty);
    expect(model.task(task.id)!.status, TaskStatus.completed);
    await repository.removePlan(block.id);
    expect(
      (await repository.readWorkspace()).tasks.single.status,
      TaskStatus.completed,
    );
    model.dispose();
  });

  test('focus pause, restart and partial outcome retain elapsed time without completion', () async {
    final task = Task(
      id: newId(),
      title: 'Investigate bug',
      area: 'Work',
      minutes: 30,
    );
    await repository.saveTask(task);
    final start = DateTime.utc(2026, 9, 7, 10);
    final session = FocusSession(
      id: newId(),
      taskId: task.id,
      minutes: task.minutes,
      startedAt: start,
      runningSince: start,
    );
    await repository.saveSession(session);
    await expectLater(
      repository.saveSession(
        FocusSession(
          id: newId(),
          taskId: task.id,
          minutes: 25,
          startedAt: start,
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    await repository.saveSession(
      session.pause(start.add(const Duration(minutes: 5))),
    );
    await repository.close();
    var data = await repository.readWorkspace();
    expect(data.sessions.single.seconds, 300);
    expect(
      data.sessions.single.elapsed(start.add(const Duration(hours: 2))),
      300,
    );
    final resumed = data.sessions.single.resume(
      start.add(const Duration(hours: 2)),
    );
    await repository.saveSession(resumed);
    await repository.saveSession(
      resumed.finish(
        start.add(const Duration(hours: 2, minutes: 3)),
        FocusOutcome.partial,
        'Check the logs next',
      ),
    );
    data = await repository.readWorkspace();
    expect(data.sessions.single.seconds, 480);
    expect(data.sessions.single.notes, 'Check the logs next');
    expect(data.tasks.single.active, isTrue);
    await expectLater(repository.saveSession(resumed), throwsStateError);
  });

  test('explicit focus completion updates shared task atomically', () async {
    final task = Task(
      id: newId(),
      title: 'Prepare photo',
      area: 'Relationships',
    );
    await repository.saveTask(task);
    final start = DateTime.now().toUtc();
    final session = FocusSession(
      id: newId(),
      taskId: task.id,
      minutes: 25,
      startedAt: start,
      runningSince: start,
    );
    await repository.saveSession(session);
    await repository.saveSession(
      session.finish(
        start.add(const Duration(minutes: 4)),
        FocusOutcome.completed,
        'Ready',
      ),
    );
    final data = await repository.readWorkspace();
    expect(data.tasks.single.status, TaskStatus.completed);
    expect(data.sessions.single.outcome, FocusOutcome.completed);
  });

  test('project bug and later idea stay linked to the focus task', () async {
    final p = Project(id: newId(), title: 'Restaurant software', area: 'Work');
    await repository.saveProject(p);
    final bug = ProjectEntry(
      id: newId(),
      projectId: p.id,
      title: 'Checkout error',
      body: 'Observed a timeout; cause unknown.',
      kind: 'bug',
    );
    final idea = ProjectEntry(
      id: newId(),
      projectId: p.id,
      title: 'Inspect request logs',
      body: 'Could be a retry issue; unconfirmed.',
      kind: 'idea',
      relatedId: bug.id,
    );
    await repository.saveEntry(bug);
    await repository.saveEntry(idea);
    final t = Task(
      id: newId(),
      title: 'Reproduce timeout',
      area: 'Work',
      projectId: p.id,
      entryId: idea.id,
    );
    await repository.saveTask(t);
    final start = DateTime.now().toUtc();
    final session = FocusSession(
      id: newId(),
      taskId: t.id,
      minutes: 25,
      startedAt: start,
      runningSince: start,
    );
    await repository.saveSession(session);
    await repository.saveSession(
      session.finish(
        start.add(const Duration(minutes: 3)),
        FocusOutcome.blocked,
        'Need sample order',
      ),
    );
    await repository.close();
    final data = await repository.readWorkspace();
    expect(data.entries.firstWhere((e) => e.id == idea.id).relatedId, bug.id);
    expect(data.tasks.single.entryId, idea.id);
    expect(data.sessions.single.taskId, t.id);
    expect(data.sessions.single.outcome, FocusOutcome.blocked);
    expect(data.tasks.single.active, isTrue);
    // Changing the current task's category must not rewrite recorded focus history.
    await repository.saveTask(
      Task(
        id: t.id,
        title: t.title,
        area: 'Study',
        projectId: p.id,
        entryId: idea.id,
      ),
    );
    expect((await repository.readWorkspace()).sessions.single.area, 'Work');
  });

  test('routine outcomes are per day, retries do not duplicate, gaps remain unknown', () async {
    final routine = Routine(
      id: newId(),
      title: 'Move a little',
      area: 'Health',
      window: 'After lunch',
      alternative: 'Walk five minutes',
      createdDay: '2026-09-07',
    );
    await repository.saveRoutine(routine);
    await repository.recordRoutine(
      RoutineRecord(routineId: routine.id, day: '2026-09-07', outcome: 'later'),
    );
    await repository.recordRoutine(
      RoutineRecord(
        routineId: routine.id,
        day: '2026-09-07',
        outcome: 'smaller',
      ),
    );
    await repository.recordRoutine(
      RoutineRecord(
        routineId: routine.id,
        day: '2026-09-07',
        outcome: 'smaller',
      ),
    );
    final data = await repository.readWorkspace();
    expect(data.routineRecords, hasLength(1));
    expect(data.routineRecords.single.outcome, 'smaller');
    expect(data.routineRecords.where((r) => r.day == '2026-09-08'), isEmpty);
  });
}
