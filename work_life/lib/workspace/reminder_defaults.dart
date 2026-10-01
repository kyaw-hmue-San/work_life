import 'records.dart';

String reminderDefaultLabel(ReminderDefault value) => switch (value) {
  ReminderDefault.none => 'No default reminder',
  ReminderDefault.atTime => 'At scheduled time',
  ReminderDefault.tenMinutesBefore => '10 minutes before',
  ReminderDefault.thirtyMinutesBefore => '30 minutes before',
  ReminderDefault.oneHourBefore => '1 hour before',
};

DateTime? defaultReminderTime(ReminderDefault value, DateTime scheduledAt) {
  final offset = switch (value) {
    ReminderDefault.none => null,
    ReminderDefault.atTime => Duration.zero,
    ReminderDefault.tenMinutesBefore => const Duration(minutes: 10),
    ReminderDefault.thirtyMinutesBefore => const Duration(minutes: 30),
    ReminderDefault.oneHourBefore => const Duration(hours: 1),
  };
  return offset == null ? null : scheduledAt.subtract(offset).toUtc();
}

/// Date-only deadlines notify at 9:00 AM local time, adjusted by the user's
/// existing reminder default (for example, 30 minutes before means 8:30 AM).
DateTime? dateOnlyDueReminderTime(ReminderDefault value, String deadline) {
  final date = DateTime.tryParse(deadline);
  if (date == null) return null;
  return defaultReminderTime(
    value,
    DateTime(date.year, date.month, date.day, 9),
  );
}
