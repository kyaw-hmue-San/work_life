import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../captures/capture_repository.dart';
import '../captures/capture.dart';
import 'records.dart';
import 'reminder_defaults.dart';
import 'local_restore_data.dart';
import '../ai/ai_proposals.dart';
import '../ai/day_context_builder.dart';

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
  Future<void> saveRecurringSchedule(RecurringSchedule schedule);
  Future<void> saveRecurringSchedules(List<RecurringSchedule> schedules);
  Future<void> removeRecurringSchedule(String id);
  Future<void> saveScheduleException(ScheduleException exception);
  Future<void> savePlanningPreferences(PlanningPreferences preferences);
  Future<void> saveRoutine(Routine routine);
  Future<void> recordRoutine(RoutineRecord record);
  Future<void> saveSession(FocusSession session);
  Future<void> addArea(String name);
  Future<void> applyProjectProposal(
    AiProjectProposal proposal, {
    required String operationId,
    String? captureId,
    String? targetProjectId,
  });
  Future<void> applyScheduleProposal(
    AiScheduleProposal proposal, {
    required String operationId,
  });
  Future<void> applyCaptureProposal(
    AiCaptureProposal proposal, {
    required String operationId,
    String? captureId,
  });
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
    final recurringRows = await tx.query('recurring_schedules');
    final exceptionRows = await tx.query('schedule_exceptions');
    final preference = (await tx.query(
      'planning_preferences',
      where: 'id = 1',
    )).single;
    return WorkspaceData(
      onboardingCompleted: setup['completed'] == 1,
      recurringSchedules: recurringRows
          .map(
            (r) => RecurringSchedule(
              id: r['id'] as String,
              title: r['title'] as String,
              type: RecurringScheduleType.values.byName(r['type'] as String),
              weekday: r['weekday'] as int,
              startTime: r['start_time'] as String,
              endTime: r['end_time'] as String,
              startDate: r['start_date'] as String,
              endDate: r['end_date'] as String?,
              location: r['location'] as String,
              notes: r['notes'] as String,
              fixed: r['fixed'] == 1,
            ),
          )
          .toList(),
      scheduleExceptions: exceptionRows
          .map(
            (r) => ScheduleException(
              scheduleId: r['schedule_id'] as String,
              day: r['day'] as String,
              cancelled: r['kind'] == 'cancelled',
              startTime: r['start_time'] as String?,
              endTime: r['end_time'] as String?,
              movedToDate: r['moved_to_date'] as String?,
            ),
          )
          .toList(),
      planningPreferences: PlanningPreferences(
        wakeTime: preference['wake_time'] as String,
        bedTime: preference['bed_time'] as String,
        transitionMinutes: preference['transition_minutes'] as int,
        breakMinutes: preference['break_minutes'] as int,
        exercisePeriod: preference['exercise_period'] as String,
        avoidFocusAfter: preference['avoid_focus_after'] as String,
        maxFocusMinutes: preference['max_focus_minutes'] as int,
        style: preference['style'] as String,
        breakfastWindow: preference['breakfast_window'] as String,
        lunchWindow: preference['lunch_window'] as String,
        dinnerWindow: preference['dinner_window'] as String,
      ),
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
              priority: TaskPriority.values.byName(
                (r['priority'] as String?) ?? TaskPriority.medium.name,
              ),
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
              basis: ReminderBasis.values.byName(
                (r['basis'] as String?) ?? ReminderBasis.explicit.name,
              ),
              recurrence: ReminderRecurrence.values.byName(
                (r['recurrence'] as String?) ?? ReminderRecurrence.none.name,
              ),
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

  Task _taskFromRow(Map<String, Object?> row) => Task(
    id: row['id'] as String,
    title: row['title'] as String,
    area: row['area'] as String,
    projectId: row['project_id'] as String?,
    captureId: row['capture_id'] as String?,
    entryId: row['entry_id'] as String?,
    deadline: row['deadline'] as String?,
    minutes: row['minutes'] as int,
    notes: row['notes'] as String,
    priority: TaskPriority.values.byName(
      (row['priority'] as String?) ?? TaskPriority.medium.name,
    ),
    status: TaskStatus.values.byName(row['status'] as String),
    checklist: (jsonDecode(row['checklist'] as String) as List<dynamic>).map((
      dynamic item,
    ) {
      final value = item as Map<String, dynamic>;
      return ChecklistItem(
        id: value['id'] as String,
        text: value['text'] as String,
        done: value['done'] as bool,
      );
    }).toList(),
  );

  @override
  Future<void> addArea(String name) async {
    _title(name);
    await (await database.open()).insert('life_areas', {
      'name': name.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<String> _approvedProposalArea(
    DatabaseExecutor tx,
    String? requested, {
    bool allowCreate = false,
  }) async {
    final candidate = requested?.trim();
    final wanted = candidate == null || candidate.isEmpty ? 'Work' : candidate;
    _title(wanted);
    final rows = await tx.query('life_areas', columns: ['name']);
    for (final row in rows) {
      final existing = row['name']! as String;
      if (existing.toLowerCase() == wanted.toLowerCase()) return existing;
    }
    if (!allowCreate) {
      throw ArgumentError(
        'Review and approve the suggested Life Area before saving.',
      );
    }
    await tx.insert('life_areas', {'name': wanted});
    return wanted;
  }

  @override
  Future<void> applyCaptureProposal(
    AiCaptureProposal proposal, {
    required String operationId,
    String? captureId,
  }) async {
    if (proposal.kind == AiCaptureKind.project ||
        proposal.kind == AiCaptureKind.planningRequest) {
      throw ArgumentError('Use the project or planner approval workflow');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      if ((await tx.query(
        'ai_operations',
        where: 'id = ?',
        whereArgs: [operationId],
      )).isNotEmpty) {
        return;
      }
      final selectedArea = await _approvedProposalArea(
        tx,
        proposal.task?.area ?? proposal.routine?.area,
        allowCreate: proposal.createArea,
      );
      if (proposal.routine case final routine?) {
        _title(routine.title);
        _title(routine.minimum);
        await tx.insert('routines', {
          'id': newId(),
          'title': routine.title.trim(),
          'area': selectedArea,
          'window': routine.window.trim(),
          'alternative': routine.minimum.trim(),
          'normal': routine.normal.trim(),
          'strong': routine.strong.trim(),
          'created_day': dayKey(DateTime.now()),
        });
      } else if (proposal.task case final task?) {
        _title(task.title);
        if (!TaskPriority.values.any((value) => value.name == task.priority) ||
            task.minutes < 1 ||
            task.minutes > 1440) {
          throw ArgumentError('Invalid proposed task');
        }
        final taskId = newId();
        await tx.insert('tasks', {
          'id': taskId,
          'title': task.title.trim(),
          'area': selectedArea,
          'project_id': null,
          'capture_id': captureId,
          'entry_id': null,
          'deadline': task.deadline,
          'minutes': task.minutes,
          'notes': '',
          'priority': task.priority,
          'status': TaskStatus.open.name,
          'checklist': jsonEncode(
            task.checklist
                .map((text) => {'id': newId(), 'text': text, 'done': false})
                .toList(),
          ),
        });
        if (task.reminder != null) {
          final reminderAt = DateTime.tryParse(task.reminder!)?.toUtc();
          if (reminderAt == null ||
              !reminderAt.isAfter(DateTime.now().toUtc())) {
            throw ArgumentError('Reminder must be in the future');
          }
          await tx.insert('reminders', {
            'id': newId(),
            'task_id': taskId,
            'scheduled_at': reminderAt.toIso8601String(),
            'delivery_status': 'pending',
            'origin': ReminderOrigin.explicit.name,
            'basis': ReminderBasis.explicit.name,
            'recurrence': ReminderRecurrence.none.name,
          });
        }
      } else {
        throw ArgumentError('Capture proposal has no content');
      }
      await tx.insert('ai_operations', {
        'id': operationId,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  @override
  Future<void> applyProjectProposal(
    AiProjectProposal proposal, {
    required String operationId,
    String? captureId,
    String? targetProjectId,
  }) async {
    _title(proposal.title);
    if (proposal.tasks.where((task) => task.included).isEmpty) {
      throw ArgumentError('Choose at least one proposed task');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      final duplicate = await tx.query(
        'ai_operations',
        where: 'id = ?',
        whereArgs: [operationId],
      );
      if (duplicate.isNotEmpty) return;
      final area = await _approvedProposalArea(
        tx,
        proposal.area,
        allowCreate: proposal.createArea,
      );
      final projectId = targetProjectId ?? newId();
      if (targetProjectId == null) {
        await tx.insert('projects', {
          'id': projectId,
          'title': proposal.title.trim(),
          'area': area,
          'description': proposal.description.trim().isEmpty
              ? 'Created from an approved AI proposal.'
              : proposal.description.trim(),
        });
      } else {
        final existingProject = await tx.query(
          'projects',
          where: 'id = ?',
          whereArgs: [targetProjectId],
        );
        if (existingProject.isEmpty) throw ArgumentError('Project missing');
        await tx.update(
          'projects',
          {
            'title': proposal.title.trim(),
            'area': area,
            'description': proposal.description.trim(),
          },
          where: 'id = ?',
          whereArgs: [targetProjectId],
        );
      }
      var first = true;
      for (final item in proposal.tasks.where((task) => task.included)) {
        _title(item.title);
        if (!TaskPriority.values.any((value) => value.name == item.priority)) {
          throw ArgumentError('Invalid priority');
        }
        final requestedTaskArea = item.area?.trim();
        final taskArea =
            requestedTaskArea == null ||
                requestedTaskArea.isEmpty ||
                requestedTaskArea.toLowerCase() == area.toLowerCase()
            ? area
            : await _approvedProposalArea(tx, requestedTaskArea);
        final checklist = jsonEncode(
          item.checklist
              .map((text) => {'id': newId(), 'text': text, 'done': false})
              .toList(),
        );
        if (item.change == AiProjectChange.remove) {
          if (item.taskId == null || targetProjectId == null) {
            throw ArgumentError('Only an existing project task can be removed');
          }
          final changed = await tx.update(
            'tasks',
            {'project_id': null, 'status': TaskStatus.cancelled.name},
            where: 'id = ? AND project_id = ?',
            whereArgs: [item.taskId, targetProjectId],
          );
          if (changed == 0) {
            throw ArgumentError('Proposed task is not in this project');
          }
          await tx.delete(
            'reminders',
            where: 'task_id = ?',
            whereArgs: [item.taskId],
          );
          first = false;
          continue;
        }
        if (item.taskId != null && targetProjectId != null) {
          final existingTask = await tx.query(
            'tasks',
            where: 'id = ? AND project_id = ?',
            whereArgs: [item.taskId, targetProjectId],
          );
          if (existingTask.isEmpty) {
            throw ArgumentError('Proposed task is not in this project');
          }
          await tx.update(
            'tasks',
            {
              'title': item.title.trim(),
              'area': taskArea,
              'deadline': item.deadline,
              'minutes': item.minutes,
              'priority': item.priority,
              if (item.checklist.isNotEmpty) 'checklist': checklist,
            },
            where: 'id = ?',
            whereArgs: [item.taskId],
          );
        } else {
          await tx.insert('tasks', {
            'id': newId(),
            'title': item.title.trim(),
            'area': taskArea,
            'project_id': projectId,
            'capture_id': first ? captureId : null,
            'entry_id': null,
            'deadline': item.deadline,
            'minutes': item.minutes,
            'notes': '',
            'priority': item.priority,
            'status': TaskStatus.open.name,
            'checklist': checklist,
          });
        }
        first = false;
      }
      await tx.insert('ai_operations', {
        'id': operationId,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  @override
  Future<void> applyScheduleProposal(
    AiScheduleProposal proposal, {
    required String operationId,
  }) async {
    final chosen = proposal.events.where((event) => event.included).toList();
    if (chosen.isEmpty) throw ArgumentError('Choose at least one time block');
    final db = await database.open();
    await db.transaction((tx) async {
      final duplicate = await tx.query(
        'ai_operations',
        where: 'id = ?',
        whereArgs: [operationId],
      );
      if (duplicate.isNotEmpty) return;
      if (proposal.baseFingerprints.isNotEmpty) {
        final current = await _readWorkspace(tx);
        const builder = DayContextBuilder();
        for (final entry in proposal.baseFingerprints.entries) {
          final day = DateTime.tryParse(entry.key);
          if (day == null ||
              dayKey(day) != entry.key ||
              builder.fingerprint(current, day) != entry.value) {
            throw const StaleScheduleProposalException();
          }
        }
      }
      final existingRows = await tx.query('plans');
      final existingPlans = existingRows
          .map(
            (row) => PlanBlock(
              id: row['id'] as String,
              title: row['title'] as String,
              taskId: row['task_id'] as String?,
              start: DateTime.parse(row['start'] as String).toLocal(),
              minutes: row['minutes'] as int,
              area: row['area'] as String,
              fixed: row['fixed'] == 1,
            ),
          )
          .toList();
      final proposed = <PlanBlock>[];
      final removals = <String>[];
      for (final event in chosen) {
        if (event.operation == 'unchanged') continue;
        if (event.operation == 'remove') {
          if (event.planId == null) {
            throw ArgumentError('A removed block needs its Planner ID');
          }
          final old = await tx.query(
            'plans',
            where: 'id = ?',
            whereArgs: [event.planId],
          );
          if (old.isEmpty || old.single['fixed'] == 1) {
            throw ArgumentError(
              'Locked Planner blocks cannot be removed by AI',
            );
          }
          removals.add(event.planId!);
          continue;
        }
        if (!{'add', 'move', 'change'}.contains(event.operation)) {
          throw ArgumentError('Unsupported plan change');
        }
        PlanBlock? existing;
        if (event.operation == 'add') {
          if (event.planId != null) {
            throw ArgumentError('A new block cannot reuse a Planner ID');
          }
        } else {
          if (event.planId == null) {
            throw ArgumentError('Moved or changed blocks need a Planner ID');
          }
          final matches = existingPlans.where((p) => p.id == event.planId);
          if (matches.isEmpty || matches.single.fixed) {
            throw ArgumentError('AI cannot change a missing or locked block');
          }
          existing = matches.single;
          if (event.taskId != null && event.taskId != existing.taskId) {
            throw ArgumentError('AI cannot change a Planner block task link');
          }
        }
        _title(event.title);
        final start = _proposalStart(event);
        final end = _proposalEnd(event, start);
        final taskId = event.taskId ?? existing?.taskId;
        String area = event.area?.trim().isNotEmpty == true
            ? event.area!.trim()
            : existing?.area ?? 'Work';
        if (taskId != null) {
          final tasks = await tx.query(
            'tasks',
            where: 'id = ? AND status IN (?, ?)',
            whereArgs: [
              taskId,
              TaskStatus.open.name,
              TaskStatus.inProgress.name,
            ],
          );
          if (tasks.isEmpty) {
            throw ArgumentError('Proposed task is unavailable');
          }
          final deadline = tasks.single['deadline'] as String?;
          if (deadline != null && dayKey(start).compareTo(deadline) > 0) {
            throw ArgumentError('A task cannot be planned after its deadline');
          }
          area = tasks.single['area'] as String;
        }
        final block = PlanBlock(
          id: event.planId ?? newId(),
          title: event.title.trim(),
          taskId: taskId,
          start: start,
          minutes: end.difference(start).inMinutes,
          area: area,
          fixed: event.locked,
        );
        final startMinute = start.hour * 60 + start.minute,
            endMinute = end
                .difference(DateTime(start.year, start.month, start.day))
                .inMinutes;
        final pref = (await tx.query(
          'planning_preferences',
          where: 'id = 1',
        )).single;
        int minuteOf(String text) {
          final p = text.split(':');
          return int.parse(p[0]) * 60 + int.parse(p[1]);
        }

        if ({'task', 'focus'}.contains(event.kind) &&
            endMinute > minuteOf(pref['avoid_focus_after'] as String)) {
          throw ArgumentError(
            'Focused work exceeds your preferred work cutoff',
          );
        }
        final bed = minuteOf(pref['bed_time'] as String);
        final wake = minuteOf(pref['wake_time'] as String);
        if (startMinute < wake || endMinute > bed) {
          throw ArgumentError(
            'A proposed block falls outside your preferred waking hours',
          );
        }
        final day = DateTime(start.year, start.month, start.day);
        final key = dayKey(day);
        final dateExceptions = await tx.query(
          'schedule_exceptions',
          where: 'day = ? OR moved_to_date = ?',
          whereArgs: [key, key],
        );
        final allSchedules = await tx.query('recurring_schedules');
        final weekdayRows = allSchedules.where((row) {
          final start = row['start_date'] as String,
              end = row['end_date'] as String?;
          if (key.compareTo(start) < 0 ||
              (end != null && key.compareTo(end) > 0)) {
            return false;
          }
          final moved = dateExceptions.any(
            (exception) =>
                exception['schedule_id'] == row['id'] &&
                exception['moved_to_date'] == key &&
                exception['kind'] != 'cancelled',
          );
          final regular =
              row['weekday'] == day.weekday &&
              !dateExceptions.any(
                (exception) =>
                    exception['schedule_id'] == row['id'] &&
                    exception['day'] == key &&
                    (exception['kind'] == 'cancelled' ||
                        exception['moved_to_date'] != null),
              );
          return moved || regular;
        }).toList();
        for (final row in weekdayRows) {
          final exceptions = dateExceptions
              .where(
                (e) =>
                    e['schedule_id'] == row['id'] &&
                    (e['day'] == key || e['moved_to_date'] == key),
              )
              .toList();
          final exception = exceptions.isEmpty ? null : exceptions.first;
          if (exception?['kind'] == 'cancelled' ||
              (exception?['moved_to_date'] != null &&
                  exception?['day'] == key)) {
            continue;
          }
          final s = minuteOf(
            (exception == null || exception['start_time'] == null
                    ? row['start_time']
                    : exception['start_time'])
                as String,
          );
          final e = minuteOf(
            (exception == null || exception['end_time'] == null
                    ? row['end_time']
                    : exception['end_time'])
                as String,
          );
          final buffer = pref['transition_minutes'] as int;
          if (startMinute < e + buffer && endMinute + buffer > s) {
            throw ArgumentError(
              'A proposed block overlaps a recurring fixed commitment',
            );
          }
        }
        if (proposed.any((other) => other.overlaps(block))) {
          throw ArgumentError('Proposed time blocks overlap');
        }
        proposed.add(block);
      }
      final changedIds = proposed.map((block) => block.id).toSet();
      final removedIds = removals.toSet();
      final retained = existingPlans
          .where(
            (block) =>
                !changedIds.contains(block.id) &&
                !removedIds.contains(block.id),
          )
          .toList();
      final planning = (await tx.query(
        'planning_preferences',
        where: 'id = 1',
      )).single;
      int clockMinute(String value) {
        final p = value.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      final dayKeys = proposed.map((p) => dayKey(p.start)).toSet();
      for (final key in dayKeys) {
        final date = DateTime.parse(key);
        final dayBlocks = proposed
            .where((p) => dayKey(p.start) == key)
            .toList();
        final retainedBlocks = retained.where((p) => p.occursOn(date)).toList();
        final exceptions = await tx.query(
          'schedule_exceptions',
          where: 'day = ? OR moved_to_date = ?',
          whereArgs: [key, key],
        );
        final allRecurrences = await tx.query('recurring_schedules');
        final recurring = allRecurrences.where((item) {
          final start = item['start_date'] as String,
              end = item['end_date'] as String?;
          if (key.compareTo(start) < 0 ||
              (end != null && key.compareTo(end) > 0)) {
            return false;
          }
          final moved = exceptions.any(
            (e) =>
                e['schedule_id'] == item['id'] &&
                e['moved_to_date'] == key &&
                e['kind'] != 'cancelled',
          );
          final regular =
              item['weekday'] == date.weekday &&
              !exceptions.any(
                (e) =>
                    e['schedule_id'] == item['id'] &&
                    e['day'] == key &&
                    (e['kind'] == 'cancelled' || e['moved_to_date'] != null),
              );
          return moved || regular;
        }).toList();
        var recurringMinutes = 0, recurringCount = 0;
        for (final item in recurring) {
          final occurrenceExceptions = exceptions
              .where(
                (e) =>
                    e['schedule_id'] == item['id'] &&
                    (e['day'] == key || e['moved_to_date'] == key),
              )
              .toList();
          final exception = occurrenceExceptions.isEmpty
              ? null
              : occurrenceExceptions.first;
          if (exception?['kind'] == 'cancelled' ||
              (exception?['moved_to_date'] != null &&
                  exception?['day'] == key)) {
            continue;
          }
          final start = clockMinute(
            (exception == null || exception['start_time'] == null
                    ? item['start_time']
                    : exception['start_time'])
                as String,
          );
          final end = clockMinute(
            (exception == null || exception['end_time'] == null
                    ? item['end_time']
                    : exception['end_time'])
                as String,
          );
          recurringMinutes += end - start;
          recurringCount++;
        }
        final occupied =
            retainedBlocks.fold<int>(0, (sum, p) => sum + p.minutes) +
            recurringMinutes;
        final waking =
            (clockMinute(planning['bed_time'] as String) -
                    clockMinute(planning['wake_time'] as String))
                .clamp(0, 1440);
        final buffer =
            (retainedBlocks.length + recurringCount + dayBlocks.length) *
            (planning['transition_minutes'] as int);
        final available = (waking - occupied - buffer).clamp(0, 1440);
        final proposedMinutes = dayBlocks.fold<int>(
          0,
          (sum, p) => sum + p.minutes,
        );
        if (proposedMinutes > available) {
          throw ArgumentError(
            'This day exceeds your available capacity. Remove or move some flexible blocks.',
          );
        }
      }
      for (final block in proposed) {
        final sameDay = retained.where(
          (item) => item.occursOn(
            DateTime(block.start.year, block.start.month, block.start.day),
          ),
        );
        final transition = Duration(
          minutes: planning['transition_minutes'] as int,
        );
        if (sameDay.any(
          (item) =>
              item.start.isBefore(block.end.add(transition)) &&
              item.end.add(transition).isAfter(block.start),
        )) {
          throw ArgumentError('A proposed block overlaps a fixed event');
        }
        await tx.insert('life_areas', {
          'name': block.area,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final values = <String, Object?>{
          'id': block.id,
          'title': block.title,
          'task_id': block.taskId,
          'start': block.start.toUtc().toIso8601String(),
          'minutes': block.minutes,
          'area': block.area,
          'fixed': block.fixed ? 1 : 0,
        };
        final updated = await tx.update(
          'plans',
          values,
          where: 'id = ? AND fixed = 0',
          whereArgs: [block.id],
        );
        if (updated == 0) await tx.insert('plans', values);
        if (block.taskId != null) {
          await _saveDefaultReminder(tx, block.taskId!, block.start);
        }
      }
      for (final id in removals) {
        await tx.delete(
          'plans',
          where: 'id = ? AND fixed = 0',
          whereArgs: [id],
        );
      }
      await tx.insert('ai_operations', {
        'id': operationId,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  DateTime _proposalStart(AiScheduleEvent event) {
    final date = event.date;
    final time = event.start;
    if (date == null || time == null) {
      throw ArgumentError('Every selected block needs a date and start time');
    }
    final parts = time.split(':');
    final day = DateTime.tryParse(date);
    if (day == null || dayKey(day) != date || parts.length != 2) {
      throw ArgumentError('Invalid proposed date or time');
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw ArgumentError('Invalid proposed time');
    }
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  DateTime _proposalEnd(AiScheduleEvent event, DateTime start) {
    final value = event.end;
    if (value == null) return start.add(const Duration(minutes: 25));
    final parts = value.split(':');
    if (parts.length != 2) throw ArgumentError('Invalid proposed end time');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw ArgumentError('Invalid proposed end time');
    }
    var end = DateTime(start.year, start.month, start.day, hour, minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return end;
  }

  Future<void> _saveDefaultReminder(
    Transaction tx,
    String taskId,
    DateTime start,
  ) async {
    final existing = await tx.query(
      'reminders',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    final suppressed = await tx.query(
      'reminder_suppressions',
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    final preference = (await tx.query(
      'reminder_preferences',
      where: 'id = 1',
    )).single;
    final scheduledAt = defaultReminderTime(
      ReminderDefault.values.byName(preference['default_option'] as String),
      start,
    );
    if (existing.isEmpty &&
        suppressed.isEmpty &&
        scheduledAt != null &&
        scheduledAt.isAfter(DateTime.now().toUtc())) {
      await tx.insert('reminders', {
        'id': newId(),
        'task_id': taskId,
        'scheduled_at': scheduledAt.toIso8601String(),
        'origin': ReminderOrigin.defaulted.name,
      });
    }
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
      'priority': t.priority.name,
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
      } else {
        await _reconcileDueReminder(tx, t);
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
        'basis': reminder.basis.name,
        'recurrence': reminder.recurrence.name,
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
    final db = await database.open();
    await db.transaction((tx) async {
      await tx.insert('reminder_preferences', {
        'id': 1,
        'default_option': value.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final tasks = await tx.query(
        'tasks',
        where: "deadline IS NOT NULL AND status IN ('open', 'inProgress')",
      );
      for (final row in tasks) {
        await _reconcileDueReminder(tx, _taskFromRow(row), option: value);
      }
    });
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
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS planning_preference_changes (
        id INTEGER PRIMARY KEY CHECK(id = 1), fields TEXT NOT NULL
      )''',
      );
      await tx.delete('planning_preference_changes');
      await tx.update('workspace_setup', {'completed': 0}, where: 'id = 1');
      await tx.delete('recurring_schedules');
      await tx.update('planning_preferences', {
        'wake_time': '07:30',
        'bed_time': '23:00',
        'transition_minutes': 15,
        'break_minutes': 15,
        'exercise_period': 'flexible',
        'avoid_focus_after': '21:30',
        'max_focus_minutes': 90,
        'style': 'balanced',
        'breakfast_window': '07:00-09:00',
        'lunch_window': '12:00-14:00',
        'dinner_window': '18:00-20:00',
      }, where: 'id = 1');
      for (final table in [
        'focus_sessions',
        'routine_records',
        'reminders',
        'reminder_suppressions',
        'plans',
        'schedule_exceptions',
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

  Future<void> replaceLocalData(LocalRestoreData data) async {
    final db = await database.open();
    await db.transaction((tx) async {
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS planning_preference_changes (
        id INTEGER PRIMARY KEY CHECK(id = 1), fields TEXT NOT NULL
      )''',
      );
      await tx.delete('planning_preference_changes');
      await tx.update('workspace_setup', {'completed': 0}, where: 'id = 1');
      for (final table in [
        'focus_sessions',
        'routine_records',
        'reminders',
        'reminder_suppressions',
        'plans',
        'schedule_exceptions',
        'tasks',
        'project_entries',
        'projects',
        'routines',
        'recurring_schedules',
        'captures',
        'life_areas',
      ]) {
        await tx.delete(table);
      }
      for (final area in data.areas) {
        await tx.insert('life_areas', {'name': area});
      }
      for (final capture in data.captures) {
        await tx.insert('captures', {
          'id': capture.id,
          'original_text': capture.originalText,
          'created_at': capture.createdAt.toUtc().toIso8601String(),
        });
      }
      for (final project in data.projects) {
        await tx.insert('projects', {
          'id': project.id,
          'title': project.title,
          'area': project.area,
          'description': project.description,
        });
      }
      for (final entry in data.entries) {
        await tx.insert('project_entries', {
          'id': entry.id,
          'project_id': entry.projectId,
          'title': entry.title,
          'body': entry.body,
          'kind': entry.kind,
          'related_id': null,
          'capture_id': entry.captureId,
        });
      }
      for (final entry in data.entries.where(
        (entry) => entry.relatedId != null,
      )) {
        await tx.update(
          'project_entries',
          {'related_id': entry.relatedId},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
      for (final task in data.tasks) {
        await tx.insert('tasks', {
          'id': task.id,
          'title': task.title,
          'area': task.area,
          'project_id': task.projectId,
          'capture_id': task.captureId,
          'entry_id': task.entryId,
          'deadline': task.deadline,
          'minutes': task.minutes,
          'notes': task.notes,
          'priority': task.priority.name,
          'status': task.status.name,
          'checklist': jsonEncode(
            task.checklist
                .map(
                  (item) => {
                    'id': item.id,
                    'text': item.text,
                    'done': item.done,
                  },
                )
                .toList(),
          ),
        });
      }
      for (final plan in data.plans) {
        await tx.insert('plans', {
          'id': plan.id,
          'title': plan.title,
          'task_id': plan.taskId,
          'start': plan.start.toUtc().toIso8601String(),
          'minutes': plan.minutes,
          'area': plan.area,
          'fixed': plan.fixed ? 1 : 0,
        });
      }
      for (final schedule in data.recurringSchedules) {
        _validateRecurringSchedule(schedule);
        await tx.insert('recurring_schedules', {
          'id': schedule.id,
          'title': schedule.title,
          'type': schedule.type.name,
          'weekday': schedule.weekday,
          'start_time': schedule.startTime,
          'end_time': schedule.endTime,
          'start_date': schedule.startDate,
          'end_date': schedule.endDate,
          'location': schedule.location,
          'notes': schedule.notes,
          'fixed': schedule.fixed ? 1 : 0,
        });
      }
      for (final exception in data.scheduleExceptions) {
        await tx.insert('schedule_exceptions', {
          'schedule_id': exception.scheduleId,
          'day': exception.day,
          'kind': exception.cancelled ? 'cancelled' : 'moved',
          'start_time': exception.startTime,
          'end_time': exception.endTime,
          'moved_to_date': exception.movedToDate,
        });
      }
      for (final routine in data.routines) {
        await tx.insert('routines', {
          'id': routine.id,
          'title': routine.title,
          'area': routine.area,
          'window': routine.window,
          'alternative': routine.alternative,
          'normal': routine.normal,
          'strong': routine.strong,
          'created_day': routine.createdDay,
        });
      }
      for (final record in data.routineRecords) {
        await tx.insert('routine_records', {
          'routine_id': record.routineId,
          'day': record.day,
          'outcome': record.outcome,
          'area': record.area,
        });
      }
      for (final session in data.sessions) {
        await tx.insert('focus_sessions', {
          'id': session.id,
          'task_id': session.taskId,
          'minutes': session.minutes,
          'started_at': session.startedAt.toUtc().toIso8601String(),
          'running_since': session.runningSince?.toUtc().toIso8601String(),
          'seconds': session.seconds,
          'outcome': session.outcome?.name,
          'notes': session.notes,
          'area': session.area,
        });
      }
      for (final reminder in data.reminders) {
        await tx.insert('reminders', {
          'id': reminder.id,
          'task_id': reminder.taskId,
          'scheduled_at': reminder.scheduledAt.toUtc().toIso8601String(),
          'delivery_status': 'pending',
          'origin': reminder.origin.name,
          'basis': reminder.basis.name,
          'recurrence': reminder.recurrence.name,
        });
      }
      for (final taskId in data.suppressedTaskIds) {
        await tx.insert('reminder_suppressions', {'task_id': taskId});
      }
      final quiet = data.quietHours;
      if (quiet != null) {
        await tx.update('quiet_hours', {
          'enabled': quiet.enabled ? 1 : 0,
          'start_minute': quiet.startMinute,
          'end_minute': quiet.endMinute,
        }, where: 'id = 1');
      }
      if (data.reminderDefault case final value?) {
        await tx.update('reminder_preferences', {
          'default_option': value.name,
        }, where: 'id = 1');
      }
      if (data.planningPreferences case final value?) {
        await tx.update('planning_preferences', {
          'wake_time': value.wakeTime,
          'bed_time': value.bedTime,
          'transition_minutes': value.transitionMinutes,
          'break_minutes': value.breakMinutes,
          'exercise_period': value.exercisePeriod,
          'avoid_focus_after': value.avoidFocusAfter,
          'max_focus_minutes': value.maxFocusMinutes,
          'style': value.style,
          'breakfast_window': value.breakfastWindow,
          'lunch_window': value.lunchWindow,
          'dinner_window': value.dinnerWindow,
        }, where: 'id = 1');
      }
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
          'basis': ReminderBasis.plannedTime.name,
          'recurrence': ReminderRecurrence.none.name,
        });
      }
    });
  }

  @override
  Future<void> saveRecurringSchedule(RecurringSchedule schedule) async {
    await saveRecurringSchedules([schedule]);
  }

  @override
  Future<void> saveRecurringSchedules(List<RecurringSchedule> schedules) async {
    if (schedules.isEmpty) {
      throw ArgumentError('Add at least one weekly commitment.');
    }
    for (final schedule in schedules) {
      _validateRecurringSchedule(schedule);
    }
    final db = await database.open();
    await db.transaction((tx) async {
      for (final schedule in schedules) {
        await tx.insert('recurring_schedules', {
          'id': schedule.id,
          'title': schedule.title.trim(),
          'type': schedule.type.name,
          'weekday': schedule.weekday,
          'start_time': schedule.startTime,
          'end_time': schedule.endTime,
          'start_date': schedule.startDate,
          'end_date': schedule.endDate,
          'location': schedule.location,
          'notes': schedule.notes,
          'fixed': schedule.fixed ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  void _validateRecurringSchedule(RecurringSchedule schedule) {
    _title(schedule.title);
    if (schedule.weekday < 1 ||
        schedule.weekday > 7 ||
        !_validClock(schedule.startTime) ||
        !_validClock(schedule.endTime) ||
        schedule.endTime.compareTo(schedule.startTime) <= 0 ||
        dayKey(DateTime.parse(schedule.startDate)) != schedule.startDate ||
        (schedule.endDate != null &&
            (dayKey(DateTime.parse(schedule.endDate!)) != schedule.endDate ||
                schedule.endDate!.compareTo(schedule.startDate) < 0))) {
      throw ArgumentError('Check the weekday, date range and schedule times.');
    }
  }

  @override
  Future<void> removeRecurringSchedule(String id) async {
    final db = await database.open();
    await db.delete('recurring_schedules', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> saveScheduleException(ScheduleException exception) async {
    final origin = _strictDay(exception.day);
    final destination = exception.movedToDate == null
        ? null
        : _strictDay(exception.movedToDate!);
    final hasStart = exception.startTime != null;
    final hasEnd = exception.endTime != null;
    final hasCompleteTimes = hasStart && hasEnd;
    final validTimes =
        !hasStart && !hasEnd ||
        hasCompleteTimes &&
            _validClock(exception.startTime!) &&
            _validClock(exception.endTime!) &&
            exception.endTime!.compareTo(exception.startTime!) > 0;
    if (origin == null ||
        (exception.movedToDate != null && destination == null) ||
        (exception.cancelled &&
            (exception.movedToDate != null || hasStart || hasEnd)) ||
        (!exception.cancelled &&
            exception.movedToDate == null &&
            !hasCompleteTimes) ||
        !validTimes) {
      throw ArgumentError('Check the exception date and time.');
    }
    final db = await database.open();
    final schedules = await db.query(
      'recurring_schedules',
      where: 'id = ?',
      whereArgs: [exception.scheduleId],
    );
    if (schedules.isEmpty) {
      throw ArgumentError('The recurring schedule no longer exists.');
    }
    final schedule = schedules.single;
    final startDate = schedule['start_date'] as String;
    final endDate = schedule['end_date'] as String?;
    if (origin.weekday != schedule['weekday'] ||
        exception.day.compareTo(startDate) < 0 ||
        (endDate != null && exception.day.compareTo(endDate) > 0)) {
      throw ArgumentError('The exception must target a scheduled occurrence.');
    }
    await db.insert('schedule_exceptions', {
      'schedule_id': exception.scheduleId,
      'day': exception.day,
      'kind': exception.cancelled ? 'cancelled' : 'moved',
      'start_time': exception.startTime,
      'end_time': exception.endTime,
      'moved_to_date': exception.movedToDate,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  DateTime? _strictDay(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed != null && dayKey(parsed) == value ? parsed : null;
  }

  @override
  Future<void> savePlanningPreferences(PlanningPreferences p) async {
    if (!_validClock(p.wakeTime) ||
        !_validClock(p.bedTime) ||
        !_validClock(p.avoidFocusAfter) ||
        !_laterClock(p.bedTime, p.wakeTime) ||
        p.transitionMinutes < 0 ||
        p.transitionMinutes > 120 ||
        p.breakMinutes < 1 ||
        p.breakMinutes > 60 ||
        p.maxFocusMinutes < 15 ||
        p.maxFocusMinutes > 240 ||
        !{'balanced', 'productive', 'flexible'}.contains(p.style)) {
      throw ArgumentError('Check your planning preferences.');
    }
    if (!_validWindow(p.breakfastWindow) ||
        !_validWindow(p.lunchWindow) ||
        !_validWindow(p.dinnerWindow)) {
      throw ArgumentError('Meal windows must use valid start-end times.');
    }
    final db = await database.open();
    await db.transaction((tx) async {
      await tx.execute(
        '''CREATE TABLE IF NOT EXISTS planning_preference_changes (
        id INTEGER PRIMARY KEY CHECK(id = 1), fields TEXT NOT NULL
      )''',
      );
      final previous = (await tx.query(
        'planning_preferences',
        where: 'id = 1',
      )).single;
      final values = <String, Object?>{
        'wake_time': p.wakeTime,
        'bed_time': p.bedTime,
        'transition_minutes': p.transitionMinutes,
        'break_minutes': p.breakMinutes,
        'exercise_period': p.exercisePeriod,
        'avoid_focus_after': p.avoidFocusAfter,
        'max_focus_minutes': p.maxFocusMinutes,
        'style': p.style,
        'breakfast_window': p.breakfastWindow,
        'lunch_window': p.lunchWindow,
        'dinner_window': p.dinnerWindow,
      };
      final changed = values.entries
          .where((entry) => previous[entry.key] != entry.value)
          .map((entry) => entry.key)
          .toSet();
      await tx.update('planning_preferences', values, where: 'id = 1');
      if (changed.isNotEmpty) {
        final rows = await tx.query(
          'planning_preference_changes',
          where: 'id = 1',
        );
        if (rows.isNotEmpty) {
          changed.addAll(
            (jsonDecode(rows.single['fields'] as String) as List)
                .cast<String>(),
          );
        }
        await tx.insert('planning_preference_changes', {
          'id': 1,
          'fields': jsonEncode(changed.toList()..sort()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  bool _validClock(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60;
  }

  bool _laterClock(String a, String b) {
    int minutes(String value) {
      final p = value.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    return minutes(a) > minutes(b);
  }

  bool _validWindow(String value) {
    final parts = value.split('-');
    return parts.length == 2 &&
        _validClock(parts[0]) &&
        _validClock(parts[1]) &&
        _laterClock(parts[1], parts[0]);
  }

  Future<void> _reconcileDueReminder(
    Transaction tx,
    Task task, {
    ReminderDefault? option,
  }) async {
    final rows = await tx.query(
      'reminders',
      where: 'task_id = ?',
      whereArgs: [task.id],
    );
    if (rows.isNotEmpty && rows.single['basis'] != ReminderBasis.dueDate.name) {
      return;
    }
    final suppressed = await tx.query(
      'reminder_suppressions',
      where: 'task_id = ?',
      whereArgs: [task.id],
    );
    if (suppressed.isNotEmpty) {
      if (rows.isNotEmpty) {
        await tx.delete(
          'reminders',
          where: 'task_id = ?',
          whereArgs: [task.id],
        );
      }
      return;
    }
    final selected =
        option ??
        ReminderDefault.values.byName(
          (await tx.query(
                'reminder_preferences',
                where: 'id = 1',
              )).single['default_option']
              as String,
        );
    final scheduledAt = task.deadline == null
        ? null
        : dateOnlyDueReminderTime(selected, task.deadline!);
    if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now().toUtc())) {
      if (rows.isNotEmpty) {
        await tx.delete(
          'reminders',
          where: 'task_id = ?',
          whereArgs: [task.id],
        );
      }
      return;
    }
    final values = <String, Object?>{
      'id': rows.isEmpty ? newId() : rows.single['id'],
      'task_id': task.id,
      'scheduled_at': scheduledAt.toIso8601String(),
      'delivery_status': 'pending',
      'origin': ReminderOrigin.defaulted.name,
      'basis': ReminderBasis.dueDate.name,
      'recurrence': ReminderRecurrence.none.name,
    };
    if (rows.isEmpty) {
      await tx.insert('reminders', values);
    } else {
      await tx.update(
        'reminders',
        values,
        where: 'task_id = ?',
        whereArgs: [task.id],
      );
    }
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
