import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import 'sync_models.dart';

class LocalSyncStore {
  const LocalSyncStore(this.database);
  final AppDatabase database;

  static const entityOrder = <String>[
    'life_areas',
    'captures',
    'projects',
    'project_entries',
    'tasks',
    'plans',
    'routines',
    'routine_records',
    'focus_sessions',
    'reminders',
    'reminder_suppressions',
    'quiet_hours',
    'reminder_preferences',
    'workspace_setup',
    'recurring_schedules',
    'schedule_exceptions',
    'planning_preferences',
  ];

  Future<void> initialize(String workspaceId) async {
    final db = await database.open();
    await _ensurePreferenceChanges(db);
    final state = (await db.query('sync_state', where: 'id = 1')).single;
    final current = state['workspace_id'] as String?;
    if (current != null && current != workspaceId) {
      throw StateError('Local sync workspace does not match this account');
    }
    await db.update('sync_state', {
      'workspace_id': workspaceId,
    }, where: 'id = 1');
  }

  Future<bool> get seeded async => (await _state())['seeded'] == 1;
  Future<int> get checkpoint async => (await _state())['checkpoint'] as int;

  Future<Map<String, Object?>> _state() async =>
      (await (await database.open()).query(
        'sync_state',
        where: 'id = 1',
      )).single;

  Future<void> seedLocalOnly() async {
    final db = await database.open();
    await db.transaction((tx) async {
      for (final type in entityOrder) {
        for (final row in await tx.query(type)) {
          final id = _recordId(type, row);
          final known = await tx.query(
            'sync_records',
            where: 'entity_type = ? AND record_id = ?',
            whereArgs: [type, id],
          );
          if (known.isEmpty) await _queue(tx, type, id, deleted: false);
        }
      }
      await tx.update('sync_state', {'seeded': 1}, where: 'id = 1');
    });
  }

  Future<List<SyncMutation>> pending(
    String workspaceId, {
    DateTime? now,
  }) async {
    final instant = (now ?? DateTime.now()).toUtc().toIso8601String();
    final db = await database.open();
    await _ensurePreferenceChanges(db);
    final rows = await db.query(
      'sync_outbox',
      orderBy: 'created_at, entity_type, record_id',
    );
    final result = <SyncMutation>[];
    for (final row in rows) {
      final retryAt = row['next_attempt_at'] as String?;
      // Rows are ordered by creation time, not retry time. A delayed mutation
      // must not hide unrelated work that is already eligible to upload.
      if (retryAt != null && retryAt.compareTo(instant) > 0) continue;
      final type = row['entity_type'] as String;
      final id = row['record_id'] as String;
      final deleted = row['deleted'] == 1;
      result.add(
        SyncMutation(
          mutationId: row['mutation_id'] as String,
          workspaceId: workspaceId,
          entityType: type,
          recordId: id,
          deleted: deleted,
          baseRevision: row['base_revision'] as int,
          payload: deleted ? null : await _payload(db, type, id),
        ),
      );
    }
    result.sort((a, b) {
      final order = entityOrder
          .indexOf(a.entityType)
          .compareTo(entityOrder.indexOf(b.entityType));
      return order == 0 ? a.recordId.compareTo(b.recordId) : order;
    });
    return result;
  }

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(
        await (await database.open()).rawQuery(
          'SELECT COUNT(*) FROM sync_outbox',
        ),
      ) ??
      0;

  Future<void> makeRetriesDue() async {
    await (await database.open()).update('sync_outbox', {
      'next_attempt_at': null,
    });
  }

