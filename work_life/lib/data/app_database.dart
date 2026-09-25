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
      version: 9,
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
      origin TEXT NOT NULL DEFAULT 'explicit'
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
