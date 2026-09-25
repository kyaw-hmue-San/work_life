import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/captures/capture_repository.dart';

void main() {
  sqfliteFfiInit();
  test(
    'SQLite preserves original text across close/reopen and deduplicates retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'work_life_test_',
      );
      final file = '${directory.path}/captures.db';
      var repository = SqliteCaptureRepository(
        factory: databaseFactoryFfi,
        databasePath: file,
      );
      try {
        final capture = Capture.create('  Friday?\nDinner 🍲 with family  ');
        await repository.save(capture);
        await repository.save(capture);
        await repository.close();
        repository = SqliteCaptureRepository(
          factory: databaseFactoryFfi,
          databasePath: file,
        );
        final items = await repository.load();
        expect(items, hasLength(1));
        expect(items.single.id, capture.id);
        expect(items.single.originalText, capture.originalText);
        expect(items.single.createdAt, capture.createdAt);
        await expectLater(
          repository.save(Capture.create('  \n')),
          throwsArgumentError,
        );
      } finally {
        await repository.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
