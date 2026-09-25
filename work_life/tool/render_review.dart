// Run explicitly: flutter test tool/render_review.dart
// Writes deterministic, synthetic review screenshots under build/review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/main.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/notifications/reminder_notifications.dart';

import '../test/support/memory_workspace.dart';
import '../test/support/fake_notifications.dart';

void main() {
  testWidgets('render the five mobile destinations with synthetic records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in {
      'Roboto': '/Users/rioo/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      'MaterialIcons': '/Users/rioo/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(font.value);
      if (file.existsSync()) {
        final loader = FontLoader(font.key)
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        await tester.runAsync(() => loader.load());
      }
    }
    final repo = MemoryWorkspace();
    final day = DateTime.now();
    final project = Project(
      id: 'project',
      title: 'Restaurant software',
      area: 'Work',
      description: 'Make checkout a little smoother.',
    );
    repo.projects.add(project);
    repo.tasks.add(
      Task(
        id: 'bug',
        title: 'Investigate the checkout timeout',
        area: 'Work',
        projectId: project.id,
        deadline: dayKey(day),
        minutes: 30,
      ),
    );
    repo.tasks.add(
      const Task(
        id: 'family',
        title: 'Prepare the photo for our form',
        area: 'Relationships',
        minutes: 15,
      ),
    );
    repo.plans.add(
      PlanBlock(
        id: 'break',
        title: 'Lunch away from the screen',
        start: DateTime(day.year, day.month, day.day, 12, 30),
        minutes: 45,
        area: 'Rest',
      ),
    );
    repo.routines.add(
      Routine(
        id: 'walk',
        title: 'A little movement',
        area: 'Health',
        window: 'After lunch',
        alternative: 'A five-minute walk',
        createdDay: dayKey(day),
      ),
    );
    repo.captures.add(
      Capture.create(
        'Could the checkout timeout be a retry issue? Check the request logs.',
      ),
    );
    final boundaryKey = GlobalKey();
    repo.reminders.add(
      TaskReminder(
        id: 'family-reminder',
        taskId: 'family',
        scheduledAt: day.toUtc().add(const Duration(hours: 1)),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: WorkLifeApp(
          repository: repo,
          notifications: ReminderNotifications(FakeNotifications()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Directory('build/review').createSync(recursive: true);
    for (final name in ['Today', 'Inbox', 'Projects', 'Planner', 'More']) {
      await tester.tap(find.widgetWithText(NavigationDestination, name));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/review/${name.toLowerCase()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
  });
}
