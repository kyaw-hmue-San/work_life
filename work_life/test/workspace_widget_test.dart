import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/main.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/notifications/notification_driver.dart';
import 'package:work_life/notifications/reminder_notifications.dart';

import 'support/memory_workspace.dart';
import 'support/fake_notifications.dart';

void main() {
  testWidgets(
    'Today explains denied notification permission and retries after enabling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryWorkspace();
      repo.tasks.add(
        const Task(id: 'rest', title: 'Take a walk', area: 'Health'),
      );
      repo.reminders.add(
        TaskReminder(
          id: 'walk-reminder',
          taskId: 'rest',
          scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        ),
      );
      final driver = FakeNotifications()
        ..state = NotificationPermission.blocked;
      final notifications = ReminderNotifications(driver);
      await tester.pumpWidget(
        WorkLifeApp(repository: repo, notifications: notifications),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Device notifications are off'),
        findsOneWidget,
      );
      expect(driver.permissionRequests, 0);
      driver.state = NotificationPermission.allowed;
      await tester.ensureVisible(find.text('Enable notifications'));
      await tester.tap(find.text('Enable notifications'));
      await tester.pumpAndSettle();
      expect(driver.permissionRequests, 1);
      expect(driver.alerts, hasLength(1));
      expect(repo.reminders.single.deliveryStatus, 'scheduled');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  void roomy(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'capture becomes a linked task and completion agrees across project and Today',
    (tester) async {
      roomy(tester);
      final repo = MemoryWorkspace();
      final capture = Capture.create('Photo for form by Friday?');
      repo.captures.add(capture);
      final project = Project(
        id: newId(),
        title: 'Family paperwork',
        area: 'Relationships',
      );
      repo.projects.add(project);
      await tester.pumpWidget(WorkLifeApp(repository: repo));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Inbox').last);
      await tap(tester, find.text(capture.originalText));
      await tap(tester, find.text('Turn into a task'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Prepare photo',
      );
      await tap(
        tester,
        find.widgetWithText(DropdownButtonFormField<String>, 'Project'),
      );
      await tap(tester, find.text(project.title).last);
      await tap(tester, find.text('Save task'));
      expect(repo.tasks.single.captureId, capture.id);
      expect(repo.tasks.single.deadline, isNull);
      expect(repo.tasks.single.projectId, project.id);
      expect(repo.captures.single.originalText, capture.originalText);
      await tap(tester, find.text('Prepare photo'));
      expect(find.text('Original capture'), findsOneWidget);
      await tap(tester, find.text('Mark task completed'));
      expect(repo.tasks.single.status, TaskStatus.completed);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Projects'));
      await tap(tester, find.text(project.title));
      expect(find.text('Prepare photo'), findsOneWidget);
      expect(find.textContaining('completed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mobile navigation and large text stay usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: WorkLifeApp(repository: MemoryWorkspace()),
      ),
    );
    await tester.pumpAndSettle();
    for (final destination in [
      'Inbox',
      'Projects',
      'Planner',
      'More',
      'Today',
    ]) {
      await tap(
        tester,
        find.widgetWithText(NavigationDestination, destination),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reminder save retries, reschedules, cancels and removes without changing task',
    (tester) async {
      roomy(tester);
      final repo = MemoryWorkspace();
      final task = Task(
        id: newId(),
        title: 'Call family',
        area: 'Relationships',
        deadline: '2099-12-31',
      );
      repo.tasks.add(task);
      await tester.pumpWidget(WorkLifeApp(repository: repo));
      await tester.pumpAndSettle();
      await tap(tester, find.text(task.title));
      await tap(tester, find.text('Set reminder'));
      repo.failReminderSave = true;
      await tap(tester, find.text('Save reminder'));
      expect(
        find.textContaining('Couldn’t finish that change').first,
        findsOneWidget,
      );
      expect(repo.reminders, isEmpty);
      repo.failReminderSave = false;
      await tap(tester, find.text('Save reminder'));
      final first = repo.reminders.single;
      expect(first.scheduledAt.isUtc, isTrue);
      await tap(tester, find.text('Snooze'));
      await tap(tester, find.text('10 minutes'));
      expect(repo.reminders.single.id, first.id);
      expect(repo.reminders.single.scheduledAt, isNot(first.scheduledAt));
      expect(
        repo.reminders.single.scheduledAt.isAfter(DateTime.now().toUtc()),
        isTrue,
      );
      await tap(tester, find.text('Reschedule reminder'));
      await tap(tester, find.text('Choose date'));
      await tap(tester, find.byTooltip('Next month'));
      await tap(tester, find.text('15'));
      await tap(tester, find.text('OK'));
      await tap(tester, find.text('Save reminder'));
      expect(repo.reminders.single.id, first.id);
      expect(
        repo.reminders.single.scheduledAt.isAfter(first.scheduledAt),
        isTrue,
      );
      final changed = repo.reminders.single.scheduledAt;
      await tap(tester, find.text('Reschedule reminder'));
      await tap(tester, find.text('Cancel').last);
      expect(repo.reminders.single.scheduledAt, changed);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Upcoming ·'), findsOneWidget);
      await tap(tester, find.text(task.title).first);
      await tap(tester, find.text('Remove reminder'));
      expect(repo.reminders, isEmpty);
      expect(repo.tasks.single.status, TaskStatus.open);
      expect(repo.tasks.single.deadline, task.deadline);
      await tap(tester, find.text('Set reminder'));
      await tap(tester, find.text('Save reminder'));
      await tap(tester, find.text('Mark task completed'));
      expect(repo.reminders, isEmpty);
      expect(find.text('Set reminder'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('elapsed reminders remain pending after opening and returning', (
    tester,
  ) async {
    roomy(tester);
    final repo = MemoryWorkspace();
    final task = Task(id: newId(), title: 'Take a break', area: 'Rest');
    repo.tasks.add(task);
    repo.reminders.add(
      TaskReminder(
        id: newId(),
        taskId: task.id,
        scheduledAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    );
    await tester.pumpWidget(WorkLifeApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to revisit ·'), findsOneWidget);
    await tap(tester, find.text(task.title).first);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to revisit ·'), findsOneWidget);
    expect(repo.tasks.single.status, TaskStatus.open);
    expect(repo.reminders, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });
}
