import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../workspace/records.dart';

class AppDatabase {
  AppDatabase({
    DatabaseFactory? factory,
    this.databasePath,
    this.databaseName = 'work_life.db',
  }) : _factory = factory ?? databaseFactory;
  final DatabaseFactory _factory;
  final String? databasePath;
  final String databaseName;
  Future<Database>? _opening;

  Future<Database> open() async {
    try {
      return await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async => _factory.openDatabase(
    databasePath ?? path.join(await _factory.getDatabasesPath(), databaseName),
    options: OpenDatabaseOptions(
      version: 17,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE captures (id TEXT PRIMARY KEY, original_text TEXT NOT NULL, created_at TEXT NOT NULL)',
        );
        await _workspace(db);
        await _entries(db);
        await _reminders(db);
        await _notificationState(db);
        await _quietHours(db);
        await _reminderDefaults(db);
        await _workspaceSetup(db, completed: false);
        await _routineLevels(db);
        await _aiOperations(db);
        await _taskPriority(db);
        await _reminderBasis(db);
        await _syncTables(db);
        await _dayArchitectTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 8) await _workspaceSetup(db, completed: true);
        if (oldVersion < 2) await _workspace(db);
        if (oldVersion < 3) await _entries(db);
        if (oldVersion < 4) await _reminders(db);
        if (oldVersion < 5) await _notificationState(db);
        if (oldVersion < 6) await _quietHours(db);
        if (oldVersion < 7) {
          final columns = await db.rawQuery('PRAGMA table_info(reminders)');
          if (!columns.any((column) => column['name'] == 'origin')) {
            await db.execute(
              "ALTER TABLE reminders ADD COLUMN origin TEXT NOT NULL DEFAULT 'explicit'",
            );
          }
          await _reminderDefaults(db);
        }
        if (oldVersion < 9) await _routineLevels(db);
        if (oldVersion < 10) {
          final columns = await db.rawQuery('PRAGMA table_info(reminders)');
          if (!columns.any((column) => column['name'] == 'recurrence')) {
            await db.execute(
              "ALTER TABLE reminders ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'none'",
            );
          }
        }
        if (oldVersion < 11) await _aiOperations(db);
        if (oldVersion < 12) await _taskPriority(db);
        if (oldVersion < 13) await _reminderBasis(db);
        if (oldVersion < 14) await _syncTables(db);
        if (oldVersion < 15) await _dayArchitectTables(db);
        if (oldVersion < 16) await _scheduleMoveException(db);
        if (oldVersion < 17) await _mealPreferenceColumns(db);
      },
    ),
  );

  static Future<void> _routineLevels(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(routines)');
    for (final name in ['normal', 'strong']) {
      if (!columns.any((c) => c['name'] == name)) {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN $name TEXT NOT NULL DEFAULT ''",
        );
      }
    }
  }

  static Future<void> _aiOperations(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS ai_operations (id TEXT PRIMARY KEY, applied_at TEXT NOT NULL)',
  );

  static Future<void> _dayArchitectTables(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS recurring_schedules (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, type TEXT NOT NULL, weekday INTEGER NOT NULL,
      start_time TEXT NOT NULL, end_time TEXT NOT NULL, start_date TEXT NOT NULL, end_date TEXT,
      location TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', fixed INTEGER NOT NULL DEFAULT 1)''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS schedule_exceptions (
      schedule_id TEXT NOT NULL REFERENCES recurring_schedules(id) ON DELETE CASCADE,
      day TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'cancelled', start_time TEXT, end_time TEXT, moved_to_date TEXT,
      PRIMARY KEY(schedule_id, day))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS planning_preferences (
      id INTEGER PRIMARY KEY CHECK(id = 1), wake_time TEXT NOT NULL, bed_time TEXT NOT NULL,
      transition_minutes INTEGER NOT NULL, break_minutes INTEGER NOT NULL, exercise_period TEXT NOT NULL,
      avoid_focus_after TEXT NOT NULL, max_focus_minutes INTEGER NOT NULL, style TEXT NOT NULL,
      breakfast_window TEXT NOT NULL DEFAULT '07:00-09:00', lunch_window TEXT NOT NULL DEFAULT '12:00-14:00',
      dinner_window TEXT NOT NULL DEFAULT '18:00-20:00')''');
    await db.insert('planning_preferences', {
      'id': 1,
      'wake_time': '07:30',
      'bed_time': '23:00',
      'transition_minutes': 15,
      'break_minutes': 15,
      'exercise_period': 'flexible',
      'avoid_focus_after': '21:30',
      'max_focus_minutes': 90,
      'style': 'balanced',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    const entities = <String, String>{
      'recurring_schedules': '{row}.id',
      'schedule_exceptions': "{row}.schedule_id || '|' || {row}.day",
      'planning_preferences': 'CAST({row}.id AS TEXT)',
    };
    for (final entry in entities.entries) {
      final table = entry.key, key = entry.value;
      for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
        final row = operation == 'DELETE' ? 'OLD' : 'NEW';
        final id = key.replaceAll('{row}', row);
        final suffix = operation.toLowerCase();
        await db.execute(
          '''CREATE TRIGGER IF NOT EXISTS sync_${table}_$suffix AFTER $operation ON $table
          WHEN (SELECT applying_remote FROM sync_state WHERE id=1)=0 BEGIN
          INSERT INTO sync_outbox(mutation_id,entity_type,record_id,deleted,base_revision,created_at)
          VALUES(lower(hex(randomblob(16))),'$table',$id,${operation == 'DELETE' ? 1 : 0},
          COALESCE((SELECT revision FROM sync_records WHERE entity_type='$table' AND record_id=$id),0),
          strftime('%Y-%m-%dT%H:%M:%fZ','now'))
          ON CONFLICT(entity_type,record_id) DO UPDATE SET mutation_id=excluded.mutation_id,
          deleted=excluded.deleted,base_revision=excluded.base_revision,created_at=excluded.created_at;
          END''',
        );
      }
    }
  }

  static Future<void> _mealPreferenceColumns(Database db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(planning_preferences)',
    );
    const defaults = {
      'breakfast_window': '07:00-09:00',
      'lunch_window': '12:00-14:00',
      'dinner_window': '18:00-20:00',
    };
    for (final entry in defaults.entries) {
      if (!columns.any((column) => column['name'] == entry.key)) {
        await db.execute(
          "ALTER TABLE planning_preferences ADD COLUMN ${entry.key} TEXT NOT NULL DEFAULT '${entry.value}'",
        );
      }
    }
  }

  static Future<void> _scheduleMoveException(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(schedule_exceptions)');
    if (!columns.any((column) => column['name'] == 'moved_to_date')) {
      await db.execute(
        'ALTER TABLE schedule_exceptions ADD COLUMN moved_to_date TEXT',
      );
    }
  }

  static Future<void> _taskPriority(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(tasks)');
    if (!columns.any((column) => column['name'] == 'priority')) {
      await db.execute(
        "ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'",
      );
    }
  }

  static Future<void> _reminderBasis(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(reminders)');
    if (!columns.any((column) => column['name'] == 'basis')) {
      await db.execute(
        "ALTER TABLE reminders ADD COLUMN basis TEXT NOT NULL DEFAULT 'explicit'",
      );
      await db.execute(
        "UPDATE reminders SET basis = 'plannedTime' WHERE origin = 'defaulted'",
      );
    }
  }

  static Future<void> _syncTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_state (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      workspace_id TEXT,
      checkpoint INTEGER NOT NULL DEFAULT 0,
      seeded INTEGER NOT NULL DEFAULT 0,
      applying_remote INTEGER NOT NULL DEFAULT 0
    )''');
    await db.insert('sync_state', {
      'id': 1,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_records (
      entity_type TEXT NOT NULL,
      record_id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(entity_type, record_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS sync_outbox (
      mutation_id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      record_id TEXT NOT NULL,
      deleted INTEGER NOT NULL,
      base_revision INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      next_attempt_at TEXT,
      UNIQUE(entity_type, record_id)
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS planning_preference_changes (
      id INTEGER PRIMARY KEY CHECK(id = 1), fields TEXT NOT NULL
    )''');
    const entities = <String, String>{
      'captures': '{row}.id',
      'life_areas': '{row}.name',
      'projects': '{row}.id',
      'project_entries': '{row}.id',
      'tasks': '{row}.id',
      'plans': '{row}.id',
      'routines': '{row}.id',
      'routine_records': "{row}.routine_id || '|' || {row}.day",
      'focus_sessions': '{row}.id',
      'reminders': '{row}.id',
      'reminder_suppressions': '{row}.task_id',
      'quiet_hours': "CAST({row}.id AS TEXT)",
      'reminder_preferences': "CAST({row}.id AS TEXT)",
      'workspace_setup': "CAST({row}.id AS TEXT)",
    };
    for (final entry in entities.entries) {
      final table = entry.key;
      final key = entry.value;
      final newKey = key.replaceAll('{row}', 'NEW');
      final oldKey = key.replaceAll('{row}', 'OLD');
      for (final operation in ['INSERT', 'UPDATE']) {
        final suffix = operation == 'INSERT' ? 'insert' : 'update';
        await db.execute('''CREATE TRIGGER IF NOT EXISTS sync_${table}_$suffix
          AFTER $operation ON $table
          WHEN (SELECT applying_remote FROM sync_state WHERE id = 1) = 0
          BEGIN
            INSERT INTO sync_outbox(
              mutation_id, entity_type, record_id, deleted, base_revision, created_at
            ) VALUES (
              lower(hex(randomblob(16))), '$table', $newKey, 0,
              COALESCE((SELECT revision FROM sync_records
                WHERE entity_type = '$table' AND record_id = $newKey), 0),
              strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
            )
            ON CONFLICT(entity_type, record_id) DO UPDATE SET
              mutation_id = excluded.mutation_id,
              deleted = 0,
              base_revision = excluded.base_revision,
              created_at = excluded.created_at,
              attempts = 0,
              next_attempt_at = NULL;
          END''');
      }
      await db.execute('''CREATE TRIGGER IF NOT EXISTS sync_${table}_delete
        AFTER DELETE ON $table
        WHEN (SELECT applying_remote FROM sync_state WHERE id = 1) = 0
        BEGIN
          INSERT INTO sync_outbox(
            mutation_id, entity_type, record_id, deleted, base_revision, created_at
          ) VALUES (
            lower(hex(randomblob(16))), '$table', $oldKey, 1,
            COALESCE((SELECT revision FROM sync_records
              WHERE entity_type = '$table' AND record_id = $oldKey), 0),
            strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
          )
          ON CONFLICT(entity_type, record_id) DO UPDATE SET
            mutation_id = excluded.mutation_id,
            deleted = 1,
            base_revision = excluded.base_revision,
            created_at = excluded.created_at,
            attempts = 0,
            next_attempt_at = NULL;
        END''');
    }
  }

  static Future<void> _workspaceSetup(
    Database db, {
    required bool completed,
  }) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS workspace_setup (id INTEGER PRIMARY KEY CHECK(id = 1), completed INTEGER NOT NULL CHECK(completed IN (0, 1)))',
    );
    await db.insert('workspace_setup', {
      'id': 1,
      'completed': completed ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _workspace(Database db) async {
    await db.execute('CREATE TABLE life_areas (name TEXT PRIMARY KEY)');
    for (final name in ['Work', 'Study', 'Health', 'Relationships', 'Rest']) {
      await db.insert('life_areas', {'name': name});
    }
    await db.execute(
      'CREATE TABLE projects (id TEXT PRIMARY KEY, title TEXT NOT NULL, area TEXT NOT NULL REFERENCES life_areas(name), description TEXT NOT NULL)',
    );
    await db.execute(
      '''CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL,
      area TEXT NOT NULL REFERENCES life_areas(name), project_id TEXT REFERENCES projects(id),
      capture_id TEXT UNIQUE REFERENCES captures(id), deadline TEXT, minutes INTEGER NOT NULL CHECK(minutes > 0),
      notes TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','inProgress','completed','cancelled')), checklist TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE plans (id TEXT PRIMARY KEY, title TEXT NOT NULL,
      task_id TEXT REFERENCES tasks(id), start TEXT NOT NULL, minutes INTEGER NOT NULL CHECK(minutes > 0),
      area TEXT NOT NULL REFERENCES life_areas(name), fixed INTEGER NOT NULL)''',
    );
    await db.execute(
      'CREATE TABLE routines (id TEXT PRIMARY KEY, title TEXT NOT NULL, area TEXT NOT NULL REFERENCES life_areas(name), window TEXT NOT NULL, alternative TEXT NOT NULL, created_day TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE routine_records (routine_id TEXT REFERENCES routines(id), day TEXT NOT NULL, outcome TEXT NOT NULL, PRIMARY KEY(routine_id, day))',
    );
    await db.execute('''CREATE TABLE focus_sessions (id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id),
      minutes INTEGER NOT NULL, started_at TEXT NOT NULL, running_since TEXT, seconds INTEGER NOT NULL,
      outcome TEXT, notes TEXT NOT NULL)''');
    await db.execute(
      'CREATE UNIQUE INDEX one_active_focus ON focus_sessions ((1)) WHERE outcome IS NULL',
    );
  }

  static Future<void> _entries(Database db) async {
    await db.execute(
      'CREATE TABLE project_entries (id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id), title TEXT NOT NULL, body TEXT NOT NULL, kind TEXT NOT NULL, related_id TEXT REFERENCES project_entries(id), capture_id TEXT REFERENCES captures(id))',
    );
    await db.execute(
      'ALTER TABLE tasks ADD COLUMN entry_id TEXT REFERENCES project_entries(id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX one_task_per_entry ON tasks(entry_id)',
    );
    await db.execute(
      "ALTER TABLE focus_sessions ADD COLUMN area TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'UPDATE focus_sessions SET area = (SELECT area FROM tasks WHERE tasks.id = focus_sessions.task_id)',
    );
    await db.execute(
      "ALTER TABLE routine_records ADD COLUMN area TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'UPDATE routine_records SET area = (SELECT area FROM routines WHERE routines.id = routine_records.routine_id)',
    );
  }

  static Future<void> _reminders(Database db) async {
    await db.execute('''CREATE TABLE reminders (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL UNIQUE REFERENCES tasks(id) ON DELETE CASCADE,
      scheduled_at TEXT NOT NULL,
      origin TEXT NOT NULL DEFAULT 'explicit',
      basis TEXT NOT NULL DEFAULT 'explicit',
      recurrence TEXT NOT NULL DEFAULT 'none'
    )''');
  }

  static Future<void> _notificationState(Database db) => db.execute(
    "ALTER TABLE reminders ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'pending'",
  );

  static Future<void> _quietHours(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS quiet_hours (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      enabled INTEGER NOT NULL,
      start_minute INTEGER NOT NULL,
      end_minute INTEGER NOT NULL
    )''');
    final existing = await db.query('quiet_hours', where: 'id = 1');
    if (existing.isEmpty) {
      await db.insert('quiet_hours', {
        'id': 1,
        'enabled': 0,
        'start_minute': 23 * 60,
        'end_minute': 7 * 60,
      });
    }
  }

  static Future<void> _reminderDefaults(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS reminder_preferences (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      default_option TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS reminder_suppressions (
      task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE
    )''');
    final existing = await db.query('reminder_preferences', where: 'id = 1');
    if (existing.isEmpty) {
      await db.insert('reminder_preferences', {
        'id': 1,
        'default_option': ReminderDefault.none.name,
      });
    }
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) await (await opening).close();
    _opening = null;
  }
}
