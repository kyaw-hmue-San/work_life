import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/app.dart';
import 'package:work_life/workspace/editors.dart';
import 'package:work_life/workspace/local_data_export.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_model.dart';
import 'package:work_life/workspace/workspace_repository.dart';

import 'support/memory_workspace.dart';

const routine = Routine(
  id: 'exercise',
  title: 'Exercise',
  area: 'Health',
  window: 'Morning',
  alternative: 'Stretch 5 minutes',
  normal: 'Workout 20 minutes',
  strong: 'Workout 45 minutes',
  createdDay: '2030-01-01',
);
void main() {
  sqfliteFfiInit();
  late Directory dir;
  late SqliteWorkspaceRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('routine_levels_');
    repo = SqliteWorkspaceRepository(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/app.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });

  test(
    'levels persist, all complete, and same-day retries replace one occurrence',
    () async {
      await repo.saveRoutine(routine);
      for (final outcome in ['smaller', 'done', 'strong']) {
        await repo.recordRoutine(
          RoutineRecord(
            routineId: routine.id,
            day: '2030-01-01',
            outcome: outcome,
          ),
        );
        await repo.recordRoutine(
          RoutineRecord(
            routineId: routine.id,
            day: '2030-01-01',
            outcome: outcome,
          ),
        );
        await repo.close();
        final data = await repo.readWorkspace();
        expect(data.routines.single.normal, routine.normal);
        expect(data.routines.single.strong, routine.strong);
        expect(data.routineRecords, hasLength(1));
        expect(data.routineRecords.single.completed, isTrue);
        expect(data.routineRecords.single.area, 'Health');
      }
      expect(
        (await repo.readWorkspace()).routineRecords.single.level,
        RoutineLevel.strong,
      );
      await repo.recordRoutine(
        const RoutineRecord(
          routineId: 'exercise',
          day: '2030-01-02',
          outcome: 'later',
        ),
      );
      await repo.recordRoutine(
        const RoutineRecord(
          routineId: 'exercise',
          day: '2030-01-03',
          outcome: 'skipped',
        ),
      );
      final records = (await repo.readWorkspace()).routineRecords;
      expect(records.where((r) => r.completed), hasLength(1));
      expect(records.where((r) => r.day == '2030-01-04'), isEmpty);
    },
  );

  test('editing definitions leaves recorded level intact; undefined Strong rejects', () async {
    await repo.saveRoutine(routine);
    await repo.recordRoutine(
      const RoutineRecord(
        routineId: 'exercise',
        day: '2030-01-01',
        outcome: 'strong',
      ),
    );
    await repo.saveRoutine(
      const Routine(
        id: 'exercise',
        title: 'Walk',
        area: 'Rest',
        window: '',
        alternative: '',
        createdDay: '2030-01-01',
      ),
    );
    final data = await repo.readWorkspace();
    expect(data.routines.single.descriptionFor(RoutineLevel.normal), 'Walk');
    expect(data.routineRecords.single.level, RoutineLevel.strong);
    expect(data.routineRecords.single.area, 'Health');
    await expectLater(
      repo.recordRoutine(
        const RoutineRecord(
          routineId: 'exercise',
          day: '2030-01-02',
          outcome: 'strong',
        ),
      ),
      throwsArgumentError,
    );
    expect((await repo.readWorkspace()).routineRecords, hasLength(1));
  });

  test(
    'v8 migration retains smaller and done meaning without inventing Strong',
    () async {
      await repo.saveRoutine(routine);
      await repo.completeOnboarding();
      await repo.recordRoutine(
        const RoutineRecord(
          routineId: 'exercise',
          day: '2030-01-01',
          outcome: 'smaller',
        ),
      );
      await repo.recordRoutine(
        const RoutineRecord(
          routineId: 'exercise',
          day: '2030-01-02',
          outcome: 'done',
        ),
      );
      final db = await repo.database.open();
      await db.execute('ALTER TABLE routines DROP COLUMN normal');
      await db.execute('ALTER TABLE routines DROP COLUMN strong');
      await db.execute('PRAGMA user_version = 8');
      await repo.close();
      final data = await repo.readWorkspace();
      expect(data.onboardingCompleted, isTrue);
      expect(data.routines.single.id, 'exercise');
      expect(data.routines.single.alternative, routine.alternative);
      expect(
        data.routines.single.descriptionFor(RoutineLevel.normal),
        'Exercise',
      );
      expect(data.routines.single.strong, isEmpty);
      expect(data.routineRecords.map((r) => r.level).toSet(), {
        RoutineLevel.minimum,
        RoutineLevel.normal,
      });
    },
  );

  test('export includes definitions and level; reset removes both', () async {
    await repo.saveRoutine(routine);
    await repo.recordRoutine(
      const RoutineRecord(
        routineId: 'exercise',
        day: '2030-01-01',
        outcome: 'strong',
      ),
    );
    final export = jsonDecode(await LocalDataExport(repo).buildJson());
    expect(export['formatVersion'], 1);
    expect(export['data']['routines'].single['strong'], routine.strong);
    expect(export['data']['routineRecords'].single['level'], 'strong');
    expect(export['data']['routineRecords'].single['outcome'], 'strong');
    await repo.clearLocalData();
    await repo.close();
    expect((await repo.readWorkspace()).routines, isEmpty);
    expect((await repo.readWorkspace()).routineRecords, isEmpty);
  });

  testWidgets('Today and Routines record the same daily completion', (
    tester,
  ) async {
    final memory = MemoryWorkspace()..routines.add(routine);
    await tester.pumpWidget(WorkLifeApp(repository: memory));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Minimum'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimum'));
    await tester.pumpAndSettle();
    expect(memory.records.single.level, RoutineLevel.minimum);
    await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Routines'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Strong'));
    await tester.tap(find.text('Strong'));
    await tester.pumpAndSettle();
    expect(memory.records, hasLength(1));
    expect(memory.records.single.level, RoutineLevel.strong);
    expect(find.text('Today: Strong completed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'routine editor saves and edits level descriptions on one routine',
    (tester) async {
      final memory = MemoryWorkspace();
      final model = WorkspaceModel(memory);
      await model.load();
      await tester.pumpWidget(
        MaterialApp(
          home: RecordEditor(
            model: model,
            kind: 'routine',
            day: DateTime(2030),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'Exercise');
      Future<void> fill(String label, String value) async {
        final finder = find.widgetWithText(TextFormField, label);
        await tester.scrollUntilVisible(
          finder,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(finder, value);
      }

      await fill(
        'Normal (optional; uses routine title if empty)',
        '20 minute workout',
      );
      await fill(
        'Strong (optional, for example, workout 45 minutes)',
        '45 minute workout',
      );
      await fill(
        'Minimum (optional, for example, stretch 5 minutes)',
        '5 minute stretch',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save routine'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(memory.routines.single.normal, '20 minute workout');
      expect(memory.routines.single.strong, '45 minute workout');
      expect(memory.routines.single.alternative, '5 minute stretch');
      final saved = memory.routines.single;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: RecordEditor(
            model: model,
            kind: 'routine',
            routine: saved,
            day: DateTime(2030),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await fill(
        'Normal (optional; uses routine title if empty)',
        'Updated normal',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save routine'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save routine'));
      await tester.pumpAndSettle();
      expect(memory.routines, hasLength(1));
      expect(memory.routines.single.id, saved.id);
      expect(memory.routines.single.normal, 'Updated normal');
      expect(memory.routines.single.strong, '45 minute workout');
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
