import 'dart:convert';

import '../captures/capture.dart';
import 'records.dart';
import 'workspace_repository.dart';

class LocalDataExport {
  const LocalDataExport(this.repository, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final WorkspaceRepository repository;
  final DateTime Function() now;

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
