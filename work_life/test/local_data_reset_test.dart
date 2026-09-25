import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/notifications/reminder_notifications.dart';
import 'package:work_life/workspace/local_data_export.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_model.dart';
import 'package:work_life/workspace/workspace_repository.dart';

import 'support/fake_notifications.dart';
import 'support/memory_workspace.dart';
import 'support/populated_workspace.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late SqliteWorkspaceRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('work_life_reset_');
    repo = SqliteWorkspaceRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/workspace.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test('all persisted categories export and reset, survive reopen, and allow reuse', () async {
    await populateWorkspace(repo);
    final exporter = LocalDataExport(repo, now: () => DateTime.utc(2030));
    final json = await exporter.buildJson();
    expect(await exporter.buildJson(), json);
    final data = (jsonDecode(json) as Map<String, dynamic>)['data'];
    expect(data['captures'].single['originalText'], '"Quote"\nไทย \\ ✓');
    expect(data['projectEntries'][1]['relatedId'], 'entry');
    expect(data['tasks'][1]['entryId'], 'entry');
    expect(data['tasks'][1]['checklist'].single, {
      'id': 'check',
      'text': 'Prepare',
      'done': true,
    });
    expect(data['tasks'][1]['deadline'], '2035-01-02');
    expect(data['tasks'][0]['deadline'], isNull);
    expect(data['planner'][0]['taskId'], isNull);
    expect(data['planner'][1]['taskId'], 'task');
    expect(data['planner'][1]['start'], '2035-01-01T00:00:00.000Z');
    expect(data['focusSessions'].single['taskId'], 'task');
    expect(
      data['focusSessions'].single['runningSince'],
      '2030-01-01T00:00:00.000Z',
    );
    expect(data['focusSessions'].single['outcome'], isNull);
    expect(data['routineRecords'].single['routineId'], 'routine');
    expect(data['routines'].single['id'], 'routine');
    expect(data['settings']['quietHours'], {
      'enabled': true,
      'startMinute': 1320,
      'endMinute': 360,
    });
    expect(data['reminders'].single.keys.toSet(), {
      'id',
      'taskId',
      'scheduledAt',
      'origin',
    });
    expect(data.keys.toSet(), {
      'captures',
      'projects',
      'projectEntries',
      'tasks',
      'planner',
      'focusSessions',
      'routines',
      'routineRecords',
      'lifeAreas',
      'reminders',
      'reminderSuppressions',
      'settings',
    });
    for (final forbidden in [
      'deliveryStatus',
      'delivery_status',
      'notificationId',
      'token',
      'password',
      'namespace',
      'databasePath',
      'rowid',
    ]) {
      expect(json, isNot(contains('"$forbidden"')));
    }
    final driver = FakeNotifications();
    final service = ReminderNotifications(
      driver,
      now: () => DateTime.utc(2030),
    );
    final model = WorkspaceModel(repo, notifications: service);
    await model.load();
    expect(driver.alerts, hasLength(1));
    driver.active.add(123);
    expect(await model.deleteLocalData(), isTrue);
    expect(model.data.tasks, isEmpty);
    expect(model.resetRevision, 1);
    expect(driver.alerts, isEmpty);
    expect(driver.active, isEmpty);
    await repo.close();
    final reset =
        jsonDecode(await exporter.buildJson())['data'] as Map<String, dynamic>;
    for (final entry in reset.entries) {
      if (entry.key != 'lifeAreas' && entry.key != 'settings') {
        expect(entry.value, isEmpty, reason: entry.key);
      }
    }
    expect(reset['lifeAreas'], [
      'Health',
      'Relationships',
      'Rest',
      'Study',
      'Work',
    ]);
    expect(reset['settings'], {
      'quietHours': {'enabled': false, 'startMinute': 1380, 'endMinute': 420},
      'reminderDefault': 'none',
    });
    await model.refreshNotifications();
    expect(driver.alerts, isEmpty);
    await repo.saveTask(
      const Task(id: 'new', title: 'Start again', area: 'Work'),
    );
    expect((await repo.readWorkspace()).tasks.single.id, 'new');
    model.dispose();
    await service.idle;
    service.dispose();
  });

  test('SQL failure rolls all categories and settings back', () async {
    await populateWorkspace(repo);
    final exporter = LocalDataExport(repo, now: () => DateTime.utc(2030));
    final before = await exporter.buildJson();
    final db = await repo.database.open();
    await db.execute(
      "CREATE TRIGGER block_reset BEFORE DELETE ON captures BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(repo.clearLocalData(), throwsA(isA<DatabaseException>()));
    expect(await exporter.buildJson(), before);
    await repo.close();
    expect(await exporter.buildJson(), before);
  });

  test(
    'notification cancellation failure prevents deletion and permits retry',
    () async {
      await populateWorkspace(repo);
      final driver = FakeNotifications();
      final service = ReminderNotifications(
        driver,
        now: () => DateTime.utc(2030),
      );
      final model = WorkspaceModel(repo, notifications: service);
      await model.load();
      driver.failCancel = true;
      expect(await model.deleteLocalData(), isFalse);
      expect((await repo.readWorkspace()).tasks, hasLength(2));
      expect(model.resetRevision, 0);
      expect(model.error, contains('Couldn’t delete'));
      driver.failCancel = false;
      expect(await model.deleteLocalData(), isTrue);
      expect(driver.alerts, isEmpty);
      model.dispose();
      await service.idle;
      service.dispose();
    },
  );

  test(
    'reset waits for in-flight scheduling and rejects duplicate reset',
    () async {
      final memory = MemoryWorkspace();
      await populateWorkspace(memory);
      final driver = FakeNotifications();
      final service = ReminderNotifications(
        driver,
        now: () => DateTime.utc(2030),
      );
      final model = WorkspaceModel(memory, notifications: service);
      await model.load();
      driver.alerts.clear();
      driver.scheduleGate = Completer<void>();
      final refresh = model.refreshNotifications();
      // Wait until the second schedule is actually blocked.
      while (driver.schedules < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      final deletion = model.deleteLocalData();
      expect(await model.deleteLocalData(), isFalse);
      expect(memory.tasks, isNotEmpty);
      driver.scheduleGate!.complete();
      await refresh;
      expect(await deletion, isTrue);
      await model.refreshNotifications();
      expect(driver.alerts, isEmpty);
      expect(memory.reminders, isEmpty);
      model.dispose();
      await service.idle;
      service.dispose();
    },
  );

  test(
    'account switch during cancellation aborts old workspace deletion',
    () async {
      final memory = MemoryWorkspace();
      await populateWorkspace(memory);
      final driver = _GatedCancellation();
      final service = ReminderNotifications(driver);
      final lease = service.attach('alice');
      final deletion = service.deleteLocalData(lease, memory);
      await driver.started.future;
      service.attach('bob');
      driver.gate.complete();
      await expectLater(deletion, throwsStateError);
      expect(memory.tasks, hasLength(2));
      await service.idle;
      service.dispose();
    },
  );
}

class _GatedCancellation extends FakeNotifications {
  final started = Completer<void>();
  final gate = Completer<void>();
  @override
  Future<void> cancelAll() async {
    started.complete();
    await gate.future;
    await super.cancelAll();
  }
}
