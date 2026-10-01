import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/sync/local_sync_store.dart';
import 'package:work_life/sync/sync_models.dart';
import 'package:work_life/sync/workspace_sync_coordinator.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';

class FakeRemote implements WorkspaceRemoteStore {
  final records = <String, SyncRecord>{};
  final receipts = <String, int>{};
  int revision = 0;
  bool offline = false;
  bool loseNextResponse = false;

  String key(String workspace, String type, String id) =>
      '$workspace::$type::$id';

  @override
  Future<SyncPushResult> push(SyncMutation mutation) async {
    if (offline) throw StateError('offline');
    final receipt = receipts[mutation.mutationId];
    if (receipt != null) return SyncPushResult(revision: receipt);
    final recordKey = key(
      mutation.workspaceId,
      mutation.entityType,
      mutation.recordId,
    );
    final current = records[recordKey];
    if (current != null &&
        current.deleted &&
        !mutation.deleted &&
        mutation.baseRevision < current.revision) {
      receipts[mutation.mutationId] = current.revision;
      return SyncPushResult(revision: current.revision);
    }
    final next = ++revision;
    final payload =
        mutation.entityType == 'planning_preferences' &&
            current?.payload != null &&
            mutation.payload != null
        ? <String, Object?>{...current!.payload!, ...mutation.payload!}
        : mutation.payload;
    records[recordKey] = SyncRecord(
      workspaceId: mutation.workspaceId,
      entityType: mutation.entityType,
      recordId: mutation.recordId,
      revision: next,
      deleted: mutation.deleted,
      payload: payload,
    );
    receipts[mutation.mutationId] = next;
    if (loseNextResponse) {
      loseNextResponse = false;
      throw StateError('response lost');
    }
    return SyncPushResult(revision: next);
  }

