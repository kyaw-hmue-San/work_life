import '../workspace/records.dart';

enum SnoozeOption { tenMinutes, thirtyMinutes, oneHour, tomorrow }

String snoozeLabel(SnoozeOption option) => switch (option) {
  SnoozeOption.tenMinutes => '10 minutes',
  SnoozeOption.thirtyMinutes => '30 minutes',
  SnoozeOption.oneHour => '1 hour',
  SnoozeOption.tomorrow => 'Tomorrow',
};

DateTime snoozeTime(SnoozeOption option, DateTime now) {
  final local = now.toLocal();
  return switch (option) {
    SnoozeOption.tenMinutes => local.add(const Duration(minutes: 10)),
    SnoozeOption.thirtyMinutes => local.add(const Duration(minutes: 30)),
    SnoozeOption.oneHour => local.add(const Duration(hours: 1)),
    SnoozeOption.tomorrow => DateTime(
      local.year,
      local.month,
      local.day + 1,
      local.hour,
      local.minute,
    ),
  };
}

TaskReminder snoozedReminder(
  TaskReminder reminder,
  SnoozeOption option, {
  DateTime? now,
}) => TaskReminder(
  id: reminder.id,
  taskId: reminder.taskId,
  scheduledAt: snoozeTime(option, now ?? DateTime.now()).toUtc(),
);