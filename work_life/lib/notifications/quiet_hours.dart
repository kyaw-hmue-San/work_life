import '../workspace/records.dart';

/// Returns the local wall-clock time at which a reminder may be delivered.
/// The original reminder remains unchanged; only the device schedule moves.
DateTime effectiveReminderTime(
  DateTime reminder,
  QuietHours quietHours,
) {
  if (!quietHours.enabled || quietHours.startMinute == quietHours.endMinute) {
    return reminder;
  }
  final local = reminder.toLocal();
  final minute = local.hour * 60 + local.minute;
  final start = quietHours.startMinute;
  final end = quietHours.endMinute;
  DateTime? quietEnd;
  if (start < end) {
    if (minute >= start && minute < end) {
      quietEnd = DateTime(local.year, local.month, local.day).add(
        Duration(minutes: end),
      );
    }
  } else if (minute >= start) {
    quietEnd = DateTime(local.year, local.month, local.day + 1).add(
      Duration(minutes: end),
    );
  } else if (minute < end) {
    quietEnd = DateTime(local.year, local.month, local.day).add(
      Duration(minutes: end),
    );
  }
  return quietEnd?.toUtc() ?? reminder;
}