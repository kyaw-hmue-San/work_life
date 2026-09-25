import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';

Future<void> populateWorkspace(WorkspaceRepository repo) async {
  await repo.addArea('Creative');
  await repo.save(
    Capture(
      id: 'capture',
      originalText: '"Quote"\nไทย \\ ✓',
      createdAt: DateTime.utc(2030),
    ),
  );
  await repo.saveProject(
    const Project(
      id: 'project',
      title: 'Project',
      area: 'Creative',
      description: 'Notes',
    ),
  );
  await repo.saveEntry(
    const ProjectEntry(
      id: 'entry',
      projectId: 'project',
      title: 'Idea',
      body: 'Body',
      kind: 'idea',
      captureId: 'capture',
    ),
  );
  await repo.saveEntry(
    const ProjectEntry(
      id: 'related',
      projectId: 'project',
      title: 'Link',
      body: '',
      kind: 'note',
      relatedId: 'entry',
    ),
  );
  await repo.saveTask(
    const Task(
      id: 'task',
      title: 'Task',
      area: 'Creative',
      projectId: 'project',
      captureId: 'capture',
      entryId: 'entry',
      deadline: '2035-01-02',
      checklist: [ChecklistItem(id: 'check', text: 'Prepare', done: true)],
    ),
  );
  await repo.saveTask(
    const Task(id: 'suppressed', title: 'No reminder', area: 'Rest'),
  );
  await repo.removeReminder('suppressed');
  await repo.savePlan(
    PlanBlock(
      id: 'plan',
      title: 'Plan',
      taskId: 'task',
      start: DateTime.utc(2035, 1, 1),
      minutes: 30,
      area: 'Creative',
    ),
  );
  await repo.savePlan(
    PlanBlock(
      id: 'personal',
      title: 'Rest',
      start: DateTime.utc(2035, 1, 2),
      minutes: 30,
      area: 'Rest',
      fixed: true,
    ),
  );
  await repo.saveRoutine(
    const Routine(
      id: 'routine',
      title: 'Walk',
      area: 'Health',
      window: 'Morning',
      alternative: 'Short walk',
      createdDay: '2030-01-01',
    ),
  );
  await repo.recordRoutine(
    const RoutineRecord(
      routineId: 'routine',
      day: '2030-01-01',
      outcome: 'done',
      area: 'Health',
    ),
  );
  await repo.saveSession(
    FocusSession(
      id: 'session',
      taskId: 'task',
      minutes: 30,
      startedAt: DateTime.utc(2030),
      runningSince: DateTime.utc(2030),
      seconds: 42,
      notes: 'Focus notes',
      area: 'Creative',
    ),
  );
  await repo.saveReminder(
    TaskReminder(
      id: 'reminder',
      taskId: 'task',
      scheduledAt: DateTime.utc(2035),
      origin: ReminderOrigin.explicit,
    ),
  );
  await repo.saveQuietHours(
    const QuietHours(enabled: true, startMinute: 1320, endMinute: 360),
  );
  await repo.saveReminderDefault(ReminderDefault.thirtyMinutesBefore);
}
