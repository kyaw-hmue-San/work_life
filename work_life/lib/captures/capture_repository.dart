import '../data/app_database.dart';

import 'package:sqflite/sqflite.dart';

import 'capture.dart';

abstract interface class CaptureRepository {
  Future<List<Capture>> load();
  Future<void> save(Capture capture);
}

class SqliteCaptureRepository implements CaptureRepository {
  SqliteCaptureRepository({
    DatabaseFactory? factory,
    String? databasePath,
    String databaseName = 'work_life.db',
  }) : database = AppDatabase(
         factory: factory,
         databasePath: databasePath,
         databaseName: databaseName,
       );

  final AppDatabase database;

  @override
  Future<List<Capture>> load() async {
    final rows = await (await database.open()).query(
      'captures',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows
        .map(
          (row) => Capture(
            id: row['id'] as String,
            originalText: row['original_text'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> save(Capture capture) async {
    if (capture.originalText.trim().isEmpty) {
      throw ArgumentError('Capture is empty');
    }
    await (await database.open()).insert('captures', {
      'id': capture.id,
      'original_text': capture.originalText,
      'created_at': capture.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> close() => database.close();
}
