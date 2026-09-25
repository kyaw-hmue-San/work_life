import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';
import 'package:work_life/workspace/reminder_defaults.dart';

class MemoryWorkspace implements WorkspaceRepository {
  // Existing regression fixtures represent returning workspaces.
  MemoryWorkspace({this.onboardingCompleted = true});
  bool onboardingCompleted;
  bool failOnboarding = false;
  @override
  Future<void> completeOnboarding({ReminderDefault? reminderDefault}) async {
    if (failOnboarding) throw StateError('Setup save failed');
    if (reminderDefault != null) this.reminderDefault = reminderDefault;
    onboardingCompleted = true;
  }

  final captures = <Capture>[];
  final tasks = <Task>[];
  final entries = <ProjectEntry>[];
  final projects = <Project>[];
  final plans = <PlanBlock>[];
  final routines = <Routine>[];
  final records = <RoutineRecord>[];
  final sessions = <FocusSession>[];
  final reminders = <TaskReminder>[];
  QuietHours quietHours = const QuietHours();
  ReminderDefault reminderDefault = ReminderDefault.none;
  final suppressedTasks = <String>{};
  bool failReminderSave = false;
  final areas = ['Work', 'Study', 'Health', 'Relationships', 'Rest'];
  @override
  Future<List<Capture>> load() async => List.of(captures);
  @override
  Future<void> save(Capture c) async {
    captures.removeWhere((v) => v.id == c.id);
    captures.add(c);
  }

  @override
  Future<WorkspaceData> readWorkspace() async => WorkspaceData(
    onboardingCompleted: onboardingCompleted,
    tasks: List.of(tasks),
    entries: List.of(entries),
    projects: List.of(projects),
    plans: List.of(plans),
    routines: List.of(routines),
    routineRecords: List.of(records),
    sessions: List.of(sessions),
    areas: List.of(areas),
    reminders: List.of(reminders),
    suppressedTaskIds: [...suppressedTasks]..sort(),
    quietHours: quietHours,
    reminderDefault: reminderDefault,
  );
  @override
  Future<({List<Capture> captures, WorkspaceData workspace})>
  readExportSnapshot() async =>
      (captures: await load(), workspace: await readWorkspace());

  @override
  Future<void> saveEntry(ProjectEntry e) async {
    entries.removeWhere((v) => v.id == e.id);
    entries.add(e);
  }

  @override
  Future<void> saveTask(Task t) async {
    tasks.removeWhere((v) => v.id == t.id);
    tasks.add(t);
    if (!t.active) reminders.removeWhere((r) => r.taskId == t.id);
  }

  @override
  Future<void> saveReminder(TaskReminder reminder) async {
    if (failReminderSave) throw StateError('Test save failure');
    reminders.removeWhere((r) => r.taskId == reminder.taskId);
    reminders.add(reminder);
    suppressedTasks.remove(reminder.taskId);
  }

  @override
  Future<void> removeReminder(String taskId) async => {
    reminders.removeWhere((r) => r.taskId == taskId),
    suppressedTasks.add(taskId),
  };

  @override
  Future<void> recordReminderDelivery(
    TaskReminder reminder,
    String status,
  ) async {
    final index = reminders.indexWhere(
      (r) => r.id == reminder.id && r.scheduledAt == reminder.scheduledAt,
    );
    if (index >= 0) {
      reminders[index] = TaskReminder(
        id: reminder.id,
        taskId: reminder.taskId,
        scheduledAt: reminder.scheduledAt,
        deliveryStatus: status,
        origin: reminder.origin,
      );
    }
  }

  @override
  Future<void> saveQuietHours(QuietHours value) async {
    quietHours = value;
  }

  @override
  Future<void> saveReminderDefault(ReminderDefault value) async {
    reminderDefault = value;
  }

  @override
  Future<void> clearLocalData() async {
    onboardingCompleted = false;
    captures.clear();
    tasks.clear();
    entries.clear();
    projects.clear();
    plans.clear();
    routines.clear();
    records.clear();
    sessions.clear();
    reminders.clear();
    suppressedTasks.clear();
    areas
      ..clear()
      ..addAll(['Work', 'Study', 'Health', 'Relationships', 'Rest']);
    quietHours = const QuietHours();
    reminderDefault = ReminderDefault.none;
  }

  @override
  Future<void> saveProject(Project p) async {
    projects.removeWhere((v) => v.id == p.id);
    projects.add(p);
  }

  @override
  Future<void> savePlan(PlanBlock p) async {
    plans.removeWhere((v) => v.id == p.id);
    plans.add(p);
    if (p.taskId != null &&
        reminders.every((r) => r.taskId != p.taskId) &&
        !suppressedTasks.contains(p.taskId)) {
      final scheduledAt = defaultReminderTime(reminderDefault, p.start);
      if (scheduledAt != null && scheduledAt.isAfter(DateTime.now().toUtc())) {
        reminders.add(
          TaskReminder(
            id: newId(),
            taskId: p.taskId!,
            scheduledAt: scheduledAt,
            origin: ReminderOrigin.defaulted,
          ),
        );
      }
    }
  }

  @override
  Future<void> removePlan(String id) async =>
      plans.removeWhere((v) => v.id == id);
  @override
  Future<void> saveRoutine(Routine r) async {
    routines.removeWhere((v) => v.id == r.id);
    routines.add(r);
  }

  @override
  Future<void> recordRoutine(RoutineRecord r) async {
    records.removeWhere((v) => v.routineId == r.routineId && v.day == r.day);
    records.add(r);
  }

  @override
  Future<void> saveSession(FocusSession s) async {
    sessions.removeWhere((v) => v.id == s.id);
    sessions.add(s);
  }

  @override
  Future<void> addArea(String name) async => areas.add(name);
}
