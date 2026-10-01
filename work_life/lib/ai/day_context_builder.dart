import 'dart:convert';

import '../workspace/records.dart';

/// Builds only date-relevant, typed local context for a day-planning request.
/// The result intentionally separates hard commitments from flexible work and
/// optional lifestyle suggestions; it contains no provider or database data.
class DayContextBuilder {
  const DayContextBuilder();

  Map<String, Object?> build(
    WorkspaceData workspace,
    DateTime requestedDay, {
    String request = '',
  }) {
    final date = DateTime(
      requestedDay.year,
      requestedDay.month,
      requestedDay.day,
    );
    final key = dayKey(date);
    final horizonKey = dayKey(calendarDay(date, 7));
    final exceptions = workspace.scheduleExceptions
        .where((e) => e.day == key)
        .toList();
    final schedules = <Map<String, Object?>>[];
    for (final item in workspace.recurringSchedules) {
      if (item.weekday != date.weekday ||
          key.compareTo(item.startDate) < 0 ||
          (item.endDate != null && key.compareTo(item.endDate!) > 0)) {
        continue;
      }
      final exception = exceptions
          .where((e) => e.scheduleId == item.id)
          .firstOrNull;
      if (exception?.cancelled == true || exception?.movedToDate != null) {
        continue;
      }
      schedules.add({
        'scheduleId': item.id,
        'title': item.title,
        'kind': item.type.name,
        'start': exception?.startTime ?? item.startTime,
        'end': exception?.endTime ?? item.endTime,
        'location': item.location,
        'fixed': item.fixed,
        'notes': item.notes,
      });
    }
    for (final exception in workspace.scheduleExceptions.where(
      (e) => e.movedToDate == key,
    )) {
      final item = workspace.recurringSchedules
          .where((s) => s.id == exception.scheduleId)
          .firstOrNull;
      final origin = DateTime.tryParse(exception.day);
      if (item == null ||
          origin == null ||
          origin.weekday != item.weekday ||
          exception.cancelled ||
          exception.day.compareTo(item.startDate) < 0 ||
          (item.endDate != null &&
              exception.day.compareTo(item.endDate!) > 0)) {
        continue;
      }
      schedules.add({
        'scheduleId': item.id,
        'title': item.title,
        'kind': item.type.name,
        'start': exception.startTime ?? item.startTime,
        'end': exception.endTime ?? item.endTime,
        'location': item.location,
        'fixed': item.fixed,
        'notes': item.notes,
        'movedFrom': exception.day,
      });
    }
    final plans = workspace.plans
        .where((p) => p.occursOn(date))
        .map(
          (p) => {
            'planId': p.id,
            'taskId': p.taskId,
            'title': p.title,
            'start': p.start.toIso8601String(),
            'minutes': p.minutes,
            'fixed': p.fixed,
            'constraint': p.fixed ? 'hard' : 'soft',
          },
        )
        .toList();
    final tasks = workspace.tasks
        .where(
          (t) =>
              t.active &&
              (t.deadline != null && t.deadline!.compareTo(horizonKey) <= 0 ||
                  workspace.plans.any(
                    (p) => p.taskId == t.id && p.occursOn(date),
                  )),
        )
        .map(
          (t) => {
            'taskId': t.id,
            'title': t.title,
            'area': t.area,
            'priority': t.priority.name,
            'minutes': t.minutes,
            'deadline': t.deadline,
            'status': t.status.name,
            'projectId': t.projectId,
            'scheduledToday': workspace.plans.any(
              (p) => p.taskId == t.id && p.occursOn(date),
            ),
            'urgency': t.deadline == null
                ? 'normal'
                : (t.deadline!.compareTo(key) < 0
                      ? 'overdue'
                      : t.deadline == key
                      ? 'due_today'
                      : 'upcoming'),
          },
        )
        .toList();
    return {
      'date': key,
      'weekday': date.weekday,
      'fixedCommitments': schedules,
      'existingPlanner': plans,
      'capacity': _capacity(workspace, date, schedules),
      'tasks': tasks,
      'routines': workspace.routines
          .map(
            (r) => {
              'routineId': r.id,
              'title': r.title,
              'area': r.area,
              'window': r.window,
            },
          )
          .toList(),
      'preferences': _preferences(workspace.planningPreferences),
      'instructions': 'Respect fixed commitments and locked Planner blocks. Schedule high-priority and urgent tasks first and keep task IDs unchanged. Build a realistic whole-life plan that can include travel between places, commuting, errands, appointments, household work, preparation, personal care, social/family time, recovery and open time when supported by the supplied context. Existing actionable errands keep their task IDs; supportive lifestyle blocks must not become fake Tasks. Respect wake/bed, focus boundaries and transition buffers. Move lower-priority work when capacity is insufficient and never invent commitments.',
      if (request.trim().isNotEmpty) 'userRequest': request.trim(),
    };
  }

