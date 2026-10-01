import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/local_data_export.dart';
import 'package:work_life/workspace/records.dart';

import 'support/memory_workspace.dart';

void main() {
  test('empty export is versioned and contains reset settings', () async {
    final export = await LocalDataExport(
      MemoryWorkspace(),
      now: () => DateTime.utc(2030, 1, 1),
    ).buildJson();
    final decoded = jsonDecode(export) as Map<String, dynamic>;
    expect(decoded['formatVersion'], 1);
    expect(decoded['exportedAt'], '2030-01-01T00:00:00.000Z');
    expect(decoded['app'], 'Work Life');
    final data = decoded['data'] as Map<String, dynamic>;
    expect(data['tasks'], isEmpty);
    expect(data['settings']['reminderDefault'], 'none');
    expect(data['settings']['quietHours']['enabled'], isFalse);
  });

  test(
    'populated export preserves IDs, relationships, nullable values, and text',
    () async {
      final repo = MemoryWorkspace()
        ..reminderDefault = ReminderDefault.thirtyMinutesBefore
        ..quietHours = const QuietHours(
          enabled: true,
          startMinute: 23 * 60,
          endMinute: 7 * 60,
        );
      final capture = Capture.create('Line 1\n"special" ✓');
      final project = Project(id: 'project-1', title: 'Project', area: 'Work');
      final task = Task(
        id: 'task-1',
        title: 'Task',
        area: 'Work',
        projectId: project.id,
        captureId: capture.id,
        checklist: [const ChecklistItem(id: 'check-1', text: 'Prepare')],
      );
      repo.captures.add(capture);
      repo.projects.add(project);
      repo.tasks.add(task);
      repo.reminders.add(
        TaskReminder(
          id: 'reminder-1',
          taskId: 'task-1',
          scheduledAt: DateTime.utc(2030, 1, 2, 13, 30),
          origin: ReminderOrigin.defaulted,
        ),
      );
      repo.suppressedTasks.add('task-other');
      final decoded = jsonDecode(
        await LocalDataExport(repo, now: () => DateTime.utc(2030)).buildJson(),
      ) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;
      expect(data['captures'][0]['originalText'], contains('"special"'));
      expect(data['tasks'][0]['id'], 'task-1');
      expect(data['tasks'][0]['projectId'], 'project-1');
      expect(data['tasks'][0]['captureId'], capture.id);
      expect(data['tasks'][0]['deadline'], isNull);
      expect(data['reminders'][0]['origin'], 'defaulted');
      expect(data['reminderSuppressions'], ['task-other']);
      expect(data['settings']['reminderDefault'], 'thirtyMinutesBefore');
      expect(data['settings']['quietHours']['startMinute'], 23 * 60);
      expect(exportContainsSecret(decoded), isFalse);
    },
  );

  test('readable exports separate report content from task analysis', () async {
    final repo = MemoryWorkspace();
    repo.projects.add(
      const Project(
        id: 'birthday',
        title: 'Birthday plan',
        area: 'Relationships',
        description: 'Make the day special.',
      ),
    );
    repo.tasks.add(
      const Task(
        id: 'cake',
        title: 'Order "special" cake',
        area: 'Relationships',
        projectId: 'birthday',
        deadline: '2030-05-03',
        notes: 'Confirm dietary needs, then order.',
        checklist: [ChecklistItem(id: 'size', text: 'Choose size')],
      ),
    );
    repo.recurringSchedules.add(
      const RecurringSchedule(
        id: 'class',
        title: 'Software class',
        type: RecurringScheduleType.classSession,
        weekday: DateTime.monday,
        startTime: '09:00',
        endTime: '10:30',
        startDate: '2030-01-01',
      ),
    );
    final exporter = LocalDataExport(repo, now: () => DateTime.utc(2030));
    final markdown = await exporter.buildMarkdown();
    expect(markdown, contains('# Work Life report'));
    expect(markdown, contains('### Birthday plan'));
    expect(markdown, contains('Order "special" cake'));
    expect(markdown, contains('Monday 09:00–10:30'));
    expect(markdown, isNot(contains('formatVersion')));

    final csv = await exporter.buildTasksCsv();
    expect(csv, startsWith('"Title","Status","Priority"'));
    expect(csv, contains('"Order ""special"" cake"'));
    expect(csv, contains('"Birthday plan"'));
    expect(csv, contains('"[ ] Choose size"'));
  });
}

bool exportContainsSecret(Map<String, dynamic> value) =>
    value.keys.any((key) => key.toLowerCase().contains('token')) ||
    value.values.any(
      (item) => item is Map<String, dynamic>
          ? exportContainsSecret(item)
          : item is List<dynamic>
          ? item.any(
              (entry) =>
                  entry is Map<String, dynamic> && exportContainsSecret(entry),
            )
          : false,
    );
