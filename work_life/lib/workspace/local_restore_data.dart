import '../captures/capture.dart';
import 'records.dart';

class LocalRestoreData {
  const LocalRestoreData({
    required this.captures,
    required this.projects,
    required this.entries,
    required this.tasks,
    required this.plans,
    required this.routines,
    required this.routineRecords,
    required this.sessions,
    required this.reminders,
    required this.areas,
    required this.recurringSchedules,
    required this.scheduleExceptions,
    required this.suppressedTaskIds,
    this.quietHours,
    this.reminderDefault,
    this.planningPreferences,
  });

  final List<Capture> captures;
  final List<Project> projects;
  final List<ProjectEntry> entries;
  final List<Task> tasks;
  final List<PlanBlock> plans;
  final List<Routine> routines;
  final List<RoutineRecord> routineRecords;
  final List<FocusSession> sessions;
  final List<TaskReminder> reminders;
  final List<String> areas;
  final List<RecurringSchedule> recurringSchedules;
  final List<ScheduleException> scheduleExceptions;
  final List<String> suppressedTaskIds;
  final QuietHours? quietHours;
  final ReminderDefault? reminderDefault;
  final PlanningPreferences? planningPreferences;
}
