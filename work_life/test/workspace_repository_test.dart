import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/ai/ai_proposals.dart';
import 'package:work_life/ai/day_context_builder.dart';
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
    expect(
      (await repository.readWorkspace()).reminderDefault,
      ReminderDefault.none,
    );
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

  test(
    'date-only deadline receives and reschedules its generated reminder',
    () async {
      await repository.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
      final due = DateTime.now().add(const Duration(days: 3));
      final task = Task(
        id: newId(),
        title: 'Submit assignment',
        area: 'Study',
        deadline: dayKey(due),
      );
      await repository.saveTask(task);
      var data = await repository.readWorkspace();
      expect(data.reminders, hasLength(1));
      expect(data.reminders.single.basis, ReminderBasis.dueDate);
      expect(
        data.reminders.single.scheduledAt,
        DateTime(due.year, due.month, due.day, 8, 30).toUtc(),
      );

      final changed = due.add(const Duration(days: 2));
      await repository.saveTask(
        Task(
          id: task.id,
          title: task.title,
          area: task.area,
          deadline: dayKey(changed),
        ),
      );
      data = await repository.readWorkspace();
      expect(data.reminders, hasLength(1));
      expect(
        data.reminders.single.scheduledAt,
        DateTime(changed.year, changed.month, changed.day, 8, 30).toUtc(),
      );
    },
  );

  test(
    'explicit reminder and explicit no-reminder override date-only defaults',
    () async {
      await repository.saveReminderDefault(ReminderDefault.atTime);
      final due = DateTime.now().add(const Duration(days: 3));
      final task = Task(
        id: newId(),
        title: 'Call lecturer',
        area: 'Study',
        deadline: dayKey(due),
      );
      await repository.saveTask(task);
      final chosen = DateTime.now().toUtc().add(const Duration(hours: 4));
      await repository.saveReminder(
        TaskReminder(id: newId(), taskId: task.id, scheduledAt: chosen),
      );
      await repository.saveTask(task);
      var data = await repository.readWorkspace();
      expect(data.reminders.single.scheduledAt, chosen);
      expect(data.reminders.single.basis, ReminderBasis.explicit);

      await repository.removeReminder(task.id);
      await repository.saveTask(task);
      await repository.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
      data = await repository.readWorkspace();
      expect(data.reminders, isEmpty);
      expect(data.suppressedTaskIds, contains(task.id));
    },
  );

  test('completion and reset remove generated due reminders', () async {
    await repository.saveReminderDefault(ReminderDefault.atTime);
    final due = DateTime.now().add(const Duration(days: 3));
    final task = Task(
      id: newId(),
      title: 'Renew pass',
      area: 'Work',
      deadline: dayKey(due),
    );
    await repository.saveTask(task);
    expect((await repository.readWorkspace()).reminders, hasLength(1));
    await repository.saveTask(task.withStatus(TaskStatus.completed));
    expect((await repository.readWorkspace()).reminders, isEmpty);

    final second = Task(
      id: newId(),
      title: 'File report',
      area: 'Work',
      deadline: dayKey(due),
    );
    await repository.saveTask(second);
    expect((await repository.readWorkspace()).reminders, hasLength(1));
    await repository.clearLocalData();
    expect((await repository.readWorkspace()).reminders, isEmpty);
  });

  test(
    'project AI diff applies selected add change move remove once',
    () async {
      final project = Project(id: newId(), title: 'AWS', area: 'Study');
      await repository.saveProject(project);
      final changed = Task(
        id: newId(),
        title: 'Study AWS',
        area: 'Study',
        projectId: project.id,
      );
      final moved = Task(
        id: newId(),
        title: 'Practice exam',
        area: 'Study',
        projectId: project.id,
        deadline: '2035-04-12',
      );
      final removed = Task(
        id: newId(),
        title: 'Old task',
        area: 'Study',
        projectId: project.id,
      );
      final rejected = Task(
        id: newId(),
        title: 'Keep me',
        area: 'Study',
        projectId: project.id,
      );
      for (final task in [changed, moved, removed, rejected]) {
        await repository.saveTask(task);
      }
      final proposal = AiProjectProposal(
        title: 'AWS',
        area: 'Study',
        tasks: [
          AiTaskProposal(title: 'Take mock exam', change: AiProjectChange.add),
          AiTaskProposal(
            taskId: changed.id,
            title: 'Study AWS Core Services',
            change: AiProjectChange.change,
          ),
          AiTaskProposal(
            taskId: moved.id,
            title: moved.title,
            deadline: '2035-04-15',
            change: AiProjectChange.move,
          ),
          AiTaskProposal(
            taskId: removed.id,
            title: removed.title,
            change: AiProjectChange.remove,
          ),
          AiTaskProposal(
            taskId: rejected.id,
            title: 'AI wanted to change this',
            change: AiProjectChange.change,
            included: false,
          ),
        ],
      );
      await repository.applyProjectProposal(
        proposal,
        operationId: 'diff-once',
        targetProjectId: project.id,
      );
      await repository.applyProjectProposal(
        proposal,
        operationId: 'diff-once',
        targetProjectId: project.id,
      );
      final data = await repository.readWorkspace();
      expect(
        data.tasks.where((task) => task.projectId == project.id),
        hasLength(4),
      );
      expect(
        data.tasks.singleWhere((task) => task.id == changed.id).title,
        'Study AWS Core Services',
      );
      expect(
        data.tasks.singleWhere((task) => task.id == moved.id).deadline,
        '2035-04-15',
      );
      expect(
        data.tasks.singleWhere((task) => task.id == removed.id).status,
        TaskStatus.cancelled,
      );
      expect(
        data.tasks.singleWhere((task) => task.id == rejected.id).title,
        'Keep me',
      );
    },
  );

  test(
    'project AI diff rolls back all changes when one operation is invalid',
    () async {
      final project = Project(id: newId(), title: 'Safe project', area: 'Work');
      await repository.saveProject(project);
      final proposal = AiProjectProposal(
        title: 'Changed title',
        area: 'Work',
        tasks: [
          AiTaskProposal(title: 'Would be added', change: AiProjectChange.add),
          AiTaskProposal(
            taskId: 'missing',
            title: 'Missing',
            change: AiProjectChange.remove,
          ),
        ],
      );
      await expectLater(
        repository.applyProjectProposal(
          proposal,
          operationId: 'failing-diff',
          targetProjectId: project.id,
        ),
        throwsArgumentError,
      );
      final data = await repository.readWorkspace();
      expect(data.projects.single.title, 'Safe project');
      expect(data.tasks, isEmpty);
    },
  );

  test(
    'approved AI project persists its calendar block and reminder atomically',
    () async {
      final proposal = AiProjectProposal(
        title: 'Birthday preparation',
        area: 'Relationships',
        tasks: [
          AiTaskProposal(
            title: 'Collect birthday cake',
            group: 'Birthday',
            details: 'Confirm dietary preferences before ordering.',
            minutes: 45,
            deadline: '2099-05-03',
            plannedStart: '2099-05-02T15:00:00+07:00',
            reminder: '2099-05-02T14:30:00+07:00',
          ),
        ],
      );
      await repository.applyProjectProposal(
        proposal,
        operationId: 'calendar-and-reminder',
      );
      final data = await repository.readWorkspace();
      final task = data.tasks.single;
      expect(task.notes, contains('dietary preferences'));
      expect(data.plans.single.taskId, task.id);
      expect(data.plans.single.minutes, 45);
      expect(data.reminders.single.taskId, task.id);
      expect(data.reminders.single.origin, ReminderOrigin.explicit);
      expect(data.reminders.single.basis, ReminderBasis.plannedTime);
    },
  );

  test(
    'approved standalone AI task persists calendar and explicit reminder',
    () async {
      final proposal = AiCaptureProposal(
        kind: AiCaptureKind.standaloneTask,
        task: AiTaskProposal(
          title: 'Collect parcel',
          area: 'Work',
          minutes: 30,
          plannedStart: '2099-05-02T15:00:00+07:00',
          reminder: '2099-05-02T14:45:00+07:00',
        ),
      );
      await repository.applyCaptureProposal(
        proposal,
        operationId: 'standalone-calendar-reminder',
      );
      final data = await repository.readWorkspace();
      final task = data.tasks.single;
      expect(data.plans.single.taskId, task.id);
      expect(data.reminders.single.taskId, task.id);
      expect(data.reminders.single.origin, ReminderOrigin.explicit);
      expect(data.reminders.single.basis, ReminderBasis.plannedTime);
    },
  );

  test('AI project approval rejects calendar conflicts atomically', () async {
    await repository.savePlan(
      PlanBlock(
        id: newId(),
        title: 'Existing appointment',
        start: DateTime(2099, 5, 2, 15),
        minutes: 60,
        area: 'Work',
        fixed: true,
      ),
    );
    final proposal = AiProjectProposal(
      title: 'Parcel trip',
      area: 'Work',
      tasks: [
        AiTaskProposal(
          title: 'Collect parcel',
          minutes: 30,
          plannedStart: '2099-05-02T15:15:00+07:00',
        ),
      ],
    );
    await expectLater(
      repository.applyProjectProposal(
        proposal,
        operationId: 'calendar-conflict',
      ),
      throwsArgumentError,
    );
    final data = await repository.readWorkspace();
    expect(data.projects, isEmpty);
    expect(data.tasks, isEmpty);
    expect(data.plans.single.title, 'Existing appointment');
  });

  test(
    'clearLocalData removes workspace content and resets settings after reopen',
    () async {
      final task = Task(id: newId(), title: 'Delete me', area: 'Work');
      await repository.saveTask(task);
      await repository.saveReminderDefault(ReminderDefault.atTime);
      await repository.saveQuietHours(
        const QuietHours(
          enabled: true,
          startMinute: 22 * 60,
          endMinute: 6 * 60,
        ),
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
    },
  );

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

  test(
    'AI schedule approval is atomic, idempotent, and reuses reminder defaults',
    () async {
      const task = Task(
        id: 'ai-task',
        title: 'Prepare presentation',
        area: 'Work',
        priority: TaskPriority.high,
      );
      await repository.saveTask(task);
      await repository.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
      await repository.savePlan(
        PlanBlock(
          id: 'fixed',
          title: 'Class',
          start: DateTime(2099, 4, 16, 9),
          minutes: 60,
          area: 'Study',
          fixed: true,
        ),
      );
      final event = AiScheduleEvent(
        title: task.title,
        taskId: task.id,
        date: '2099-04-16',
        start: '09:30',
        end: '10:30',
      );
      final proposal = AiScheduleProposal(events: [event]);
      await expectLater(
        repository.applyScheduleProposal(proposal, operationId: 'schedule'),
        throwsArgumentError,
      );
      event.start = '10:30';
      event.end = '11:30';
      await repository.applyScheduleProposal(proposal, operationId: 'schedule');
      await repository.applyScheduleProposal(proposal, operationId: 'schedule');
      final data = await repository.readWorkspace();
      expect(data.tasks.single.priority, TaskPriority.high);
      expect(data.plans, hasLength(2));
      expect(data.reminders, hasLength(1));
      expect(
        data.reminders.single.scheduledAt.toLocal(),
        DateTime(2099, 4, 16, 10),
      );
    },
  );

  test('lifestyle blocks persist in Planner without creating tasks and buffers protect class', () async {
    await repository.saveRecurringSchedule(
      const RecurringSchedule(
        id: 'class',
        title: 'Class',
        type: RecurringScheduleType.classSession,
        weekday: 1,
        startTime: '09:00',
        endTime: '12:00',
        startDate: '2030-01-01',
      ),
    );
    final proposal = AiScheduleProposal(
      events: [
        AiScheduleEvent(
          title: 'Exercise',
          date: '2030-01-07',
          start: '12:15',
          end: '13:00',
          kind: 'exercise',
        ),
      ],
    );
    await repository.applyScheduleProposal(proposal, operationId: 'lifestyle');
    final data = await repository.readWorkspace();
    expect(data.tasks, isEmpty);
    expect(data.plans.single.title, 'Exercise');
    await expectLater(
      repository.applyScheduleProposal(
        AiScheduleProposal(
          events: [
            AiScheduleEvent(
              title: 'Travel',
              date: '2030-01-07',
              start: '11:50',
              end: '12:20',
              kind: 'travel',
            ),
          ],
        ),
        operationId: 'buffered',
      ),
      throwsArgumentError,
    );
  });

  test('AI removal is user-approved, editable plans only, and sleep limits are enforced', () async {
    final plan = PlanBlock(
      id: 'flex',
      title: 'Study',
      start: DateTime(2030, 1, 7, 18),
      minutes: 60,
      area: 'Study',
    );
    await repository.savePlan(plan);
    await repository.applyScheduleProposal(
      AiScheduleProposal(
        events: [
          AiScheduleEvent(
            title: 'Study',
            planId: 'flex',
            date: '2030-01-07',
            start: '18:00',
            end: '19:00',
            operation: 'remove',
          ),
        ],
      ),
      operationId: 'remove-flex',
    );
    expect((await repository.readWorkspace()).plans, isEmpty);
    await expectLater(
      repository.applyScheduleProposal(
        AiScheduleProposal(
          events: [
            AiScheduleEvent(
              title: 'Late work',
              date: '2030-01-07',
              start: '22:00',
              end: '22:30',
              taskId: null,
              kind: 'task',
            ),
          ],
        ),
        operationId: 'late',
      ),
      throwsArgumentError,
    );
  });

  test(
    'AI schedule changes require stable IDs and preserve task links',
    () async {
      const task = Task(id: 'linked-task', title: 'Assignment', area: 'Study');
      await repository.saveTask(task);
      await repository.savePlan(
        PlanBlock(
          id: 'linked-plan',
          title: task.title,
          taskId: task.id,
          start: DateTime(2030, 1, 7, 14),
          minutes: 60,
          area: task.area,
        ),
      );

      await expectLater(
        repository.applyScheduleProposal(
          AiScheduleProposal(
            events: [
              AiScheduleEvent(
                title: 'Missing identity',
                date: '2030-01-07',
                start: '16:00',
                end: '17:00',
                operation: 'move',
              ),
            ],
          ),
          operationId: 'missing-plan-id',
        ),
        throwsArgumentError,
      );

      await repository.applyScheduleProposal(
        AiScheduleProposal(
          events: [
            AiScheduleEvent(
              title: task.title,
              planId: 'linked-plan',
              date: '2030-01-07',
              start: '16:00',
              end: '17:00',
              operation: 'move',
            ),
          ],
        ),
        operationId: 'preserve-task-link',
      );
      final moved = (await repository.readWorkspace()).plans.single;
      expect(moved.taskId, task.id);
      expect(moved.start, DateTime(2030, 1, 7, 16));
    },
  );

  test(
    'partial schedule acceptance cannot overlap an untouched flexible block',
    () async {
      await repository.savePlan(
        PlanBlock(
          id: 'kept-plan',
          title: 'Keep me',
          start: DateTime(2030, 1, 7, 10),
          minutes: 60,
          area: 'Work',
        ),
      );
      await expectLater(
        repository.applyScheduleProposal(
          AiScheduleProposal(
            events: [
              AiScheduleEvent(
                title: 'Remove kept block',
                planId: 'kept-plan',
                operation: 'remove',
                included: false,
              ),
              AiScheduleEvent(
                title: 'Exercise',
                date: '2030-01-07',
                start: '10:30',
                end: '11:15',
                kind: 'exercise',
              ),
            ],
          ),
          operationId: 'partial-overlap',
        ),
        throwsArgumentError,
      );
      expect((await repository.readWorkspace()).plans.single.id, 'kept-plan');
    },
  );

  test('malformed negative AI clock values are rejected', () async {
    await expectLater(
      repository.applyScheduleProposal(
        AiScheduleProposal(
          events: [
            AiScheduleEvent(
              title: 'Normalized by DateTime',
              date: '2030-01-07',
              start: '09:-1',
              end: '09:30',
              kind: 'personal',
            ),
          ],
        ),
        operationId: 'negative-clock',
      ),
      throwsArgumentError,
    );
    expect((await repository.readWorkspace()).plans, isEmpty);
  });

  test(
    'schedule proposal rejects material Planner changes without partial writes',
    () async {
      final day = DateTime(2030, 1, 7);
      final before = await repository.readWorkspace();
      final proposal = AiScheduleProposal(
        baseFingerprints: {
          dayKey(day): const DayContextBuilder().fingerprint(before, day),
        },
        events: [
          AiScheduleEvent(
            title: 'Exercise',
            date: dayKey(day),
            start: '10:00',
            end: '10:30',
            kind: 'exercise',
          ),
        ],
      );
      await repository.savePlan(
        PlanBlock(
          id: 'new-fixed',
          title: 'New appointment',
          start: DateTime(2030, 1, 7, 14),
          minutes: 30,
          area: 'Work',
          fixed: true,
        ),
      );

      await expectLater(
        repository.applyScheduleProposal(proposal, operationId: 'stale-plan'),
        throwsA(isA<StaleScheduleProposalException>()),
      );
      final plans = (await repository.readWorkspace()).plans;
      expect(plans.map((plan) => plan.id), ['new-fixed']);
    },
  );

  test('irrelevant changes keep a proposal valid and regeneration refreshes its base', () async {
    final day = DateTime(2030, 1, 7);
    final builder = const DayContextBuilder();
    final oldBase = builder.fingerprint(await repository.readWorkspace(), day);
    await repository.saveTask(
      const Task(id: 'distant', title: 'Someday', area: 'Work'),
    );
    expect(builder.fingerprint(await repository.readWorkspace(), day), oldBase);

    final proposal = AiScheduleProposal(
      baseFingerprints: {dayKey(day): oldBase},
      events: [
        AiScheduleEvent(
          title: 'Walk',
          date: dayKey(day),
          start: '10:00',
          end: '10:30',
          kind: 'exercise',
        ),
      ],
    );
    await repository.applyScheduleProposal(proposal, operationId: 'fresh-base');
    expect((await repository.readWorkspace()).plans.single.title, 'Walk');

    final regenerated = AiScheduleProposal(
      baseFingerprints: {
        dayKey(day): builder.fingerprint(await repository.readWorkspace(), day),
      },
      events: [
        AiScheduleEvent(
          title: 'Read',
          date: dayKey(day),
          start: '11:00',
          end: '11:30',
          kind: 'personal',
        ),
      ],
    );
    await repository.applyScheduleProposal(
      regenerated,
      operationId: 'regenerated-base',
    );
    expect((await repository.readWorkspace()).plans, hasLength(2));
  });

  test('recurrence exception makes an existing day proposal stale', () async {
    final day = DateTime(2030, 1, 7);
    await repository.saveRecurringSchedule(
      const RecurringSchedule(
        id: 'class-stale',
        title: 'Class',
        type: RecurringScheduleType.classSession,
        weekday: DateTime.monday,
        startTime: '09:00',
        endTime: '10:00',
        startDate: '2030-01-01',
      ),
    );
    final builder = const DayContextBuilder();
    final proposal = AiScheduleProposal(
      baseFingerprints: {
        dayKey(day): builder.fingerprint(await repository.readWorkspace(), day),
      },
      events: [
        AiScheduleEvent(
          title: 'Lunch',
          date: dayKey(day),
          start: '12:00',
          end: '12:30',
          kind: 'meal',
        ),
      ],
    );
    await repository.saveScheduleException(
      const ScheduleException(scheduleId: 'class-stale', day: '2030-01-07'),
    );
    await expectLater(
      repository.applyScheduleProposal(
        proposal,
        operationId: 'stale-recurrence',
      ),
      throwsA(isA<StaleScheduleProposalException>()),
    );
    expect((await repository.readWorkspace()).plans, isEmpty);
  });

  test('deleted linked Task rejects its stale proposal atomically', () async {
    final day = DateTime(2030, 1, 7);
    const task = Task(
      id: 'deleted-proposal-task',
      title: 'Assignment',
      area: 'Study',
      deadline: '2030-01-07',
    );
    await repository.saveTask(task);
    final proposal = AiScheduleProposal(
      baseFingerprints: {
        dayKey(day): const DayContextBuilder().fingerprint(
          await repository.readWorkspace(),
          day,
        ),
      },
      events: [
        AiScheduleEvent(
          title: task.title,
          taskId: task.id,
          date: dayKey(day),
          start: '13:00',
          end: '14:00',
        ),
      ],
    );
    await (await repository.database.open()).delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    await expectLater(
      repository.applyScheduleProposal(proposal, operationId: 'deleted-task'),
      throwsA(isA<StaleScheduleProposalException>()),
    );
    expect((await repository.readWorkspace()).plans, isEmpty);
  });

  test(
    'weekly proposal moves across days and keeps split sessions linked',
    () async {
      const task = Task(
        id: 'weekly-task',
        title: 'Prepare release',
        area: 'Work',
        deadline: '2030-01-13',
        minutes: 120,
      );
      await repository.saveTask(task);
      await repository.savePlan(
        PlanBlock(
          id: 'existing-session',
          title: task.title,
          taskId: task.id,
          start: DateTime(2030, 1, 7, 9),
          minutes: 60,
          area: task.area,
        ),
      );
      final snapshot = await repository.readWorkspace();
      final proposal = AiScheduleProposal(
        baseFingerprints: const WeekContextBuilder().fingerprints(
          snapshot,
          DateTime(2030, 1, 7),
        ),
        events: [
          AiScheduleEvent(
            planId: 'existing-session',
            taskId: task.id,
            title: 'Prepare release · part 1',
            date: '2030-01-09',
            start: '09:00',
            end: '10:00',
            operation: 'move',
          ),
          AiScheduleEvent(
            taskId: task.id,
            title: 'Prepare release · part 2',
            date: '2030-01-11',
            start: '09:00',
            end: '10:00',
          ),
        ],
      );
      await repository.applyScheduleProposal(
        proposal,
        operationId: 'week-plan',
      );
      final data = await repository.readWorkspace();
      expect(data.tasks.where((item) => item.id == task.id), hasLength(1));
      expect(data.plans.where((plan) => plan.taskId == task.id), hasLength(2));
      expect(
        data.plans.map((plan) => dayKey(plan.start)),
        containsAll(['2030-01-09', '2030-01-11']),
      );
    },
  );

  test(
    'weekly proposal cannot schedule linked work after its deadline',
    () async {
      await repository.saveTask(
        const Task(
          id: 'deadline-task',
          title: 'Submit application',
          area: 'Work',
          deadline: '2030-01-10',
        ),
      );
      await expectLater(
        repository.applyScheduleProposal(
          AiScheduleProposal(
            events: [
              AiScheduleEvent(
                taskId: 'deadline-task',
                title: 'Submit application',
                date: '2030-01-11',
                start: '09:00',
                end: '10:00',
              ),
            ],
          ),
          operationId: 'late-week-plan',
        ),
        throwsArgumentError,
      );
      expect((await repository.readWorkspace()).plans, isEmpty);
    },
  );
}
