import 'dart:convert';

import '../captures/capture.dart';
import 'records.dart';
import 'workspace_repository.dart';
import 'local_restore_data.dart';

class LocalDataImport {
  const LocalDataImport(this.repository);
  final WorkspaceRepository repository;

  Future<void> restore(String json) async {
    final root = jsonDecode(json);
    if (root is! Map || root['formatVersion'] != 1 || root['data'] is! Map) {
      throw const FormatException('Unsupported Work Life export.');
    }
    final data = Map<String, dynamic>.from(root['data'] as Map);
    final lists = <String>[
      'captures',
      'projects',
      'projectEntries',
      'tasks',
      'planner',
      'focusSessions',
      'routines',
      'routineRecords',
      'lifeAreas',
      'reminders',
    ];
    for (final key in lists) {
      if (data[key] is! List) {
        throw FormatException('Missing export section: $key');
      }
    }
    final captures = (data['captures'] as List).map(_capture).toList();
    final projects = (data['projects'] as List).map(_project).toList();
    final entries = (data['projectEntries'] as List).map(_entry).toList();
    final tasks = (data['tasks'] as List).map(_task).toList();
    final plans = (data['planner'] as List).map(_plan).toList();
    final routines = (data['routines'] as List).map(_routine).toList();
    final records = (data['routineRecords'] as List)
        .map(_routineRecord)
        .toList();
    final sessions = (data['focusSessions'] as List).map(_session).toList();
    final reminders = (data['reminders'] as List).map(_reminder).toList();
    final areas = (data['lifeAreas'] as List).map((v) => v as String).toList();
    final recurringSchedules =
        ((data['recurringSchedules'] as List?) ?? const []).map((value) {
          final m = _map(value);
          return RecurringSchedule(
            id: m['id'],
            title: m['title'],
            type: RecurringScheduleType.values.byName(m['type']),
            weekday: m['weekday'],
            startTime: m['startTime'],
            endTime: m['endTime'],
            startDate: m['startDate'],
            endDate: m['endDate'],
            location: m['location'] ?? '',
            notes: m['notes'] ?? '',
            fixed: m['fixed'] ?? true,
          );
        }).toList();
    final scheduleExceptions =
        ((data['scheduleExceptions'] as List?) ?? const []).map((value) {
          final m = _map(value);
          return ScheduleException(
            scheduleId: m['scheduleId'],
            day: m['day'],
            cancelled: m['cancelled'] ?? true,
            startTime: m['startTime'],
            endTime: m['endTime'],
            movedToDate: m['movedToDate'],
          );
        }).toList();
    final suppressedTaskIds =
        ((data['reminderSuppressions'] as List?) ?? const [])
            .map((value) => value as String)
            .toList();
    final taskIds = tasks.map((task) => task.id).toSet();
    if (suppressedTaskIds.any((id) => !taskIds.contains(id))) {
      throw const FormatException('A reminder suppression has no task.');
    }
    QuietHours? quietHours;
    ReminderDefault? reminderDefault;
    PlanningPreferences? planningPreferences;
    final settings = data['settings'];
    if (settings is Map) {
      final quiet = settings['quietHours'];
      if (quiet is Map) {
        quietHours = QuietHours(
          enabled: quiet['enabled'] == true,
          startMinute: quiet['startMinute'] as int,
          endMinute: quiet['endMinute'] as int,
        );
      }
      final defaultName = settings['reminderDefault'];
      if (defaultName is String) {
        reminderDefault = ReminderDefault.values.byName(defaultName);
      }
      final p = settings['planningPreferences'];
      if (p is Map) {
        planningPreferences = PlanningPreferences(
          wakeTime: p['wakeTime'] ?? '07:30',
          bedTime: p['bedTime'] ?? '23:00',
          transitionMinutes: p['transitionMinutes'] ?? 15,
          breakMinutes: p['breakMinutes'] ?? 15,
          exercisePeriod: p['exercisePeriod'] ?? 'flexible',
          avoidFocusAfter: p['avoidFocusAfter'] ?? '21:30',
          maxFocusMinutes: p['maxFocusMinutes'] ?? 90,
          style: p['style'] ?? 'balanced',
          breakfastWindow: p['breakfastWindow'] ?? '07:00-09:00',
          lunchWindow: p['lunchWindow'] ?? '12:00-14:00',
          dinnerWindow: p['dinnerWindow'] ?? '18:00-20:00',
        );
      }
    }

    // Parse every section before destructive replacement. This prevents a
    // malformed optional v17 section from clearing an otherwise valid local
    // workspace before the error is discovered.
    final restoreData = LocalRestoreData(
      captures: captures,
      projects: projects,
      entries: entries,
      tasks: tasks,
      plans: plans,
      routines: routines,
      routineRecords: records,
      sessions: sessions,
      reminders: reminders,
      areas: areas,
      recurringSchedules: recurringSchedules,
      scheduleExceptions: scheduleExceptions,
      suppressedTaskIds: suppressedTaskIds,
      quietHours: quietHours,
      reminderDefault: reminderDefault,
      planningPreferences: planningPreferences,
    );
    if (repository case final SqliteWorkspaceRepository sqlite) {
      await sqlite.replaceLocalData(restoreData);
      return;
    }
    await repository.clearLocalData();
    for (final area in areas) {
      await repository.addArea(area);
    }
    for (final capture in captures) {
      await repository.save(capture);
    }
    for (final project in projects) {
      await repository.saveProject(project);
    }
    for (final entry in entries) {
      await repository.saveEntry(entry);
    }
    for (final task in tasks) {
      await repository.saveTask(task);
    }
    for (final plan in plans) {
      await repository.savePlan(plan);
    }
    for (final schedule in recurringSchedules) {
      await repository.saveRecurringSchedule(schedule);
    }
    for (final exception in scheduleExceptions) {
      await repository.saveScheduleException(exception);
    }
    for (final routine in routines) {
      await repository.saveRoutine(routine);
    }
    for (final record in records) {
      await repository.recordRoutine(record);
    }
    for (final session in sessions) {
      await repository.saveSession(session);
    }
    for (final reminder in reminders) {
      await repository.saveReminder(reminder);
    }
    for (final taskId in suppressedTaskIds) {
      await repository.removeReminder(taskId);
    }
    if (quietHours != null) await repository.saveQuietHours(quietHours);
    if (reminderDefault != null) {
      await repository.saveReminderDefault(reminderDefault);
    }
    if (planningPreferences != null) {
      await repository.savePlanningPreferences(planningPreferences);
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid export record.');
    return Map<String, dynamic>.from(value);
  }

  Capture _capture(Object? v) {
    final m = _map(v);
    return Capture(
      id: m['id'],
      originalText: m['originalText'],
      createdAt: DateTime.parse(m['createdAt']),
    );
  }

  Project _project(Object? v) {
    final m = _map(v);
    return Project(
      id: m['id'],
      title: m['title'],
      area: m['area'],
      description: m['description'],
    );
  }

  ProjectEntry _entry(Object? v) {
    final m = _map(v);
    return ProjectEntry(
      id: m['id'],
      projectId: m['projectId'],
      title: m['title'],
      body: m['body'],
      kind: m['kind'],
      relatedId: m['relatedId'],
      captureId: m['captureId'],
    );
  }

  Task _task(Object? v) {
    final m = _map(v);
    return Task(
      id: m['id'],
      title: m['title'],
      area: m['area'],
      projectId: m['projectId'],
      captureId: m['captureId'],
      entryId: m['entryId'],
      deadline: m['deadline'],
      minutes: m['minutes'],
      notes: m['notes'],
      priority: TaskPriority.values.byName(m['priority'] ?? 'medium'),
      status: TaskStatus.values.byName(m['status']),
      checklist: (m['checklist'] as List).map((i) {
        final x = _map(i);
        return ChecklistItem(id: x['id'], text: x['text'], done: x['done']);
      }).toList(),
    );
  }

  PlanBlock _plan(Object? v) {
    final m = _map(v);
    return PlanBlock(
      id: m['id'],
      title: m['title'],
      taskId: m['taskId'],
      start: DateTime.parse(m['start']),
      minutes: m['minutes'],
      area: m['area'],
      fixed: m['fixed'],
    );
  }

  Routine _routine(Object? v) {
    final m = _map(v);
    return Routine(
      id: m['id'],
      title: m['title'],
      area: m['area'],
      window: m['window'],
      alternative: m['alternative'],
      normal: m['normal'] ?? '',
      strong: m['strong'] ?? '',
      createdDay: m['createdDay'],
    );
  }

  RoutineRecord _routineRecord(Object? v) {
    final m = _map(v);
    return RoutineRecord(
      routineId: m['routineId'],
      day: m['day'],
      outcome: m['outcome'],
      area: m['area'] ?? '',
    );
  }

  FocusSession _session(Object? v) {
    final m = _map(v);
    return FocusSession(
      id: m['id'],
      taskId: m['taskId'],
      minutes: m['minutes'],
      startedAt: DateTime.parse(m['startedAt']),
      runningSince: m['runningSince'] == null
          ? null
          : DateTime.parse(m['runningSince']),
      seconds: m['seconds'],
      outcome: m['outcome'] == null
          ? null
          : FocusOutcome.values.byName(m['outcome']),
      notes: m['notes'],
      area: m['area'],
    );
  }

  TaskReminder _reminder(Object? v) {
    final m = _map(v);
    return TaskReminder(
      id: m['id'],
      taskId: m['taskId'],
      scheduledAt: DateTime.parse(m['scheduledAt']),
      origin: ReminderOrigin.values.byName(m['origin']),
      basis: ReminderBasis.values.byName(m['basis'] ?? 'explicit'),
      recurrence: ReminderRecurrence.values.byName(m['recurrence'] ?? 'none'),
    );
  }
}
