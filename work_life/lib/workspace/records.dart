import '../captures/capture.dart';

String newId() => Capture.create('').id;
String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

/// Calendar-local day arithmetic for wall-clock concepts such as classes.
/// Unlike adding a 24-hour Duration, this remains local midnight across DST.
DateTime calendarDay(DateTime value, [int offset = 0]) =>
    DateTime(value.year, value.month, value.day + offset);

enum TaskStatus { open, inProgress, completed, cancelled }

enum TaskPriority { low, medium, high }

enum FocusOutcome { completed, partial, blocked }

enum ReminderDefault {
  none,
  atTime,
  tenMinutesBefore,
  thirtyMinutesBefore,
  oneHourBefore,
}

enum ReminderOrigin { explicit, defaulted }

/// Why a reminder exists. This lets generated reminders be recalculated
/// without ever overwriting a time the user explicitly chose.
enum ReminderBasis { explicit, plannedTime, dueDate }

enum ReminderRecurrence { none, daily, weekly }

class Project {
  const Project({
    required this.id,
    required this.title,
    required this.area,
    this.description = '',
  });
  final String id, title, area, description;
}

class ProjectEntry {
  const ProjectEntry({
    required this.id,
    required this.projectId,
    required this.title,
    required this.body,
    this.kind = 'note',
    this.relatedId,
    this.captureId,
  });
  final String id, projectId, title, body, kind;
  final String? relatedId, captureId;
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });
  final String id, text;
  final bool done;
  ChecklistItem toggle() => ChecklistItem(id: id, text: text, done: !done);
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.area,
    this.projectId,
    this.captureId,
    this.entryId,
    this.deadline,
    this.minutes = 25,
    this.notes = '',
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.open,
    this.checklist = const [],
  });
  final String id, title, area, notes;
  final String? projectId, captureId, entryId, deadline;
  final int minutes;
  final TaskPriority priority;
  final TaskStatus status;
  final List<ChecklistItem> checklist;
  bool get active =>
      status == TaskStatus.open || status == TaskStatus.inProgress;
  Task withStatus(TaskStatus value) => Task(
    id: id,
    title: title,
    area: area,
    projectId: projectId,
    captureId: captureId,
    entryId: entryId,
    deadline: deadline,
    minutes: minutes,
    notes: notes,
    priority: priority,
    status: value,
    checklist: checklist,
  );
  Task withChecklist(List<ChecklistItem> value) => Task(
    id: id,
    title: title,
    area: area,
    projectId: projectId,
    captureId: captureId,
    entryId: entryId,
    deadline: deadline,
    minutes: minutes,
    notes: notes,
    priority: priority,
    status: status,
    checklist: value,
  );
}

class TaskReminder {
  const TaskReminder({
    required this.id,
    required this.taskId,
    required this.scheduledAt,
    this.deliveryStatus = 'pending',
    this.origin = ReminderOrigin.explicit,
    this.basis = ReminderBasis.explicit,
    this.recurrence = ReminderRecurrence.none,
  });
  final String id, taskId;
  final DateTime scheduledAt;
  final String deliveryStatus;
  final ReminderOrigin origin;
  final ReminderBasis basis;
  final ReminderRecurrence recurrence;
}

class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.startMinute = 23 * 60,
    this.endMinute = 7 * 60,
  });
  final bool enabled;
  final int startMinute, endMinute;

  QuietHours copyWith({bool? enabled, int? startMinute, int? endMinute}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );
}

class PlanBlock {
  const PlanBlock({
    required this.id,
    required this.title,
    required this.start,
    required this.minutes,
    required this.area,
    this.taskId,
    this.fixed = false,
  });
  final String id, title, area;
  final String? taskId;
  final DateTime start;
  final int minutes;
  final bool fixed;
  DateTime get end => start.add(Duration(minutes: minutes));
  bool occursOn(DateTime day) =>
      start.isBefore(DateTime(day.year, day.month, day.day + 1)) &&
      end.isAfter(DateTime(day.year, day.month, day.day));
  bool overlaps(PlanBlock other) =>
      start.isBefore(other.end) && end.isAfter(other.start);
}

enum RecurringScheduleType { classSession, work, meeting, commitment, other }

class RecurringSchedule {
  const RecurringSchedule({
    required this.id,
    required this.title,
    required this.type,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.startDate,
    this.endDate,
    this.location = '',
    this.notes = '',
    this.fixed = true,
  });
  final String id, title, startTime, endTime, startDate, location, notes;
  final String? endDate;
  final RecurringScheduleType type;

  /// DateTime weekday (Monday=1 … Sunday=7).
  final int weekday;
  final bool fixed;
  bool occursOn(DateTime day, {Set<String> exceptions = const {}}) {
    final key = dayKey(day);
    return day.weekday == weekday &&
        key.compareTo(startDate) >= 0 &&
        (endDate == null || key.compareTo(endDate!) <= 0) &&
        !exceptions.contains(key);
  }
}