  Map<String, Object?> _capacity(
    WorkspaceData data,
    DateTime day,
    List<Map<String, Object?>> recurring,
  ) {
    int minute(String value) {
      final p = value.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final preference = data.planningPreferences;
    final waking = (minute(preference.bedTime) - minute(preference.wakeTime))
        .clamp(0, 1440);
    final spans = <List<int>>[];
    for (final row in recurring) {
      spans.add([minute(row['start'] as String), minute(row['end'] as String)]);
    }
    for (final plan in data.plans.where((p) => p.occursOn(day))) {
      final start = plan.start.hour * 60 + plan.start.minute;
      spans.add([start, (start + plan.minutes).clamp(0, 1440)]);
    }
    spans.sort((a, b) => a[0].compareTo(b[0]));
    var occupied = 0, cursor = -1;
    for (final span in spans) {
      final start = span[0], end = span[1];
      if (end <= cursor) continue;
      occupied += end - (start < cursor ? cursor : start);
      cursor = end;
    }
    final urgent = data.tasks
        .where(
          (t) =>
              t.active &&
              t.deadline != null &&
              t.deadline!.compareTo(dayKey(calendarDay(day, 7))) <= 0,
        )
        .fold<int>(0, (n, t) => n + t.minutes);
    final available =
        (waking - occupied - spans.length * preference.transitionMinutes).clamp(
          0,
          1440,
        );
    return {
      'wakingMinutes': waking,
      'fixedAndPlannedMinutes': occupied,
      'availableMinutes': available,
      'urgentTaskEstimateMinutes': urgent,
      'overCapacity': urgent > available,
    };
  }

  String encode(WorkspaceData workspace, DateTime day, {String request = ''}) =>
      jsonEncode(build(workspace, day, request: request));

  /// A deterministic, non-secret identity for the date-relevant planning
  /// state. It deliberately excludes the user's temporary request text.
  String fingerprint(WorkspaceData workspace, DateTime day) {
    final canonical = _canonical(build(workspace, day));
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(jsonEncode(canonical))) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) {
      final items = value.map(_canonical).toList();
      items.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      return items;
    }
    return value;
  }

  Map<String, Object?> _preferences(PlanningPreferences p) => {
    'wakeTime': p.wakeTime,
    'bedTime': p.bedTime,
    'transitionMinutes': p.transitionMinutes,
    'breakMinutes': p.breakMinutes,
    'exercisePeriod': p.exercisePeriod,
    'avoidFocusAfter': p.avoidFocusAfter,
    'maxFocusMinutes': p.maxFocusMinutes,
    'style': p.style,
    'breakfastWindow': p.breakfastWindow,
    'lunchWindow': p.lunchWindow,
    'dinnerWindow': p.dinnerWindow,
  };
}

/// Reuses the exact date-scoped day context for a Monday-to-Sunday planning
/// horizon, avoiding a second incompatible weekly data model.
class WeekContextBuilder {
  const WeekContextBuilder({this.dayBuilder = const DayContextBuilder()});
  final DayContextBuilder dayBuilder;
  List<Map<String, Object?>> build(
    WorkspaceData workspace,
    DateTime weekStart, {
    String request = '',
  }) {
    final monday = calendarDay(weekStart, -(weekStart.weekday - 1));
    return List.generate(
      7,
      (index) => dayBuilder.build(
        workspace,
        calendarDay(monday, index),
        request: request,
      ),
    );
  }

