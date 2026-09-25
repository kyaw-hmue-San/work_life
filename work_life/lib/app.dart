import 'package:flutter/material.dart';

import 'notifications/reminder_notifications.dart';

import 'workspace/workspace_repository.dart';
import 'workspace/workspace_screen.dart';

class WorkLifeApp extends StatelessWidget {
  const WorkLifeApp({
    super.key,
    required this.repository,
    this.accountBuilder,
    this.accountLabel,
    this.accountNotice,
    this.homeOverride,
    this.notifications,
    this.notificationScope = 'guest',
  });
  final WorkspaceRepository repository;
  final WidgetBuilder? accountBuilder;
  final String? accountLabel, accountNotice;
  final Widget? homeOverride;
  final ReminderNotifications? notifications;
  final String notificationScope;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(seedColor: const Color(0xFF345F4C));
    return MaterialApp(
      title: 'Work Life',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFFF8F7F2),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF8F7F2)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      ),
      home:
          homeOverride ??
          WorkspaceScreen(
            repository: repository,
            accountBuilder: accountBuilder,
            accountLabel: accountLabel,
            accountNotice: accountNotice,
            notifications: notifications,
            notificationScope: notificationScope,
          ),
    );
  }
}
