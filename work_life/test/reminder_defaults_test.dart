import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/reminder_defaults.dart';

void main() {
  final scheduled = DateTime(2030, 1, 2, 14);

  test('supported defaults calculate the expected reminder time', () {
    expect(defaultReminderTime(ReminderDefault.none, scheduled), isNull);
    expect(
      defaultReminderTime(ReminderDefault.atTime, scheduled),
      scheduled.toUtc(),
    );
    expect(
      defaultReminderTime(ReminderDefault.tenMinutesBefore, scheduled),
      DateTime(2030, 1, 2, 13, 50).toUtc(),
    );
    expect(
      defaultReminderTime(ReminderDefault.thirtyMinutesBefore, scheduled),
      DateTime(2030, 1, 2, 13, 30).toUtc(),
    );
    expect(
      defaultReminderTime(ReminderDefault.oneHourBefore, scheduled),
      DateTime(2030, 1, 2, 13).toUtc(),
    );
  });

  test('subtraction can cross into the previous calendar day', () {
    final scheduled = DateTime(2030, 1, 2, 0, 15);
    expect(
      defaultReminderTime(ReminderDefault.thirtyMinutesBefore, scheduled),
      DateTime(2030, 1, 1, 23, 45).toUtc(),
    );
  });
}
