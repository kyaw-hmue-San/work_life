import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';
import 'package:work_life/workspace/reminder_defaults.dart';
import 'package:work_life/ai/ai_proposals.dart';

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
  final aiOperations = <String>{};
  final recurringSchedules = <RecurringSchedule>[];
  final scheduleExceptions = <ScheduleException>[];
  PlanningPreferences planningPreferences = const PlanningPreferences();
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
    recurringSchedules: List.of(recurringSchedules),
    scheduleExceptions: List.of(scheduleExceptions),
    planningPreferences: planningPreferences,
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
        basis: reminder.basis,
        recurrence: reminder.recurrence,
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
    aiOperations.clear();
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
            basis: ReminderBasis.plannedTime,
          ),
        );
      }
    }
  }

  @override
  Future<void> removePlan(String id) async =>
      plans.removeWhere((v) => v.id == id);
  @override
  Future<void> saveRecurringSchedule(RecurringSchedule value) async {
    recurringSchedules.removeWhere((v) => v.id == value.id);
    recurringSchedules.add(value);
  }

  @override
  Future<void> saveRecurringSchedules(List<RecurringSchedule> values) async {
    for (final value in values) {
      recurringSchedules.removeWhere((v) => v.id == value.id);
      recurringSchedules.add(value);
    }
  }

  @override
  Future<void> removeRecurringSchedule(String id) async =>
      recurringSchedules.removeWhere((v) => v.id == id);
  @override
  Future<void> saveScheduleException(ScheduleException value) async {
    scheduleExceptions.removeWhere(
      (v) => v.scheduleId == value.scheduleId && v.day == value.day,
    );
    scheduleExceptions.add(value);
  }

  @override
  Future<void> savePlanningPreferences(PlanningPreferences value) async =>
      planningPreferences = value;
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

  String approvedArea(String? requested, {bool allowCreate = false}) {
    final wanted = requested?.trim().isNotEmpty == true
        ? requested!.trim()
        : 'Work';
    final existing = areas.where(
      (value) => value.toLowerCase() == wanted.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first;
    if (!allowCreate) {
      throw ArgumentError(
        'Review and approve the suggested Life Area before saving.',
      );
    }
    areas.add(wanted);
    return wanted;
  }

  @override
  Future<void> applyCaptureProposal(
    AiCaptureProposal proposal, {
    required String operationId,
    String? captureId,
  }) async {
    if (!aiOperations.add(operationId)) return;
    final area = approvedArea(
      proposal.task?.area ?? proposal.routine?.area,
      allowCreate: proposal.createArea,
    );
    if (proposal.routine case final routine?) {
      routines.add(
        Routine(
          id: newId(),
          title: routine.title,
          area: area,
          window: routine.window,
          alternative: routine.minimum,
          normal: routine.normal,
          strong: routine.strong,
          createdDay: dayKey(DateTime.now()),
        ),
      );
      return;
    }
    final proposalTask = proposal.task;
    if (proposalTask == null) throw ArgumentError('Unsupported proposal');
    final task = Task(
      id: newId(),
      title: proposalTask.title,
      area: area,
      captureId: captureId,
      deadline: proposalTask.deadline,
      minutes: proposalTask.minutes,
      priority: TaskPriority.values.byName(proposalTask.priority),
      checklist: proposalTask.checklist
          .map((text) => ChecklistItem(id: newId(), text: text))
          .toList(),
    );
    tasks.add(task);
    if (proposalTask.reminder != null) {
      reminders.add(
        TaskReminder(
          id: newId(),
          taskId: task.id,
          scheduledAt: DateTime.parse(proposalTask.reminder!).toUtc(),
        ),
      );
    }
  }

  @override
  Future<void> applyProjectProposal(
    AiProjectProposal proposal, {
    required String operationId,
    String? captureId,
    String? targetProjectId,
  }) async {
    if (!aiOperations.add(operationId)) return;
    final area = approvedArea(proposal.area, allowCreate: proposal.createArea);
    final project = Project(
      id: targetProjectId ?? newId(),
      title: proposal.title,
      area: area,
      description: proposal.description,
    );
    projects.removeWhere((value) => value.id == project.id);
    projects.add(project);
    var first = true;
    for (final item in proposal.tasks.where((task) => task.included)) {
      final previous = item.taskId == null
          ? null
          : tasks.where((value) => value.id == item.taskId).firstOrNull;
      if (item.change == AiProjectChange.remove) {
        if (previous == null) throw ArgumentError('Task missing');
        tasks
          ..remove(previous)
          ..add(
            Task(
              id: previous.id,
              title: previous.title,
              area: previous.area,
              captureId: previous.captureId,
              deadline: previous.deadline,
              minutes: previous.minutes,
              notes: previous.notes,
              priority: previous.priority,
              status: TaskStatus.cancelled,
              checklist: previous.checklist,
            ),
          );
        continue;
      }
      if (previous != null) tasks.remove(previous);
      tasks.add(
        Task(
          id: previous?.id ?? newId(),
          title: item.title,
          area: item.area == null
              ? area
              : approvedArea(
                  item.area,
                  allowCreate:
                      proposal.createArea &&
                      item.area!.trim().toLowerCase() == area.toLowerCase(),
                ),
          projectId: project.id,
          captureId: previous?.captureId ?? (first ? captureId : null),
          deadline: item.deadline,
          minutes: item.minutes,
          notes: 'AI suggested priority: ${item.priority}',
          priority: TaskPriority.values.byName(item.priority),
          status: previous?.status ?? TaskStatus.open,
          checklist: item.checklist
              .map((text) => ChecklistItem(id: newId(), text: text))
              .toList(),
        ),
      );
      first = false;
    }
  }

  @override
  Future<void> applyScheduleProposal(
    AiScheduleProposal proposal, {
    required String operationId,
  }) async {
    if (!aiOperations.add(operationId)) return;
    for (final event in proposal.events.where((value) => value.included)) {
      if (event.date == null || event.start == null) {
        throw ArgumentError('Every selected block needs a date and start time');
      }
      final day = DateTime.parse(event.date!);
      final startParts = event.start!.split(':').map(int.parse).toList();
      final endParts = (event.end ?? event.start!)
          .split(':')
          .map(int.parse)
          .toList();
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        startParts[0],
        startParts[1],
      );
      var end = DateTime(
        day.year,
        day.month,
        day.day,
        endParts[0],
        endParts[1],
      );
      if (!end.isAfter(start)) {
        end = event.end == null
            ? start.add(const Duration(minutes: 25))
            : end.add(const Duration(days: 1));
      }
      final task = event.taskId == null
          ? null
          : tasks.where((value) => value.id == event.taskId).firstOrNull;
      final block = PlanBlock(
        id: event.planId ?? newId(),
        title: event.title,
        taskId: task?.id,
        start: start,
        minutes: end.difference(start).inMinutes,
        area: task?.area ?? event.area ?? 'Work',
      );
      await savePlan(block);
    }
  }
}