  @override
  Future<List<SyncRecord>> pull(
    String workspaceId, {
    required int after,
  }) async {
    if (offline) throw StateError('offline');
    return records.values
        .where(
          (record) =>
              record.workspaceId == workspaceId && record.revision > after,
        )
        .toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late FakeRemote remote;
  var clock = DateTime.utc(2030);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('work_life_sync_');
    remote = FakeRemote();
    clock = DateTime.utc(2030);
  });
  tearDown(() => directory.delete(recursive: true));

  SqliteWorkspaceRepository repository(String device) =>
      SqliteWorkspaceRepository(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/$device.db',
      );

  WorkspaceSyncCoordinator coordinator(
    SqliteWorkspaceRepository repo,
    String workspace,
  ) => WorkspaceSyncCoordinator(
    workspaceId: workspace,
    local: LocalSyncStore(repo.database),
    remote: remote,
    now: () => clock,
  );

  test(
    'local create update and completion upload without duplicates',
    () async {
      final repo = repository('a');
      addTearDown(repo.close);
      final sync = coordinator(repo, '11111111-1111-1111-1111-111111111111');
      addTearDown(sync.dispose);
      final task = Task(id: newId(), title: 'Draft report', area: 'Work');
      await repo.saveTask(task);
      await sync.sync();
      expect(sync.status.phase, SyncPhase.synced);
      expect(
        remote.records.values
            .where((record) => record.entityType == 'tasks')
            .single
            .payload!['title'],
        'Draft report',
      );

      final updated = Task(id: task.id, title: 'Submit report', area: 'Work');
      await repo.saveTask(updated);
      await sync.sync();
      await repo.saveTask(updated.withStatus(TaskStatus.completed));
      await sync.sync();
      final remoteTask = remote.records.values
          .where((record) => record.entityType == 'tasks')
          .single;
      expect(remoteTask.payload!['title'], 'Submit report');
      expect(remoteTask.payload!['status'], TaskStatus.completed.name);
    },
  );

  test(
    'two devices exchange project task relationship and checklist',
    () async {
      final a = repository('a');
      final b = repository('b');
      addTearDown(a.close);
      addTearDown(b.close);
      const workspace = '22222222-2222-2222-2222-222222222222';
      final syncA = coordinator(a, workspace);
      final syncB = coordinator(b, workspace);
      addTearDown(syncA.dispose);
      addTearDown(syncB.dispose);
      final project = Project(id: newId(), title: 'Launch', area: 'Work');
      final task = Task(
        id: newId(),
        title: 'Prepare release',
        area: 'Work',
        projectId: project.id,
        checklist: [
          ChecklistItem(id: newId(), text: 'Test'),
          ChecklistItem(id: newId(), text: 'Ship'),
        ],
      );
      await a.saveProject(project);
      await a.saveTask(task);
      await syncA.sync();
      await syncB.sync();
      var data = await b.readWorkspace();
      expect(data.projects.single.id, project.id);
      expect(data.tasks.single.projectId, project.id);
      expect(
        data.tasks.single.checklist.map((item) => item.id),
        task.checklist.map((item) => item.id),
      );

      await b.saveTask(
        Task(
          id: task.id,
          title: 'Prepare production release',
          area: 'Work',
          projectId: project.id,
          checklist: task.checklist,
        ),
      );
      await syncB.sync();
      await syncA.sync();
      data = await a.readWorkspace();
      expect(data.tasks.single.title, 'Prepare production release');
      expect(data.tasks, hasLength(1));
    },
  );

  test('offline outbox survives restart and retries with backoff', () async {
    var repo = repository('a');
    final workspace = '33333333-3333-3333-3333-333333333333';
    var sync = coordinator(repo, workspace);
    await sync.sync();
    final task = Task(id: newId(), title: 'Offline work', area: 'Work');
    await repo.saveTask(task);
    remote.offline = true;
    await sync.sync();
    expect(sync.status.phase, SyncPhase.offline);
    expect(await LocalSyncStore(repo.database).pendingCount(), greaterThan(0));
    sync.dispose();
    await repo.close();

    repo = repository('a');
    addTearDown(repo.close);
    sync = coordinator(repo, workspace);
    addTearDown(sync.dispose);
    remote.offline = false;
    await sync.sync();
    expect(sync.status.phase, SyncPhase.offline);
    expect(
      remote.records.values.any(
        (record) => record.entityType == 'tasks' && record.recordId == task.id,
      ),
      isFalse,
    );
    await sync.retryNow();
    expect(sync.status.phase, SyncPhase.synced);
    expect(await LocalSyncStore(repo.database).pendingCount(), 0);
    expect(
      remote.records.values.any(
        (record) => record.entityType == 'tasks' && record.recordId == task.id,
      ),
      isTrue,
    );
  });

  test('a delayed mutation does not hide other ready outbox work', () async {
    final repo = repository('retry-order');
    addTearDown(repo.close);
    const workspace = '34343434-3434-3434-3434-343434343434';
    final store = LocalSyncStore(repo.database);
    await store.initialize(workspace);
    await repo.saveTask(const Task(id: 'task-a', title: 'A', area: 'Work'));
    await repo.saveTask(const Task(id: 'task-b', title: 'B', area: 'Work'));
    final rows = await repo.database.open().then(
      (db) => db.query(
        'sync_outbox',
        orderBy: 'created_at, entity_type, record_id',
      ),
    );
    final delayedId = rows.first['mutation_id'] as String;
    final all = await store.pending(workspace, now: clock);
    final delayed = all.singleWhere((m) => m.mutationId == delayedId);
    await store.retryLater(delayed, now: clock);

    final ready = await store.pending(workspace, now: clock);
    expect(ready, isNotEmpty);
    expect(ready.every((m) => m.mutationId != delayedId), isTrue);
  });

  test('lost upload response retries idempotently', () async {
    final repo = repository('a');
    addTearDown(repo.close);
    final sync = coordinator(repo, '44444444-4444-4444-4444-444444444444');
    addTearDown(sync.dispose);
    await repo.saveTask(Task(id: newId(), title: 'Exactly once', area: 'Work'));
    remote.loseNextResponse = true;
    await sync.sync();
    clock = clock.add(const Duration(minutes: 10));
    await sync.sync();
    expect(
      remote.records.values.where((record) => record.entityType == 'tasks'),
      hasLength(1),
    );
    expect(remote.records.keys.toSet(), hasLength(remote.records.length));
    expect(sync.status.phase, SyncPhase.synced);
  });

  test(
    'remote deletion applies locally and stale device cannot resurrect it',
    () async {
      final a = repository('a');
      final b = repository('b');
      addTearDown(a.close);
      addTearDown(b.close);
      const workspace = '55555555-5555-5555-5555-555555555555';
      final syncA = coordinator(a, workspace);
      final syncB = coordinator(b, workspace);
      addTearDown(syncA.dispose);
      addTearDown(syncB.dispose);
      final plan = PlanBlock(
        id: newId(),
        title: 'Delete safely',
        start: DateTime(2035, 1, 1, 9),
        minutes: 30,
        area: 'Work',
      );
      await a.savePlan(plan);
      await syncA.sync();
      await syncB.sync();
      await a.removePlan(plan.id);
      await syncA.sync();

      // B edits its stale copy before observing A's tombstone.
      await b.savePlan(
        PlanBlock(
          id: plan.id,
          title: 'Stale edit',
          start: plan.start,
          minutes: plan.minutes,
          area: plan.area,
        ),
      );
      await syncB.sync();
      expect((await b.readWorkspace()).plans, isEmpty);
      expect(
        remote.records.values
            .singleWhere((record) => record.recordId == plan.id)
            .deleted,
        isTrue,
      );
    },
  );

  test('reminder intent syncs but device delivery status does not', () async {
    final a = repository('a');
    final b = repository('b');
    addTearDown(a.close);
    addTearDown(b.close);
    const workspace = '66666666-6666-6666-6666-666666666666';
    final syncA = coordinator(a, workspace);
    final syncB = coordinator(b, workspace);
    addTearDown(syncA.dispose);
    addTearDown(syncB.dispose);
    final task = Task(id: newId(), title: 'Call', area: 'Work');
    final reminder = TaskReminder(
      id: newId(),
      taskId: task.id,
      scheduledAt: DateTime.now().toUtc().add(const Duration(days: 3)),
      recurrence: ReminderRecurrence.weekly,
    );
    await a.saveTask(task);
    await a.saveReminder(reminder);
    await a.recordReminderDelivery(reminder, 'scheduled');
    await syncA.sync();
    final remoteReminder = remote.records.values.singleWhere(
      (record) => record.entityType == 'reminders',
    );
    expect(remoteReminder.payload, isNot(contains('delivery_status')));
    await syncB.sync();
    expect(
      (await b.readWorkspace()).reminders.single.deliveryStatus,
      'pending',
    );
    expect(
      (await b.readWorkspace()).reminders.single.recurrence,
      ReminderRecurrence.weekly,
    );
  });

  test('independent planning preference edits merge and same-field uses last arrival', () async {
    final a = repository('preferences-a');
    final b = repository('preferences-b');
    addTearDown(a.close);
    addTearDown(b.close);
    const workspace = '67676767-6767-6767-6767-676767676767';
    final syncA = coordinator(a, workspace);
    final syncB = coordinator(b, workspace);
    addTearDown(syncA.dispose);
    addTearDown(syncB.dispose);
    await syncA.sync();
    await syncB.sync();

    await a.savePlanningPreferences(
      const PlanningPreferences(bedTime: '22:30'),
    );
    await b.savePlanningPreferences(
      const PlanningPreferences(exercisePeriod: 'evening'),
    );
    await syncA.sync();
    await syncB.sync();
    await syncA.sync();
    var aPreferences = (await a.readWorkspace()).planningPreferences;
    var bPreferences = (await b.readWorkspace()).planningPreferences;
    expect(aPreferences.bedTime, '22:30');
    expect(aPreferences.exercisePeriod, 'evening');
    expect(bPreferences.bedTime, '22:30');
    expect(bPreferences.exercisePeriod, 'evening');

    await a.savePlanningPreferences(
      PlanningPreferences(
        bedTime: '22:15',
        exercisePeriod: aPreferences.exercisePeriod,
      ),
    );
    await b.savePlanningPreferences(
      PlanningPreferences(
        bedTime: '22:00',
        exercisePeriod: bPreferences.exercisePeriod,
      ),
    );
    await syncA.sync();
    await syncB.sync();
    await syncA.sync();
    aPreferences = (await a.readWorkspace()).planningPreferences;
    bPreferences = (await b.readWorkspace()).planningPreferences;
    expect(aPreferences.bedTime, '22:00');
    expect(bPreferences.bedTime, '22:00');
  });

  test(
    'workspace and account isolation reject local reuse and remote leakage',
    () async {
      final repo = repository('a');
      addTearDown(repo.close);
      final first = coordinator(repo, '77777777-7777-7777-7777-777777777777');
      addTearDown(first.dispose);
      await first.sync();
      final second = coordinator(repo, '88888888-8888-8888-8888-888888888888');
      addTearDown(second.dispose);
      await second.sync();
      expect(second.status.phase, SyncPhase.offline);

      final leaking = _LeakingRemote();
      final other = WorkspaceSyncCoordinator(
        workspaceId: '99999999-9999-9999-9999-999999999999',
        local: LocalSyncStore(repository('leak').database),
        remote: leaking,
      );
      addTearDown(other.dispose);
      await other.sync();
      expect(other.status.phase, SyncPhase.offline);
    },
  );

  test(
    'first sync merges local-only and remote-only records deterministically',
    () async {
      const workspace = 'abababab-abab-abab-abab-abababababab';
      final sharedId = newId();
      final remoteOnlyId = newId();
      remote.records[remote.key(workspace, 'tasks', sharedId)] = SyncRecord(
        workspaceId: workspace,
        entityType: 'tasks',
        recordId: sharedId,
        revision: ++remote.revision,
        deleted: false,
        payload: {
          'id': sharedId,
          'title': 'Remote version',
          'area': 'Work',
          'project_id': null,
          'capture_id': null,
          'entry_id': null,
          'deadline': null,
          'minutes': 25,
          'notes': '',
          'priority': 'medium',
          'status': 'open',
          'checklist': '[]',
        },
      );
      remote.records[remote.key(
        workspace,
        'projects',
        remoteOnlyId,
      )] = SyncRecord(
        workspaceId: workspace,
        entityType: 'projects',
        recordId: remoteOnlyId,
        revision: ++remote.revision,
        deleted: false,
        payload: {
          'id': remoteOnlyId,
          'title': 'Remote project',
          'area': 'Work',
          'description': '',
        },
      );
      final repo = repository('merge');
      addTearDown(repo.close);
      final localOnly = Task(id: newId(), title: 'Local only', area: 'Work');
      await repo.saveTask(
        Task(id: sharedId, title: 'Unversioned local copy', area: 'Work'),
      );
      await repo.saveTask(localOnly);
      final sync = coordinator(repo, workspace);
      addTearDown(sync.dispose);
      await sync.sync();

      final data = await repo.readWorkspace();
      expect(
        data.tasks.singleWhere((task) => task.id == sharedId).title,
        'Remote version',
      );
      expect(data.tasks.any((task) => task.id == localOnly.id), isTrue);
      expect(data.projects.single.id, remoteOnlyId);
      expect(
        remote.records.values.any(
          (record) =>
              record.entityType == 'tasks' && record.recordId == localOnly.id,
        ),
        isTrue,
      );
    },
  );

  test('Supabase migration enforces auth ownership and checked RPC', () async {
    final sql = await File(
      'supabase/migrations/202609260001_workspace_sync.sql',
    ).readAsString();
    expect(sql, contains('enable row level security'));
    expect(sql, contains('owner_id = auth.uid()'));
    expect(sql, contains('p_workspace_id <> v_user'));
    expect(sql, contains('security definer'));
    expect(
      sql,
      contains('There are intentionally no\n-- direct INSERT/UPDATE/DELETE'),
    );
    final architectSql = await File(
      'supabase/migrations/202609280001_day_architect_entities.sql',
    ).readAsString();
    expect(
      architectSql,
      contains("'recurring_schedules', 'schedule_exceptions'"),
    );
    expect(architectSql, contains("'planning_preferences'"));
    expect(architectSql, contains('p_workspace_id <> v_user'));
  });
}

class _LeakingRemote implements WorkspaceRemoteStore {
  @override
  Future<List<SyncRecord>> pull(
    String workspaceId, {
    required int after,
  }) async => [
    SyncRecord(
      workspaceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      entityType: 'projects',
      recordId: 'foreign',
      revision: 1,
      deleted: false,
      payload: const {
        'id': 'foreign',
        'title': 'Foreign',
        'area': 'Work',
        'description': '',
      },
    ),
  ];

  @override
  Future<SyncPushResult> push(SyncMutation mutation) async =>
      const SyncPushResult(revision: 1);
}