  /// A compact seven-day payload for the weekly architect. Shared routines,
  /// preferences and tasks are emitted once while each day keeps its own hard
  /// commitments, existing blocks and capacity calculation.
  Map<String, Object?> buildPlanningContext(
    WorkspaceData workspace,
    DateTime weekStart, {
    String request = '',
  }) {
    final monday = calendarDay(weekStart, -(weekStart.weekday - 1));
    final sunday = calendarDay(monday, 6);
    final shortlyAfter = dayKey(calendarDay(sunday, 3));
    final days = build(workspace, monday);
    final relevantTasks = workspace.tasks.where((task) {
      if (!task.active) return false;
      final plannedInWeek = workspace.plans.any(
        (plan) =>
            plan.taskId == task.id &&
            !plan.start.isBefore(monday) &&
            plan.start.isBefore(calendarDay(sunday, 1)),
      );
      return plannedInWeek ||
          (task.deadline != null &&
              task.deadline!.compareTo(shortlyAfter) <= 0);
    }).toList();

    final compactDays = days.map((day) {
      final capacity = day['capacity'] as Map<String, Object?>;
      return {
        'date': day['date'],
        'weekday': day['weekday'],
        'fixedCommitments': day['fixedCommitments'],
        'existingPlanner': day['existingPlanner'],
        'capacity': capacity,
      };
    }).toList();
    final overloaded = compactDays
        .where(
          (day) =>
              (day['capacity'] as Map<String, Object?>)['overCapacity'] == true,
        )
        .map((day) => day['date'])
        .toList();
    final lighter = [...compactDays]
      ..sort(
        (a, b) =>
            ((b['capacity'] as Map<String, Object?>)['availableMinutes'] as int)
                .compareTo(
                  (a['capacity'] as Map<String, Object?>)['availableMinutes']
                      as int,
                ),
      );

    return {
      'type': 'weekly_planning_context',
      'week': {'start': dayKey(monday), 'end': dayKey(sunday)},
      'days': compactDays,
      'tasks': relevantTasks
          .map(
            (task) => {
              'taskId': task.id,
              'title': task.title,
              'area': task.area,
              'priority': task.priority.name,
              'estimatedMinutes': task.minutes,
              'deadline': task.deadline,
              'projectId': task.projectId,
              'plannedDates': workspace.plans
                  .where(
                    (plan) =>
                        plan.taskId == task.id &&
                        !plan.start.isBefore(monday) &&
                        plan.start.isBefore(calendarDay(sunday, 1)),
                  )
                  .map((plan) => dayKey(plan.start))
                  .toSet()
                  .toList(),
            },
          )
          .toList(),
      'workload': {
        'estimatedTaskMinutes': relevantTasks.fold<int>(
          0,
          (total, task) => total + task.minutes,
        ),
        'availableMinutes': compactDays.fold<int>(
          0,
          (total, day) =>
              total +
              ((day['capacity'] as Map<String, Object?>)['availableMinutes']
                  as int),
        ),
        'overloadedDays': overloaded,
        'lighterDays': lighter.take(3).map((day) => day['date']).toList(),
      },
      'routines': days.first['routines'],
      'preferences': days.first['preferences'],
      'instructions': 'Build a feasible Monday-to-Sunday whole-life plan. Keep fixed and locked blocks unchanged. Schedule linked tasks using exact IDs before deadlines without exceeding estimates. Balance demanding work and preserve travel/transition buffers, preparation, errands, appointments, household and personal activities, social/family time, recovery and open time when supported by context. Existing actionable items retain task IDs; supportive lifestyle blocks do not get task IDs. Never manufacture commitments. Return existing blocks with explicit add, move, change, remove, or unchanged operations.',
      if (request.trim().isNotEmpty) 'userRequest': request.trim(),
    };
  }

  Map<String, String> fingerprints(
    WorkspaceData workspace,
    DateTime weekStart,
  ) {
    final monday = calendarDay(weekStart, -(weekStart.weekday - 1));
    return {
      for (var offset = 0; offset < 7; offset++)
        dayKey(calendarDay(monday, offset)): dayBuilder.fingerprint(
          workspace,
          calendarDay(monday, offset),
        ),
    };
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
