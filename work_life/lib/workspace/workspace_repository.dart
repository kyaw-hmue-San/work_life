import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../captures/capture_repository.dart';
import '../captures/capture.dart';
import 'records.dart';
import 'reminder_defaults.dart';

abstract interface class WorkspaceRepository implements CaptureRepository {
  Future<WorkspaceData> readWorkspace();
  Future<({List<Capture> captures, WorkspaceData workspace})>
  readExportSnapshot();
  Future<void> saveProject(Project project);
  Future<void> saveEntry(ProjectEntry entry);
  Future<void> saveTask(Task task);
  Future<void> saveReminder(TaskReminder reminder);
  Future<void> removeReminder(String taskId);
  Future<void> recordReminderDelivery(TaskReminder reminder, String status);
  Future<void> saveQuietHours(QuietHours quietHours);
  Future<void> saveReminderDefault(ReminderDefault value);
  Future<void> clearLocalData();
  Future<void> completeOnboarding({ReminderDefault? reminderDefault});
  Future<void> savePlan(PlanBlock plan);
  Future<void> removePlan(String id);
  Future<void> saveRoutine(Routine routine);
  Future<void> recordRoutine(RoutineRecord record);
  Future<void> saveSession(FocusSession session);
  Future<void> addArea(String name);
}

