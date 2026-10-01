import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/ai/day_context_builder.dart';
import 'package:work_life/data/app_database.dart';
import 'package:work_life/sync/local_sync_store.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkspaceRepository repository;
  late AppDatabase database;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('day_architect_');
    final path = '${dir.path}/db.sqlite';
    database = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
    repository = SqliteWorkspaceRepository(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
  });
  tearDown(() async {
    await repository.close();
    await dir.delete(recursive: true);
  });

  test('recurring commitments, cancellation/moved exception, and preferences persist and sync', () async {
    final monday = DateTime(2026, 9, 28);
    final schedule = RecurringSchedule(
      id: 'class-1',
      title: 'Software Engineering',
      type: RecurringScheduleType.classSession,
      weekday: DateTime.monday,
      startTime: '09:00',
      endTime: '10:30',
      startDate: '2026-08-24',
      endDate: '2026-12-18',
      location: 'B12',
    );
    await repository.saveRecurringSchedule(schedule);
    await repository.saveScheduleException(
      const ScheduleException(
        scheduleId: 'class-1',
        day: '2026-09-28',
        cancelled: false,
        startTime: '10:00',
        endTime: '11:30',
      ),
    );
    await repository.savePlanningPreferences(
      const PlanningPreferences(
        wakeTime: '07:00',
        bedTime: '22:30',
        style: 'flexible',
      ),
    );
    final sync = LocalSyncStore(database);
    await sync.initialize('00000000-0000-0000-0000-000000000001');
    final pending = await sync.pending('00000000-0000-0000-0000-000000000001');
    expect(
      pending.map((m) => m.entityType),
      containsAll([
        'recurring_schedules',
        'schedule_exceptions',
        'planning_preferences',
      ]),
    );
    final snapshot = await repository.readWorkspace();
    final context = const DayContextBuilder().build(snapshot, monday);
    final recurring = context['fixedCommitments'] as List;
    expect((recurring.single as Map)['start'], '10:00');
    expect(context['preferences'], containsPair('bedTime', '22:30'));
    final offDay = const DayContextBuilder().build(
      snapshot,
      monday.add(const Duration(days: 1)),
    );
    expect((offDay['fixedCommitments'] as List), isEmpty);
  });

  test('cancelled semester occurrence is absent and out-of-range schedule is excluded', () async {
    await repository.saveRecurringSchedule(
      const RecurringSchedule(
        id: 'class',
        title: 'Class',
        type: RecurringScheduleType.classSession,
        weekday: 1,
        startTime: '09:00',
        endTime: '10:00',
        startDate: '2026-09-01',
        endDate: '2026-12-01',
      ),
    );
    await repository.saveScheduleException(
      const ScheduleException(scheduleId: 'class', day: '2026-09-28'),
    );
    final data = await repository.readWorkspace();
    expect(
      const DayContextBuilder().build(
        data,
        DateTime(2026, 9, 28),
      )['fixedCommitments'],
      isEmpty,
    );
    expect(
      const DayContextBuilder().build(
        data,
        DateTime(2027, 9, 27),
      )['fixedCommitments'],
      isEmpty,
    );
  });

  test('one-date move leaves the recurrence intact and appears on destination date', () async {
    await repository.saveRecurringSchedule(
      const RecurringSchedule(
        id: 'seminar',
        title: 'Seminar',
        type: RecurringScheduleType.classSession,
        weekday: 1,
        startTime: '09:00',
        endTime: '10:00',
        startDate: '2026-09-01',
        endDate: '2026-12-31',
      ),
    );
    await repository.saveScheduleException(
      const ScheduleException(
        scheduleId: 'seminar',
        day: '2026-09-28',
        cancelled: false,
        movedToDate: '2026-09-29',
      ),
    );
    final data = await repository.readWorkspace();
    expect(
      const DayContextBuilder().build(
        data,
        DateTime(2026, 9, 28),
      )['fixedCommitments'],
      isEmpty,
    );
    final moved =
        (const DayContextBuilder().build(
                      data,
                      DateTime(2026, 9, 29),
                    )['fixedCommitments']
                    as List)
                .single
            as Map;
    expect(moved['title'], 'Seminar');
    expect(moved['movedFrom'], '2026-09-28');
  });

  test('week context is seven consecutive contexts from Monday', () {
    final week = const WeekContextBuilder().build(
      const WorkspaceData(),
      DateTime(2026, 9, 30),
    );
    expect(week, hasLength(7));
    expect(week.first['date'], '2026-09-28');
    expect(week.last['date'], '2026-10-04');
  });

  test('weekly planning context is compact and spans month boundaries', () {
    final data = WorkspaceData(
      tasks: const [
        Task(
          id: 'due',
          title: 'Submit report',
          area: 'Work',
          deadline: '2026-10-05',
          minutes: 90,
        ),
        Task(id: 'later', title: 'Someday', area: 'Personal'),
      ],
      plans: [
        PlanBlock(
          id: 'report-session',
          title: 'Draft report',
          taskId: 'due',
          start: DateTime(2026, 10, 1, 10),
          minutes: 45,
          area: 'Work',
        ),
      ],
    );
    final context = const WeekContextBuilder().buildPlanningContext(
      data,
      DateTime(2026, 9, 30),
      request: 'Keep Friday light',
    );
    expect(context['week'], {'start': '2026-09-28', 'end': '2026-10-04'});
    expect(context['days'], hasLength(7));
    expect((context['tasks'] as List), hasLength(1));
    expect((context['tasks'] as List).single, containsPair('taskId', 'due'));
    expect(
      (context['tasks'] as List).single,
      containsPair('plannedDates', ['2026-10-01']),
    );
    expect(context['userRequest'], 'Keep Friday light');
    expect((context['days'] as List).first, isNot(contains('tasks')));
    expect(
      const WeekContextBuilder().fingerprints(data, DateTime(2026, 9, 30)),
      hasLength(7),
    );
  });

  test('capacity includes transition time when detecting overload', () {
    final data = WorkspaceData(
      recurringSchedules: const [
        RecurringSchedule(
          id: 'short-class',
          title: 'Class',
          type: RecurringScheduleType.classSession,
          weekday: DateTime.monday,
          startTime: '08:00',
          endTime: '08:30',
          startDate: '2026-09-01',
        ),
      ],
      tasks: const [
        Task(
          id: 'urgent',
          title: 'Urgent work',
          area: 'Work',
          deadline: '2026-09-28',
          minutes: 80,
        ),
      ],
      planningPreferences: const PlanningPreferences(
        wakeTime: '08:00',
        bedTime: '10:00',
        transitionMinutes: 15,
      ),
    );
    final capacity =
        const DayContextBuilder().build(data, DateTime(2026, 9, 28))['capacity']
            as Map;
    expect(capacity['availableMinutes'], 75);
    expect(capacity['overCapacity'], isTrue);
  });

  test(
    'exceptions must target a real occurrence and use complete valid times',
    () async {
      await repository.saveRecurringSchedule(
        const RecurringSchedule(
          id: 'monday-class',
          title: 'Monday class',
          type: RecurringScheduleType.classSession,
          weekday: DateTime.monday,
          startTime: '09:00',
          endTime: '10:00',
          startDate: '2026-09-01',
          endDate: '2026-12-01',
        ),
      );
      await expectLater(
        repository.saveScheduleException(
          const ScheduleException(
            scheduleId: 'monday-class',
            day: '2026-09-29',
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveScheduleException(
          const ScheduleException(
            scheduleId: 'monday-class',
            day: '2026-09-28',
            cancelled: false,
            movedToDate: '2026-09-29',
            startTime: '11:00',
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'v14 to v17 upgrade preserves existing data and creates architect defaults',
    () async {
      const task = Task(id: 'legacy-task', title: 'Keep me', area: 'Work');
      await repository.saveTask(task);
      await repository.close();

      final path = '${dir.path}/db.sqlite';
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute('DROP TABLE schedule_exceptions');
      await legacy.execute('DROP TABLE recurring_schedules');
      await legacy.execute('DROP TABLE planning_preferences');
      await legacy.execute('PRAGMA user_version = 14');
      await legacy.close();

      final upgraded = await repository.readWorkspace();
      expect(upgraded.tasks.single.id, task.id);
      expect(upgraded.planningPreferences.wakeTime, '07:30');
      expect(upgraded.planningPreferences.breakfastWindow, '07:00-09:00');
      final db = await repository.database.open();
      final version = await db.rawQuery('PRAGMA user_version');
      expect(version.single.values.single, 17);
      final outbox = await db.query(
        'sync_outbox',
        where: 'entity_type = ? AND record_id = ?',
        whereArgs: ['tasks', task.id],
      );
      expect(outbox, hasLength(1));
    },
  );

  for (final oldVersion in [15, 16]) {
    test(
      'v$oldVersion to v17 preserves historical architect and core data',
      () async {
        const project = Project(
          id: 'legacy-project',
          title: 'Legacy',
          area: 'Work',
        );
        const task = Task(
          id: 'legacy-task-v15',
          title: 'Keep task',
          area: 'Work',
          projectId: 'legacy-project',
        );
        await repository.saveProject(project);
        await repository.saveTask(task);
        await repository.savePlan(
          PlanBlock(
            id: 'legacy-plan',
            title: task.title,
            taskId: task.id,
            start: DateTime(2030, 1, 7, 11),
            minutes: 30,
            area: 'Work',
            fixed: true,
          ),
        );
        await repository.saveReminder(
          TaskReminder(
            id: 'legacy-reminder',
            taskId: task.id,
            scheduledAt: DateTime.now().toUtc().add(const Duration(days: 30)),
          ),
        );
        await repository.saveRecurringSchedule(
          const RecurringSchedule(
            id: 'legacy-class',
            title: 'Legacy class',
            type: RecurringScheduleType.classSession,
            weekday: DateTime.monday,
            startTime: '09:00',
            endTime: '10:00',
            startDate: '2030-01-01',
          ),
        );
        await repository.saveScheduleException(
          ScheduleException(
            scheduleId: 'legacy-class',
            day: '2030-01-07',
            cancelled: false,
            startTime: '10:00',
            endTime: '11:00',
            movedToDate: oldVersion == 16 ? '2030-01-08' : null,
          ),
        );
        await repository.savePlanningPreferences(
          const PlanningPreferences(
            wakeTime: '06:45',
            bedTime: '22:45',
            exercisePeriod: 'evening',
          ),
        );
        await repository.close();
        final path = '${dir.path}/db.sqlite';
        await _makeHistoricalArchitectFixture(path, oldVersion);

        final data = await repository.readWorkspace();
        expect(data.projects.single.id, project.id);
        expect(data.tasks.single.projectId, project.id);
        expect(data.plans.single.taskId, task.id);
        expect(data.reminders.single.taskId, task.id);
        expect(data.recurringSchedules.single.id, 'legacy-class');
        expect(data.scheduleExceptions.single.startTime, '10:00');
        expect(
          data.scheduleExceptions.single.movedToDate,
          oldVersion == 16 ? '2030-01-08' : null,
        );
        expect(data.planningPreferences.wakeTime, '06:45');
        expect(data.planningPreferences.breakfastWindow, '07:00-09:00');

        final db = await repository.database.open();
        final version = await db.rawQuery('PRAGMA user_version');
        expect(version.single.values.single, 17);
        final foreignKeys = await db.rawQuery(
          'PRAGMA foreign_key_list(schedule_exceptions)',
        );
        expect(foreignKeys.single['table'], 'recurring_schedules');
        final triggers = await db.query(
          'sqlite_master',
          columns: ['name'],
          where: "type = 'trigger' AND name LIKE ?",
          whereArgs: ['sync_schedule_exceptions_%'],
        );
        expect(triggers.map((row) => row['name']).toSet(), hasLength(3));
        final planIndexes = await db.rawQuery('PRAGMA index_list(plans)');
        expect(planIndexes, isNotNull);
        final sync = LocalSyncStore(repository.database);
        const workspace = '15151515-1515-1515-1515-151515151515';
        await sync.initialize(workspace);
        await expectLater(
          sync.initialize('16161616-1616-1616-1616-161616161616'),
          throwsStateError,
        );
        final syncState = await db.query('sync_state', where: 'id = 1');
        expect(syncState.single['workspace_id'], workspace);
        expect(await db.query('sync_outbox'), isNotEmpty);
      },
    );
  }
}

Future<void> _makeHistoricalArchitectFixture(String path, int version) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  final preference = (await db.query('planning_preferences')).single;
  final exceptions = await db.query('schedule_exceptions');
  await db.execute('PRAGMA foreign_keys = OFF');
  await db.execute('DROP TABLE schedule_exceptions');
  await db.execute('DROP TABLE planning_preferences');
  await db.execute('DROP TABLE IF EXISTS planning_preference_changes');
  await db.execute('''CREATE TABLE schedule_exceptions (
    schedule_id TEXT NOT NULL REFERENCES recurring_schedules(id) ON DELETE CASCADE,
    day TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'cancelled',
    start_time TEXT, end_time TEXT${version >= 16 ? ', moved_to_date TEXT' : ''},
    PRIMARY KEY(schedule_id, day))''');
  await db.execute('''CREATE TABLE planning_preferences (
    id INTEGER PRIMARY KEY CHECK(id = 1), wake_time TEXT NOT NULL,
    bed_time TEXT NOT NULL, transition_minutes INTEGER NOT NULL,
    break_minutes INTEGER NOT NULL, exercise_period TEXT NOT NULL,
    avoid_focus_after TEXT NOT NULL, max_focus_minutes INTEGER NOT NULL,
    style TEXT NOT NULL)''');
  await db.insert('planning_preferences', {
    'id': preference['id'],
    'wake_time': preference['wake_time'],
    'bed_time': preference['bed_time'],
    'transition_minutes': preference['transition_minutes'],
    'break_minutes': preference['break_minutes'],
    'exercise_period': preference['exercise_period'],
    'avoid_focus_after': preference['avoid_focus_after'],
    'max_focus_minutes': preference['max_focus_minutes'],
    'style': preference['style'],
  });
  for (final row in exceptions) {
    await db.insert('schedule_exceptions', {
      'schedule_id': row['schedule_id'],
      'day': row['day'],
      'kind': row['kind'],
      'start_time': row['start_time'],
      'end_time': row['end_time'],
      if (version >= 16) 'moved_to_date': row['moved_to_date'],
    });
  }
  const keys = {
    'schedule_exceptions': "{row}.schedule_id || '|' || {row}.day",
    'planning_preferences': 'CAST({row}.id AS TEXT)',
  };
  for (final entry in keys.entries) {
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = operation == 'DELETE' ? 'OLD' : 'NEW';
      final id = entry.value.replaceAll('{row}', row);
      await db.execute(
        '''CREATE TRIGGER sync_${entry.key}_${operation.toLowerCase()}
        AFTER $operation ON ${entry.key}
        WHEN (SELECT applying_remote FROM sync_state WHERE id=1)=0 BEGIN
        INSERT INTO sync_outbox(mutation_id,entity_type,record_id,deleted,base_revision,created_at)
        VALUES(lower(hex(randomblob(16))),'${entry.key}',$id,${operation == 'DELETE' ? 1 : 0},0,
        strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        ON CONFLICT(entity_type,record_id) DO UPDATE SET
        mutation_id=excluded.mutation_id,deleted=excluded.deleted,
        base_revision=excluded.base_revision,created_at=excluded.created_at;
        END''',
      );
    }
  }
  await db.execute('PRAGMA user_version = $version');
  await db.execute('PRAGMA foreign_keys = ON');
  await db.close();
}