class ScheduleException {
  const ScheduleException({
    required this.scheduleId,
    required this.day,
    this.cancelled = true,
    this.startTime,
    this.endTime,
    this.movedToDate,
  });
  final String scheduleId, day;
  final bool cancelled;
  final String? startTime, endTime;
  final String? movedToDate;
}

class PlanningPreferences {
  const PlanningPreferences({
    this.wakeTime = '07:30',
    this.bedTime = '23:00',
    this.transitionMinutes = 15,
    this.breakMinutes = 15,
    this.exercisePeriod = 'flexible',
    this.avoidFocusAfter = '21:30',
    this.maxFocusMinutes = 90,
    this.style = 'balanced',
    this.breakfastWindow = '07:00-09:00',
    this.lunchWindow = '12:00-14:00',
    this.dinnerWindow = '18:00-20:00',
  });
  final String wakeTime, bedTime, exercisePeriod, avoidFocusAfter, style;
  final String breakfastWindow, lunchWindow, dinnerWindow;
  final int transitionMinutes, breakMinutes, maxFocusMinutes;
}

enum RoutineLevel { minimum, normal, strong }

class Routine {
  const Routine({
    required this.id,
    required this.title,
    required this.area,
    required this.window,
    required this.alternative,
    this.normal = '',
    this.strong = '',
    required this.createdDay,
  });
  final String id, title, area, window, alternative, createdDay, normal, strong;
  String descriptionFor(RoutineLevel level) => switch (level) {
    RoutineLevel.minimum => alternative,
    RoutineLevel.normal => normal.isEmpty ? title : normal,
    RoutineLevel.strong => strong,
  };
}

class RoutineRecord {
  const RoutineRecord({
    required this.routineId,
    required this.day,
    required this.outcome,
    this.area = '',
  });
  final String routineId, day, outcome, area;
  RoutineLevel? get level => switch (outcome) {
    'smaller' => RoutineLevel.minimum,
    'done' => RoutineLevel.normal,
    'strong' => RoutineLevel.strong,
    _ => null,
  };
  bool get completed => level != null;
}

class FocusSession {
  const FocusSession({
    required this.id,
    required this.taskId,
    required this.minutes,
    required this.startedAt,
    this.runningSince,
    this.seconds = 0,
    this.outcome,
    this.notes = '',
    this.area = '',
  });
  final String id, taskId, notes, area;
  final int minutes, seconds;
  final DateTime startedAt;
  final DateTime? runningSince;
  final FocusOutcome? outcome;
  int elapsed(DateTime now) =>
      seconds +
      (runningSince == null
          ? 0
          : now.difference(runningSince!).inSeconds.clamp(0, 2147483647));
  FocusSession pause(DateTime now) => FocusSession(
    id: id,
    taskId: taskId,
    area: area,
    minutes: minutes,
    startedAt: startedAt,
    seconds: elapsed(now),
    notes: notes,
  );
  FocusSession resume(DateTime now) => FocusSession(
    id: id,
    taskId: taskId,
    area: area,
    minutes: minutes,
    startedAt: startedAt,
    seconds: seconds,
    runningSince: now,
    notes: notes,
  );
  FocusSession finish(DateTime now, FocusOutcome result, String note) =>
      FocusSession(
        id: id,
        taskId: taskId,
        area: area,
        minutes: minutes,
        startedAt: startedAt,
        seconds: elapsed(now),
        outcome: result,
        notes: note,
      );
}

class WorkspaceData {
  const WorkspaceData({
    this.onboardingCompleted = false,
    this.tasks = const [],
    this.entries = const [],
    this.projects = const [],
    this.plans = const [],
    this.routines = const [],
    this.routineRecords = const [],
    this.sessions = const [],
    this.areas = const [],
    this.reminders = const [],
    this.suppressedTaskIds = const [],
    this.quietHours = const QuietHours(),
    this.reminderDefault = ReminderDefault.none,
    this.recurringSchedules = const [],
    this.scheduleExceptions = const [],
    this.planningPreferences = const PlanningPreferences(),
  });
  final bool onboardingCompleted;
  final List<Task> tasks;
  final List<ProjectEntry> entries;
  final List<Project> projects;
  final List<PlanBlock> plans;
  final List<Routine> routines;
  final List<RoutineRecord> routineRecords;
  final List<FocusSession> sessions;
  final List<String> areas;
  final List<TaskReminder> reminders;
  final List<String> suppressedTaskIds;
  final QuietHours quietHours;
  final ReminderDefault reminderDefault;
  final List<RecurringSchedule> recurringSchedules;

  /// schedule id -> excluded ISO dates
  final List<ScheduleException> scheduleExceptions;
  final PlanningPreferences planningPreferences;
}
