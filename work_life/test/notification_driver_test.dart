import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:work_life/notifications/notification_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var blockedChannel = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    blockedChannel = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getNotificationChannels') {
            return blockedChannel
                ? [
                    {
                      'id': 'task_reminders',
                      'name': 'Task reminders',
                      'showBadge': false,
                      'importance': 0,
                      'bypassDnd': false,
                      'playSound': true,
                      'enableLights': false,
                      'enableVibration': true,
                      'ledColor': 0,
                      'audioAttributesUsage': 5,
                    },
                  ]
                : [];
          }
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android schedules a UTC instant with inexact mode and requests permission only explicitly', () async {
    final driver = LocalNotificationDriver();
    expect(await driver.permission(), NotificationPermission.allowed);
    expect(
      calls.any((c) => c.method == 'requestNotificationsPermission'),
      isFalse,
    );
    await driver.permission(request: true);
    expect(
      calls.where((c) => c.method == 'requestNotificationsPermission'),
      hasLength(1),
    );
    await driver.schedule(
      123,
      DateTime.now().toUtc().add(const Duration(days: 1)),
      'test-payload',
    );
    final args =
        calls.singleWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    expect(args['timeZoneName'], 'Etc/UTC');
    expect(
      (args['platformSpecifics'] as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
    expect(args['payload'], 'test-payload');
    expect(args['matchDateTimeComponents'], isNull);
  });

  test(
    'disabled reminder channel is blocked even if app permission is allowed',
    () async {
      blockedChannel = true;
      expect(
        await LocalNotificationDriver().permission(),
        NotificationPermission.blocked,
      );
    },
  );
}