class SqliteWorkspaceRepository extends SqliteCaptureRepository
    implements WorkspaceRepository {
  SqliteWorkspaceRepository({
    super.factory,
    super.databasePath,
    super.databaseName,
  });

  @override
  Future<WorkspaceData> readWorkspace() async {
    final db = await database.open();
    return db.transaction(_readWorkspace);
  }

  @override
  Future<({List<Capture> captures, WorkspaceData workspace})>
  readExportSnapshot() async {
    final db = await database.open();
    return db.transaction((tx) async {
      final rows = await tx.query('captures');
      final captures = rows
          .map(
            (r) => Capture(
              id: r['id'] as String,
              originalText: r['original_text'] as String,
              createdAt: DateTime.parse(r['created_at'] as String),
            ),
          )
          .toList();
      return (captures: captures, workspace: await _readWorkspace(tx));
    });
  }

  Future<WorkspaceData> _readWorkspace(Transaction tx) async {
    final entries = await tx.query('project_entries', orderBy: 'rowid DESC');
    final tasks = await tx.query('tasks', orderBy: 'rowid DESC');
    final projects = await tx.query('projects', orderBy: 'rowid DESC');
    final plans = await tx.query('plans', orderBy: 'start ASC');
    final routines = await tx.query('routines', orderBy: 'rowid');
    final records = await tx.query('routine_records');
    final sessions = await tx.query(
      'focus_sessions',
      orderBy: 'started_at DESC',
    );
    final areas = await tx.query('life_areas', orderBy: 'rowid');
    final reminders = await tx.query('reminders');
    final suppressions = await tx.query('reminder_suppressions');
    final quietHours = (await tx.query('quiet_hours', where: 'id = 1')).single;
    final reminderPreference = (await tx.query(
      'reminder_preferences',
      where: 'id = 1',
    )).single;
    final setup = (await tx.query('workspace_setup', where: 'id = 1')).single;
    return WorkspaceData(
      onboardingCompleted: setup['completed'] == 1,
      entries: entries
          .map(
            (r) => ProjectEntry(
              id: r['id'] as String,
              projectId: r['project_id'] as String,
              title: r['title'] as String,
              body: r['body'] as String,
              kind: r['kind'] as String,
              relatedId: r['related_id'] as String?,
              captureId: r['capture_id'] as String?,
            ),
          )
          .toList(),
      tasks: tasks
          .map(
            (r) => Task(
              id: r['id'] as String,
              title: r['title'] as String,
              area: r['area'] as String,
              projectId: r['project_id'] as String?,
              captureId: r['capture_id'] as String?,
              entryId: r['entry_id'] as String?,
              deadline: r['deadline'] as String?,
              minutes: r['minutes'] as int,
              notes: r['notes'] as String,
              status: TaskStatus.values.byName(r['status'] as String),
              checklist: (jsonDecode(r['checklist'] as String) as List<dynamic>)
                  .map((dynamic item) {
                    final m = item as Map<String, dynamic>;
                    return ChecklistItem(
                      id: m['id'] as String,
                      text: m['text'] as String,
                      done: m['done'] as bool,
                    );
                  })
                  .toList(),
            ),
          )
          .toList(),
      projects: projects
          .map(
            (r) => Project(
              id: r['id'] as String,
              title: r['title'] as String,
              area: r['area'] as String,
              description: r['description'] as String,
            ),
          )
          .toList(),
      plans: plans
          .map(
            (r) => PlanBlock(
              id: r['id'] as String,
              title: r['title'] as String,
              taskId: r['task_id'] as String?,
              start: DateTime.parse(r['start'] as String).toLocal(),
              minutes: r['minutes'] as int,
              area: r['area'] as String,
              fixed: r['fixed'] == 1,
            ),
          )
          .toList(),
      routines: routines
          .map(
            (r) => Routine(
              id: r['id'] as String,
              title: r['title'] as String,
              area: r['area'] as String,
              window: r['window'] as String,
              alternative: r['alternative'] as String,
              normal: r['normal'] as String,
              strong: r['strong'] as String,
              createdDay: r['created_day'] as String,
            ),
          )
          .toList(),
      routineRecords: records
          .map(
            (r) => RoutineRecord(
              routineId: r['routine_id'] as String,
              day: r['day'] as String,
              outcome: r['outcome'] as String,
              area: r['area'] as String,
            ),
          )
          .toList(),
      sessions: sessions
          .map(
            (r) => FocusSession(
              id: r['id'] as String,
              taskId: r['task_id'] as String,
              minutes: r['minutes'] as int,
              startedAt: DateTime.parse(r['started_at'] as String),
              runningSince: r['running_since'] == null
                  ? null
                  : DateTime.parse(r['running_since'] as String),
              seconds: r['seconds'] as int,
              area: r['area'] as String,
              outcome: r['outcome'] == null
                  ? null
                  : FocusOutcome.values.byName(r['outcome'] as String),
              notes: r['notes'] as String,
            ),
          )
          .toList(),
      areas: areas.map((r) => r['name'] as String).toList(),
      reminders: reminders
          .map(
            (r) => TaskReminder(
              id: r['id'] as String,
              taskId: r['task_id'] as String,
              scheduledAt: DateTime.parse(r['scheduled_at'] as String),
              deliveryStatus: r['delivery_status'] as String,
              origin: ReminderOrigin.values.byName(r['origin'] as String),
            ),
          )
          .toList(),
      suppressedTaskIds:
          suppressions.map((row) => row['task_id'] as String).toList()..sort(),
      quietHours: QuietHours(
        enabled: quietHours['enabled'] == 1,
        startMinute: quietHours['start_minute'] as int,
        endMinute: quietHours['end_minute'] as int,
      ),
      reminderDefault: ReminderDefault.values.byName(
        reminderPreference['default_option'] as String,
      ),
    );
  }

  Future<void> _upsert(String table, Map<String, Object?> values) async {
    final db = await database.open();
    await db.transaction((tx) async {
      final count = await tx.update(
        table,
        values,
        where: 'id = ?',
        whereArgs: [values['id']],
      );
      if (count == 0) await tx.insert(table, values);
    });
  }

  void _title(String title) {
    if (title.trim().isEmpty) throw ArgumentError('A title is required');
  }

  @override
  Future<void> addArea(String name) async {
    _title(name);
    await (await database.open()).insert('life_areas', {
      'name': name.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> saveProject(Project p) async {
    _title(p.title);
    await _upsert('projects', {
      'id': p.id,
      'title': p.title,
      'area': p.area,
      'description': p.description,
    });
  }

  @override
  Future<void> saveEntry(ProjectEntry e) async {
    _title(e.title);
    if (!['note', 'bug', 'idea', 'decision'].contains(e.kind)) {
      throw ArgumentError('Invalid entry kind');
    }
    final db = await database.open();
    if (e.relatedId != null) {
      final related = await db.query(
        'project_entries',
        where: 'id = ? AND project_id = ?',
        whereArgs: [e.relatedId, e.projectId],
      );
      if (related.isEmpty || e.relatedId == e.id) {
        throw ArgumentError('Choose another entry in this project');
      }
    }
    await _upsert('project_entries', {
      'id': e.id,
      'project_id': e.projectId,
      'title': e.title,
      'body': e.body,
      'kind': e.kind,
      'related_id': e.relatedId,
      'capture_id': e.captureId,
    });
  }

  @override
  Future<void> saveTask(Task t) async {
    _title(t.title);
    if (t.minutes < 1 || t.minutes > 1440) {
      throw ArgumentError('Invalid duration');
    }
    if (t.deadline != null &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t.deadline!)) {
      throw ArgumentError('Deadline must be date-only');
    }
    if (t.deadline != null) {
      final date = DateTime.tryParse(t.deadline!);
      if (date == null ||
          dayKey(date) != t.deadline ||
          date.year < 2000 ||
          date.isAfter(DateTime(2200))) {
        throw ArgumentError('Choose a valid calendar date');
      }
    }
    final values = <String, Object?>{
      'id': t.id,
      'title': t.title,
      'area': t.area,
      'project_id': t.projectId,
      'capture_id': t.captureId,
      'entry_id': t.entryId,
      'deadline': t.deadline,
      'minutes': t.minutes,
      'notes': t.notes,
      'status': t.status.name,
      'checklist': jsonEncode(
        t.checklist
            .map((c) => {'id': c.id, 'text': c.text, 'done': c.done})
            .toList(),
      ),
    };
    final db = await database.open();
    await db.transaction((tx) async {
      final old = await tx.query('tasks', where: 'id = ?', whereArgs: [t.id]);
      if (old.isEmpty) {
        await tx.insert('tasks', values);
      } else {
        if (old.single['capture_id'] != t.captureId ||
            old.single['entry_id'] != t.entryId) {
          throw StateError('Original capture cannot change');
        }
        await tx.update('tasks', values, where: 'id = ?', whereArgs: [t.id]);
      }
      // Finishing/cancelling a task pauses any active timer; it never invents a focus outcome.
      if (!t.active) {
        await tx.delete('reminders', where: 'task_id = ?', whereArgs: [t.id]);
        final active = await tx.query(
          'focus_sessions',
          where: 'task_id = ? AND outcome IS NULL',
          whereArgs: [t.id],
        );
        for (final r in active) {
          final since = r['running_since'] as String?;
          final seconds =
              (r['seconds'] as int) +
              (since == null
                  ? 0
                  : DateTime.now()
                        .toUtc()
                        .difference(DateTime.parse(since))
                        .inSeconds
                        .clamp(0, 2147483647));
          await tx.update(
            'focus_sessions',
            {'seconds': seconds, 'running_since': null},
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      }
    });
  }

  @override
  Future<void> saveReminder(TaskReminder reminder) async {
    if (!reminder.scheduledAt.isUtc) {
      throw ArgumentError('Reminder time must be UTC');
    }
    if (!reminder.scheduledAt.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Reminder time must be in the future');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      final task = await tx.query(
        'tasks',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [reminder.taskId],
      );
      if (task.isEmpty) throw ArgumentError('Task does not exist');
      if (task.single['status'] == TaskStatus.completed.name ||
          task.single['status'] == TaskStatus.cancelled.name) {
        throw ArgumentError('Inactive tasks cannot have reminders');
      }
      await tx.delete(
        'reminders',
        where: 'task_id = ?',
        whereArgs: [reminder.taskId],
      );
      await tx.delete(
        'reminder_suppressions',
        where: 'task_id = ?',
        whereArgs: [reminder.taskId],
      );
      await tx.insert('reminders', {
        'id': reminder.id,
        'task_id': reminder.taskId,
        'scheduled_at': reminder.scheduledAt.toIso8601String(),
        'origin': reminder.origin.name,
      });
    });
  }

  @override
  Future<void> removeReminder(String taskId) async {
    final db = await database.open();
    await db.transaction((tx) async {
      await tx.delete('reminders', where: 'task_id = ?', whereArgs: [taskId]);
      await tx.insert('reminder_suppressions', {
        'task_id': taskId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> recordReminderDelivery(
    TaskReminder reminder,
    String status,
  ) async {
    await (await database.open()).update(
      'reminders',
      {'delivery_status': status},
      where: 'id = ? AND scheduled_at = ?',
      whereArgs: [reminder.id, reminder.scheduledAt.toIso8601String()],
    );
  }

  @override
  Future<void> saveQuietHours(QuietHours quietHours) async {
    if (quietHours.startMinute < 0 ||
        quietHours.startMinute >= 1440 ||
        quietHours.endMinute < 0 ||
        quietHours.endMinute >= 1440) {
      throw ArgumentError('Quiet Hours must use valid times');
    }
    await (await database.open()).insert('quiet_hours', {
      'id': 1,
      'enabled': quietHours.enabled ? 1 : 0,
      'start_minute': quietHours.startMinute,
      'end_minute': quietHours.endMinute,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveReminderDefault(ReminderDefault value) async {
    await (await database.open()).insert('reminder_preferences', {
      'id': 1,
      'default_option': value.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> completeOnboarding({ReminderDefault? reminderDefault}) async {
    final db = await database.open();
    await db.transaction((tx) async {
      if (reminderDefault != null) {
        await tx.update('reminder_preferences', {
          'default_option': reminderDefault.name,
        }, where: 'id = 1');
      }
      await tx.update('workspace_setup', {'completed': 1}, where: 'id = 1');
    });
  }

  @override
  Future<void> clearLocalData() async {
    final db = await database.open();
    await db.transaction((tx) async {
      await tx.update('workspace_setup', {'completed': 0}, where: 'id = 1');
      for (final table in [
        'focus_sessions',
        'routine_records',
        'reminders',
        'reminder_suppressions',
        'plans',
        'tasks',
        'project_entries',
        'projects',
        'routines',
        'captures',
        'life_areas',
      ]) {
        await tx.delete(table);
      }
      for (final name in ['Work', 'Study', 'Health', 'Relationships', 'Rest']) {
        await tx.insert('life_areas', {'name': name});
      }
      await tx.update('quiet_hours', {
        'enabled': 0,
        'start_minute': 23 * 60,
        'end_minute': 7 * 60,
      }, where: 'id = 1');
      await tx.update('reminder_preferences', {
        'default_option': ReminderDefault.none.name,
      }, where: 'id = 1');
    });
  }

  @override
  Future<void> savePlan(PlanBlock p) async {
    _title(p.title);
    if (p.minutes < 1 || p.minutes > 1440) {
      throw ArgumentError('Invalid duration');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      final values = {
        'id': p.id,
        'title': p.title,
        'task_id': p.taskId,
        'start': p.start.toUtc().toIso8601String(),
        'minutes': p.minutes,
        'area': p.area,
        'fixed': p.fixed ? 1 : 0,
      };
      final count = await tx.update(
        'plans',
        values,
        where: 'id = ?',
        whereArgs: [p.id],
      );
      if (count == 0) await tx.insert('plans', values);
      if (p.taskId == null) return;

      final task = await tx.query(
        'tasks',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [p.taskId],
      );
      final existing = await tx.query(
        'reminders',
        columns: ['id'],
        where: 'task_id = ?',
        whereArgs: [p.taskId],
      );
      final suppressed = await tx.query(
        'reminder_suppressions',
        where: 'task_id = ?',
        whereArgs: [p.taskId],
      );
      final preference = (await tx.query(
        'reminder_preferences',
        where: 'id = 1',
      )).single;
      final option = ReminderDefault.values.byName(
        preference['default_option'] as String,
      );
      final scheduledAt = defaultReminderTime(option, p.start);
      if (task.isNotEmpty &&
          task.single['status'] != TaskStatus.completed.name &&
          task.single['status'] != TaskStatus.cancelled.name &&
          existing.isEmpty &&
          suppressed.isEmpty &&
          scheduledAt != null &&
          scheduledAt.isAfter(DateTime.now().toUtc())) {
        await tx.insert('reminders', {
          'id': newId(),
          'task_id': p.taskId,
          'scheduled_at': scheduledAt.toIso8601String(),
          'origin': ReminderOrigin.defaulted.name,
        });
      }
    });
  }

  @override
  Future<void> removePlan(String id) async =>
      (await database.open()).delete('plans', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> saveRoutine(Routine r) async {
    _title(r.title);
    await _upsert('routines', {
      'id': r.id,
      'title': r.title,
      'area': r.area,
      'window': r.window,
      'alternative': r.alternative,
      'normal': r.normal,
      'strong': r.strong,
      'created_day': r.createdDay,
    });
  }

  @override
  Future<void> recordRoutine(RoutineRecord r) async {
    if (![
      'done',
      'smaller',
      'strong',
      'later',
      'skipped',
    ].contains(r.outcome)) {
      throw ArgumentError('Invalid outcome');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      final routine = (await tx.query(
        'routines',
        where: 'id = ?',
        whereArgs: [r.routineId],
      )).single;
      if (r.outcome == 'strong' &&
          (routine['strong'] as String).trim().isEmpty) {
        throw ArgumentError('Define a Strong option first');
      }
      await tx.insert('routine_records', {
        'routine_id': r.routineId,
        'area': routine['area'],
        'day': r.day,
        'outcome': r.outcome,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> saveSession(FocusSession s) async {
    if (s.minutes < 1 || s.minutes > 1440 || s.seconds < 0) {
      throw ArgumentError('Invalid focus duration');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      final tasks = await tx.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [s.taskId],
      );
      if (tasks.isEmpty) throw StateError('Task missing');
      final previous = await tx.query(
        'focus_sessions',
        where: 'id = ?',
        whereArgs: [s.id],
      );
      if (previous.isNotEmpty && previous.single['task_id'] != s.taskId) {
        throw StateError('Session task cannot change');
      }
      if (previous.isNotEmpty && previous.single['outcome'] != null) {
        throw StateError('Session already ended');
      }
      if (s.runningSince != null &&
          !['open', 'inProgress'].contains(tasks.single['status'])) {
        throw StateError('Reopen the task before focusing');
      }
      final values = <String, Object?>{
        'id': s.id,
        'task_id': s.taskId,
        'area': previous.isEmpty
            ? tasks.single['area']
            : previous.single['area'],
        'minutes': s.minutes,
        'started_at': s.startedAt.toUtc().toIso8601String(),
        'running_since': s.runningSince?.toUtc().toIso8601String(),
        'seconds': s.seconds,
        'outcome': s.outcome?.name,
        'notes': s.notes,
      };
      if (previous.isEmpty) {
        await tx.insert('focus_sessions', values);
      } else {
        await tx.update(
          'focus_sessions',
          values,
          where: 'id = ?',
          whereArgs: [s.id],
        );
      }
      if (s.outcome == FocusOutcome.completed) {
        await tx.delete(
          'reminders',
          where: 'task_id = ?',
          whereArgs: [s.taskId],
        );
        await tx.update(
          'tasks',
          {'status': TaskStatus.completed.name},
          where: 'id = ? AND status != ?',
          whereArgs: [s.taskId, TaskStatus.cancelled.name],
        );
      } else if (s.outcome == null) {
        await tx.update(
          'tasks',
          {'status': TaskStatus.inProgress.name},
          where: 'id = ? AND status = ?',
          whereArgs: [s.taskId, TaskStatus.open.name],
        );
      }
    });
  }
}