  Future<void> acknowledge(SyncMutation mutation, int revision) async {
    final db = await database.open();
    await db.transaction((tx) async {
      final current = await tx.query(
        'sync_outbox',
        columns: ['mutation_id'],
        where: 'entity_type = ? AND record_id = ?',
        whereArgs: [mutation.entityType, mutation.recordId],
      );
      await tx.insert('sync_records', {
        'entity_type': mutation.entityType,
        'record_id': mutation.recordId,
        'revision': revision,
        'deleted': mutation.deleted ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.delete(
        'sync_outbox',
        where: 'mutation_id = ?',
        whereArgs: [mutation.mutationId],
      );
      if (mutation.entityType == 'planning_preferences' &&
          current.isNotEmpty &&
          current.single['mutation_id'] == mutation.mutationId) {
        await tx.delete('planning_preference_changes', where: 'id = 1');
      }
    });
  }

  Future<void> retryLater(
    SyncMutation mutation, {
    required DateTime now,
  }) async {
    final db = await database.open();
    final rows = await db.query(
      'sync_outbox',
      where: 'mutation_id = ?',
      whereArgs: [mutation.mutationId],
    );
    if (rows.isEmpty) return;
    final attempts = (rows.single['attempts'] as int) + 1;
    final seconds = (1 << attempts.clamp(0, 8)).clamp(2, 300);
    await db.update(
      'sync_outbox',
      {
        'attempts': attempts,
        'next_attempt_at': now
            .toUtc()
            .add(Duration(seconds: seconds))
            .toIso8601String(),
      },
      where: 'mutation_id = ?',
      whereArgs: [mutation.mutationId],
    );
  }

  Future<void> applyRemote(List<SyncRecord> records) async {
    if (records.isEmpty) return;
    final db = await database.open();
    await _ensurePreferenceChanges(db);
    await db.transaction((tx) async {
      await tx.update('sync_state', {'applying_remote': 1}, where: 'id = 1');
      try {
        final upserts = records.where((record) => !record.deleted).toList()
          ..sort(
            (a, b) => entityOrder
                .indexOf(a.entityType)
                .compareTo(entityOrder.indexOf(b.entityType)),
          );
        final deletes = records.where((record) => record.deleted).toList()
          ..sort(
            (a, b) => entityOrder
                .indexOf(b.entityType)
                .compareTo(entityOrder.indexOf(a.entityType)),
          );
        for (final record in [...upserts, ...deletes]) {
          await _apply(tx, record);
          await tx.insert('sync_records', {
            'entity_type': record.entityType,
            'record_id': record.recordId,
            'revision': record.revision,
            'deleted': record.deleted ? 1 : 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final latest = records
            .map((record) => record.revision)
            .reduce((a, b) => a > b ? a : b);
        await tx.update('sync_state', {'checkpoint': latest}, where: 'id = 1');
      } finally {
        await tx.update('sync_state', {'applying_remote': 0}, where: 'id = 1');
      }
    });
  }

  Future<Map<String, Object?>?> _payload(
    DatabaseExecutor db,
    String type,
    String id,
  ) async {
    final selector = _selector(type, id);
    final rows = await db.query(
      type,
      where: selector.$1,
      whereArgs: selector.$2,
    );
    if (rows.isEmpty) return null;
    final payload = Map<String, Object?>.from(rows.single);
    if (type == 'reminders') payload.remove('delivery_status');
    if (type == 'planning_preferences') {
      final changes = await db.query(
        'planning_preference_changes',
        where: 'id = 1',
      );
      if (changes.isNotEmpty) {
        final fields = (jsonDecode(changes.single['fields'] as String) as List)
            .cast<String>();
        payload.removeWhere((key, _) => key != 'id' && !fields.contains(key));
      }
    }
    return payload;
  }

  Future<void> _apply(Transaction tx, SyncRecord record) async {
    final selector = _selector(record.entityType, record.recordId);
    if (record.deleted) {
      await tx.delete(
        record.entityType,
        where: selector.$1,
        whereArgs: selector.$2,
      );
      return;
    }
    final payload = Map<String, Object?>.from(record.payload!);
    if (record.entityType == 'reminders') {
      payload['delivery_status'] = 'pending';
    }
    if (record.entityType == 'planning_preferences') {
      final changes = await tx.query(
        'planning_preference_changes',
        where: 'id = 1',
      );
      if (changes.isNotEmpty) {
        final fields = (jsonDecode(changes.single['fields'] as String) as List)
            .cast<String>();
        for (final field in fields) {
          payload.remove(field);
        }
      }
    }
    final changed = await tx.update(
      record.entityType,
      payload,
      where: selector.$1,
      whereArgs: selector.$2,
    );
    if (changed == 0) await tx.insert(record.entityType, payload);
  }

  (String, List<Object?>) _selector(String type, String id) {
    if (type == 'routine_records') {
      final split = id.indexOf('|');
      if (split < 1) throw FormatException('Invalid routine record ID');
      return (
        'routine_id = ? AND day = ?',
        [id.substring(0, split), id.substring(split + 1)],
      );
    }
    if (type == 'schedule_exceptions') {
      final split = id.indexOf('|');
      if (split < 1) throw FormatException('Invalid schedule exception ID');
      return (
        'schedule_id = ? AND day = ?',
        [id.substring(0, split), id.substring(split + 1)],
      );
    }
    if (type == 'life_areas') return ('name = ?', [id]);
    if (type == 'reminder_suppressions') return ('task_id = ?', [id]);
    return ('id = ?', [int.tryParse(id) ?? id]);
  }

  String _recordId(String type, Map<String, Object?> row) =>
      type == 'routine_records'
      ? '${row['routine_id']}|${row['day']}'
      : type == 'schedule_exceptions'
      ? '${row['schedule_id']}|${row['day']}'
      : type == 'life_areas'
      ? row['name'] as String
      : type == 'reminder_suppressions'
      ? row['task_id'] as String
      : row['id'].toString();

  Future<void> _queue(
    Transaction tx,
    String type,
    String id, {
    required bool deleted,
  }) async {
    await tx.rawInsert(
      '''INSERT INTO sync_outbox(
        mutation_id, entity_type, record_id, deleted, base_revision, created_at
      ) VALUES(lower(hex(randomblob(16))), ?, ?, ?, 0,
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      ON CONFLICT(entity_type, record_id) DO NOTHING''',
      [type, id, deleted ? 1 : 0],
    );
  }

  Future<void> _ensurePreferenceChanges(DatabaseExecutor db) =>
      db.execute('''CREATE TABLE IF NOT EXISTS planning_preference_changes (
      id INTEGER PRIMARY KEY CHECK(id = 1), fields TEXT NOT NULL
    )''');
}
