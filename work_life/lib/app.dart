import 'package:flutter/material.dart';

import 'notifications/reminder_notifications.dart';
import 'sync/workspace_sync_coordinator.dart';

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
    this.sync,
  });
  final WorkspaceRepository repository;
  final WidgetBuilder? accountBuilder;
  final String? accountLabel, accountNotice;
  final Widget? homeOverride;
  final ReminderNotifications? notifications;
  final String notificationScope;
  final WorkspaceSyncCoordinator? sync;

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
        cardTheme: CardThemeData(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) =>
          _KeyboardDismissRegion(child: child ?? const SizedBox.shrink()),
      home:
          homeOverride ??
          WorkspaceScreen(
            repository: repository,
            accountBuilder: accountBuilder,
            accountLabel: accountLabel,
            accountNotice: accountNotice,
            notifications: notifications,
            notificationScope: notificationScope,
            sync: sync,
          ),
    );
  }
}

/// Gives every screen, dialog and bottom sheet the same keyboard behavior:
/// tapping outside the focused editor or dragging a scrollable dismisses it.
class _KeyboardDismissRegion extends StatelessWidget {
  const _KeyboardDismissRegion({required this.child});
  final Widget child;

  void _dismissOutside(PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    final renderObject = focus?.context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final local = renderObject.globalToLocal(event.position);
    if (!(Offset.zero & renderObject.size).contains(local)) {
      focus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _dismissOutside,
    child: NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return false;
      },
      child: child,
    ),
  );
}
