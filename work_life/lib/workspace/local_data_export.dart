import 'dart:convert';

import '../captures/capture.dart';
import 'records.dart';
import 'workspace_repository.dart';

class LocalDataExport {
  const LocalDataExport(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final WorkspaceRepository repository;
  final DateTime Function() now;

  Future<String> buildMarkdown() async {
    final snapshot = await repository.readExportSnapshot();
    final workspace = snapshot.workspace;
    final projects = _sorted(workspace.projects, (value) => value.id);
    final tasks = _sorted(workspace.tasks, (value) => value.id);
    final plans = [...workspace.plans]
      ..sort((a, b) => a.start.compareTo(b.start));
    final buffer = StringBuffer()
      ..writeln('# Work Life report')
      ..writeln()
      ..writeln('Exported: ${now().toLocal().toIso8601String()}')
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln('- Projects: ${projects.length}')
      ..writeln('- Tasks: ${tasks.length}')
      ..writeln(
        '- Completed tasks: ${tasks.where((task) => task.status == TaskStatus.completed).length}',
      )
      ..writeln('- Planner blocks: ${plans.length}')
      ..writeln('- Routines: ${workspace.routines.length}')
      ..writeln('- Captures: ${snapshot.captures.length}');

    buffer
      ..writeln()
      ..writeln('## Projects');
    if (projects.isEmpty) buffer.writeln('\n_No projects._');
    for (final project in projects) {
      buffer
        ..writeln()
        ..writeln('### ${_markdown(project.title)}')
        ..writeln()
        ..writeln('Area: ${_markdown(project.area)}');
      if (project.description.trim().isNotEmpty) {
        buffer.writeln('\n${_markdown(project.description)}');
      }
      final projectTasks = tasks.where((task) => task.projectId == project.id);
      for (final task in projectTasks) {
        buffer.writeln(_taskMarkdown(task));
      }
    }

    buffer
      ..writeln()
      ..writeln('## Tasks without a project');
    final unassigned = tasks.where((task) => task.projectId == null).toList();
    if (unassigned.isEmpty) buffer.writeln('\n_No unassigned tasks._');
    for (final task in unassigned) {
      buffer.writeln(_taskMarkdown(task));
    }

    buffer
      ..writeln()
      ..writeln('## Planner');
    if (plans.isEmpty) buffer.writeln('\n_No planner blocks._');
    for (final plan in plans) {
      buffer.writeln(
        '- ${plan.start.toLocal().toIso8601String()} · ${_markdown(plan.title)} (${plan.minutes} min, ${_markdown(plan.area)})',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Recurring schedule');
    if (workspace.recurringSchedules.isEmpty) {
      buffer.writeln('\n_No recurring commitments._');
    }
    for (final schedule in workspace.recurringSchedules) {
      buffer.writeln(
        '- ${_weekday(schedule.weekday)} ${schedule.startTime}–${schedule.endTime} · ${_markdown(schedule.title)}${schedule.location.trim().isEmpty ? '' : ' · ${_markdown(schedule.location)}'}',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Routines');
    if (workspace.routines.isEmpty) buffer.writeln('\n_No routines._');
    for (final routine in workspace.routines) {
      buffer.writeln(
        '- ${_markdown(routine.title)} · ${_markdown(routine.window)} · minimum: ${_markdown(routine.alternative)}',
      );
    }
    return buffer.toString().trimRight();
  }

  Future<String> buildTasksCsv() async {
    final workspace = (await repository.readExportSnapshot()).workspace;
    final projectNames = {
      for (final project in workspace.projects) project.id: project.title,
    };
    final rows = <List<Object?>>[
      [
        'Title',
        'Status',
        'Priority',
        'Area',
        'Project',
        'Deadline',
        'Minutes',
        'Notes',
        'Checklist',
      ],
      for (final task in _sorted(workspace.tasks, (value) => value.id))
        [
          task.title,
          task.status.name,
          task.priority.name,
          task.area,
          projectNames[task.projectId] ?? '',
          task.deadline ?? '',
          task.minutes,
          task.notes,
          task.checklist
              .map((item) => '${item.done ? '[x]' : '[ ]'} ${item.text}')
              .join(' | '),
        ],
    ];
    return rows.map((row) => row.map(_csv).join(',')).join('\r\n');
  }

  Future<String> buildJson() async {
    final snapshot = await repository.readExportSnapshot();
    final captures = snapshot.captures;
    final workspace = snapshot.workspace;
    final sortedCaptures = [...captures]..sort((a, b) => a.id.compareTo(b.id));
    final data = {
      'captures': sortedCaptures.map(_capture).toList(),
      'projects': _sorted(
        workspace.projects,
        (p) => p.id,
      ).map(_project).toList(),
      'projectEntries': _sorted(
        workspace.entries,
        (e) => e.id,
      ).map(_entry).toList(),
      'tasks': _sorted(workspace.tasks, (t) => t.id).map(_task).toList(),
      'planner': _sorted(workspace.plans, (p) => p.id).map(_plan).toList(),
      'focusSessions': _sorted(
        workspace.sessions,
        (s) => s.id,
      ).map(_session).toList(),
      'routines': _sorted(
        workspace.routines,
        (r) => r.id,
      ).map(_routine).toList(),
      'recurringSchedules': _sorted(workspace.recurringSchedules, (s) => s.id)
          .map(
            (s) => {
              'id': s.id,
              'title': s.title,
              'type': s.type.name,
              'weekday': s.weekday,
              'startTime': s.startTime,
              'endTime': s.endTime,
              'startDate': s.startDate,
              'endDate': s.endDate,
              'location': s.location,
              'notes': s.notes,
              'fixed': s.fixed,
            },
          )
          .toList(),
      'scheduleExceptions': workspace.scheduleExceptions
          .map(
            (e) => {
              'scheduleId': e.scheduleId,
              'day': e.day,
              'cancelled': e.cancelled,
              'startTime': e.startTime,
              'endTime': e.endTime,
              'movedToDate': e.movedToDate,
            },
          )
          .toList(),
      'routineRecords':
          ([...workspace.routineRecords]..sort((a, b) {
                final routine = a.routineId.compareTo(b.routineId);
                return routine == 0 ? a.day.compareTo(b.day) : routine;
              }))
              .map(_routineRecord)
              .toList(),
      'lifeAreas': [...workspace.areas]..sort(),
      'reminders': _sorted(
        workspace.reminders,
        (r) => r.id,
      ).map(_reminder).toList(),
      'reminderSuppressions': [...workspace.suppressedTaskIds]..sort(),
      'settings': {
        'quietHours': {
          'enabled': workspace.quietHours.enabled,
          'startMinute': workspace.quietHours.startMinute,
          'endMinute': workspace.quietHours.endMinute,
        },
        'reminderDefault': workspace.reminderDefault.name,
        'planningPreferences': {
          'wakeTime': workspace.planningPreferences.wakeTime,
          'bedTime': workspace.planningPreferences.bedTime,
          'transitionMinutes': workspace.planningPreferences.transitionMinutes,
          'breakMinutes': workspace.planningPreferences.breakMinutes,
          'exercisePeriod': workspace.planningPreferences.exercisePeriod,
          'avoidFocusAfter': workspace.planningPreferences.avoidFocusAfter,
          'maxFocusMinutes': workspace.planningPreferences.maxFocusMinutes,
          'style': workspace.planningPreferences.style,
          'breakfastWindow': workspace.planningPreferences.breakfastWindow,
          'lunchWindow': workspace.planningPreferences.lunchWindow,
          'dinnerWindow': workspace.planningPreferences.dinnerWindow,
        },
      },
    };
    return jsonEncode({
      'formatVersion': 1,
      'exportedAt': now().toUtc().toIso8601String(),
      'app': 'Work Life',
      'data': data,
    });
  }

  List<T> _sorted<T>(List<T> values, String Function(T) id) =>
      ([...values]..sort((a, b) => id(a).compareTo(id(b))));

  String _taskMarkdown(Task task) {
    final mark = task.status == TaskStatus.completed ? 'x' : ' ';
    final details = <String>[
      task.area,
      task.priority.name,
      '${task.minutes} min',
      if (task.deadline != null) 'due ${task.deadline}',
    ];
    return '- [$mark] ${_markdown(task.title)} — ${details.map(_markdown).join(' · ')}';
  }

  String _markdown(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll('|', '\\|')
      .trim();

  String _csv(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';

  String _weekday(int value) => const [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][value.clamp(1, 7)];

  Map<String, Object?> _capture(Capture value) => {
    'id': value.id,
    'originalText': value.originalText,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
  };

  Map<String, Object?> _project(Project value) => {
    'id': value.id,
    'title': value.title,
    'area': value.area,
    'description': value.description,
  };

  Map<String, Object?> _entry(ProjectEntry value) => {
    'id': value.id,
    'projectId': value.projectId,
    'title': value.title,
    'body': value.body,
    'kind': value.kind,
    'relatedId': value.relatedId,
    'captureId': value.captureId,
  };

  Map<String, Object?> _task(Task value) => {
    'id': value.id,
    'title': value.title,
    'area': value.area,
    'projectId': value.projectId,
    'captureId': value.captureId,
    'entryId': value.entryId,
    'deadline': value.deadline,
    'minutes': value.minutes,
    'notes': value.notes,
    'priority': value.priority.name,
    'status': value.status.name,
    'checklist': value.checklist
        .map((item) => {'id': item.id, 'text': item.text, 'done': item.done})
        .toList(),
  };

  Map<String, Object?> _plan(PlanBlock value) => {
    'id': value.id,
    'title': value.title,
    'taskId': value.taskId,
    'start': value.start.toUtc().toIso8601String(),
    'minutes': value.minutes,
    'area': value.area,
    'fixed': value.fixed,
  };

  Map<String, Object?> _session(FocusSession value) => {
    'id': value.id,
    'taskId': value.taskId,
    'minutes': value.minutes,
    'startedAt': value.startedAt.toUtc().toIso8601String(),
    'runningSince': value.runningSince?.toUtc().toIso8601String(),
    'seconds': value.seconds,
    'outcome': value.outcome?.name,
    'notes': value.notes,
    'area': value.area,
  };

  Map<String, Object?> _routine(Routine value) => {
    'id': value.id,
    'title': value.title,
    'area': value.area,
    'window': value.window,
    'alternative': value.alternative,
    'normal': value.normal,
    'strong': value.strong,
    'createdDay': value.createdDay,
  };

  Map<String, Object?> _routineRecord(RoutineRecord value) => {
    'routineId': value.routineId,
    'day': value.day,
    'outcome': value.outcome,
    'level': value.level?.name,
    'area': value.area,
  };

  Map<String, Object?> _reminder(TaskReminder value) => {
    'id': value.id,
    'taskId': value.taskId,
    'scheduledAt': value.scheduledAt.toUtc().toIso8601String(),
    'origin': value.origin.name,
    'basis': value.basis.name,
    'recurrence': value.recurrence.name,
  };
}
