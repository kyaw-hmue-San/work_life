import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/notifications/snooze.dart';
import 'package:work_life/workspace/records.dart';

void main() {
  final now = DateTime(2030, 1, 1, 12, 15);
  final reminder = TaskReminder(
    id: 'reminder-1',
    taskId: 'task-1',
    scheduledAt: DateTime(2030, 1, 1, 13).toUtc(),
  );

  test('snooze choices calculate future local times', () {
    expect(
      snoozeTime(SnoozeOption.tenMinutes, now),
      DateTime(2030, 1, 1, 12, 25),
    );
    expect(
      snoozeTime(SnoozeOption.thirtyMinutes, now),
      DateTime(2030, 1, 1, 12, 45),
    );
    expect(snoozeTime(SnoozeOption.oneHour, now), DateTime(2030, 1, 1, 13, 15));
    expect(
      snoozeTime(SnoozeOption.tomorrow, now),
      DateTime(2030, 1, 2, 12, 15),
    );
  });

  test(
    'snooze preserves task and reminder identity while changing its time',
    () {
      final snoozed = snoozedReminder(
        reminder,
        SnoozeOption.thirtyMinutes,
        now: now,
      );
      expect(snoozed.id, reminder.id);
      expect(snoozed.taskId, reminder.taskId);
      expect(snoozed.scheduledAt, DateTime(2030, 1, 1, 12, 45).toUtc());
    },
  );
}
