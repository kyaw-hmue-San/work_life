import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/notifications/quiet_hours.dart';
import 'package:work_life/workspace/records.dart';

void main() {
  final overnight = const QuietHours(
    enabled: true,
    startMinute: 23 * 60,
    endMinute: 7 * 60,
  );

  test('disabled quiet hours leave the reminder unchanged', () {
    final reminder = DateTime(2030, 1, 1, 23, 30);
    expect(effectiveReminderTime(reminder, const QuietHours()), reminder);
  });

  test('overnight quiet hours include start and exclude end', () {
    expect(
      effectiveReminderTime(DateTime(2030, 1, 1, 23), overnight),
      DateTime(2030, 1, 2, 7).toUtc(),
    );
    expect(
      effectiveReminderTime(DateTime(2030, 1, 2, 6, 59), overnight),
      DateTime(2030, 1, 2, 7).toUtc(),
    );
    final atEnd = DateTime(2030, 1, 2, 7);
    expect(effectiveReminderTime(atEnd, overnight), atEnd);
  });

  test('same-day quiet hours delay only reminders inside the period', () {
    const quiet = QuietHours(enabled: true, startMinute: 9 * 60, endMinute: 17 * 60);
    expect(
      effectiveReminderTime(DateTime(2030, 1, 1, 9), quiet),
      DateTime(2030, 1, 1, 17).toUtc(),
    );
    expect(
      effectiveReminderTime(DateTime(2030, 1, 1, 17), quiet),
      DateTime(2030, 1, 1, 17),
    );
    expect(
      effectiveReminderTime(DateTime(2030, 1, 1, 8, 59), quiet),
      DateTime(2030, 1, 1, 8, 59),
    );
  });
}