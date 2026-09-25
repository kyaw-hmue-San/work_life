import 'records.dart';

String reminderDefaultLabel(ReminderDefault value) => switch (value) {
  ReminderDefault.none => 'No default reminder',
  ReminderDefault.atTime => 'At scheduled time',
  ReminderDefault.tenMinutesBefore => '10 minutes before',
  ReminderDefault.thirtyMinutesBefore => '30 minutes before',
  ReminderDefault.oneHourBefore => '1 hour before',
};

DateTime? defaultReminderTime(
  ReminderDefault value,
  DateTime scheduledAt,
) {
  final offset = switch (value) {
    ReminderDefault.none => null,
    ReminderDefault.atTime => Duration.zero,
    ReminderDefault.tenMinutesBefore => const Duration(minutes: 10),
    ReminderDefault.thirtyMinutesBefore => const Duration(minutes: 30),
    ReminderDefault.oneHourBefore => const Duration(hours: 1),
  };
  return offset == null ? null : scheduledAt.subtract(offset).toUtc();
}