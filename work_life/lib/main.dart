import 'package:flutter/material.dart';

import 'accounts/account_host.dart';
import 'accounts/account_service.dart';
import 'notifications/notification_driver.dart';
import 'notifications/reminder_notifications.dart';
export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final accounts = await initializeAccounts();
  runApp(
    AccountHost(
      accounts: accounts,
      notifications: ReminderNotifications(LocalNotificationDriver()),
    ),
  );
}
