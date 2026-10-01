import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/app.dart';
import 'package:work_life/accounts/account_host.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_repository.dart';

import 'support/memory_workspace.dart';
import 'support/fake_accounts.dart';
import 'support/populated_workspace.dart';

void main() {
  sqfliteFfiInit();
  test(
    'completion, preferences, reset and workspace isolation survive reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('onboarding_');
      final a = SqliteWorkspaceRepository(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/a.db',
      );
      final b = SqliteWorkspaceRepository(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/b.db',
      );
      addTearDown(() async {
        await a.close();
        await b.close();
        await dir.delete(recursive: true);
      });
      expect((await a.readWorkspace()).onboardingCompleted, isFalse);
      await populateWorkspace(a);
      await a.completeOnboarding(
        reminderDefault: ReminderDefault.oneHourBefore,
      );
      await a.addArea('Work');
      await a.addArea('Creative');
      await a.close();
      final data = await a.readWorkspace();
      expect(data.onboardingCompleted, isTrue);
      expect(data.reminderDefault, ReminderDefault.oneHourBefore);
      expect(data.areas.toSet().length, data.areas.length);
      expect(data.tasks, hasLength(2));
      expect(data.reminders.single.origin, ReminderOrigin.explicit);
      expect(data.suppressedTaskIds, ['suppressed']);
      expect((await b.readWorkspace()).onboardingCompleted, isFalse);
      await b.completeOnboarding();
      await a.clearLocalData();
      await a.close();
      expect((await a.readWorkspace()).onboardingCompleted, isFalse);
      expect((await b.readWorkspace()).onboardingCompleted, isTrue);
      await a.completeOnboarding();
      await a.close();
      expect((await a.readWorkspace()).onboardingCompleted, isTrue);
      expect((await a.readWorkspace()).reminderDefault, ReminderDefault.none);
    },
  );

  test('v7 upgrade treats existing workspace as returning without changing settings', () async {
    final dir = await Directory.systemTemp.createTemp('onboarding_upgrade_');
    final repo = SqliteWorkspaceRepository(
      factory: databaseFactoryFfi,
      databasePath: '${dir.path}/app.db',
    );
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
    await populateWorkspace(repo);
    final db = await repo.database.open();
    await db.execute('DROP TABLE workspace_setup');
    await db.execute('PRAGMA user_version = 7');
    await repo.close();
    final data = await repo.readWorkspace();
    expect(data.onboardingCompleted, isTrue);
    expect(data.reminderDefault, ReminderDefault.thirtyMinutesBefore);
    expect(data.quietHours.enabled, isTrue);
    expect(data.tasks, hasLength(2));
  });

  test(
    'failed completion rolls back reminder choice and completion together',
    () async {
      final dir = await Directory.systemTemp.createTemp('onboarding_fail_');
      final repo = SqliteWorkspaceRepository(
        factory: databaseFactoryFfi,
        databasePath: '${dir.path}/app.db',
      );
      addTearDown(() async {
        await repo.close();
        await dir.delete(recursive: true);
      });
      final db = await repo.database.open();
      await db.execute(
        "CREATE TRIGGER fail_setup BEFORE UPDATE ON workspace_setup BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        repo.completeOnboarding(reminderDefault: ReminderDefault.atTime),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.readWorkspace()).onboardingCompleted, isFalse);
      expect(
        (await repo.readWorkspace()).reminderDefault,
        ReminderDefault.none,
      );
    },
  );

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text(text)),
      alignment: 0.5,
    );
    await tester.pump();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'new workspace completes three steps and reopens normal navigation',
    (tester) async {
      final repo = MemoryWorkspace(onboardingCompleted: false);
      await tester.pumpWidget(WorkLifeApp(repository: repo));
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Work Life'), findsOneWidget);
      await tap(tester, 'Get Started');
      await tester.enterText(find.byType(TextField), 'Creative');
      await tap(tester, 'Add life area');
      expect(repo.areas.where((a) => a == 'Creative'), hasLength(1));
      await tap(tester, 'Continue');
      await tap(tester, '30 minutes before');
      await tap(tester, 'Start using Work Life');
      expect(repo.reminderDefault, ReminderDefault.thirtyMinutesBefore);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(WorkLifeApp(repository: repo));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Work Life'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'large text skip retries failure and keeps existing preferences',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = MemoryWorkspace(onboardingCompleted: false)
        ..failOnboarding = true
        ..reminderDefault = ReminderDefault.atTime;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: WorkLifeApp(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Get Started');
      await tap(tester, 'Continue');
      await tap(tester, '1 hour before');
      await tap(tester, 'Skip setup');
      expect(repo.onboardingCompleted, isFalse);
      expect(find.textContaining('Couldn’t finish'), findsOneWidget);
      repo.failOnboarding = false;
      await tap(tester, 'Skip setup');
      expect(repo.onboardingCompleted, isTrue);
      expect(repo.reminderDefault, ReminderDefault.atTime);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Settings rerun preserves records and skip keeps current preference',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final memory = MemoryWorkspace();
      await populateWorkspace(memory);
      await tester.pumpWidget(WorkLifeApp(repository: memory));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Settings'));
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tap(tester, 'Run setup again');
      await tap(tester, 'Get Started');
      await tap(tester, 'Continue');
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '30 minutes before'),
            )
            .value,
        isTrue,
      );
      await tap(tester, '1 hour before');
      await tap(tester, 'Skip setup');
      expect(find.text('Settings'), findsOneWidget);
      expect(memory.reminderDefault, ReminderDefault.thirtyMinutesBefore);
      await tap(tester, 'Run setup again');
      await tap(tester, 'Get Started');
      await tap(tester, 'Continue');
      await tap(tester, '1 hour before');
      await tap(tester, 'Start using Work Life');
      expect(memory.reminderDefault, ReminderDefault.oneHourBefore);
      expect(memory.tasks, hasLength(2));
      expect(memory.reminders, hasLength(1));
      expect(memory.routines, hasLength(1));
      expect(memory.areas.where((area) => area == 'Creative'), hasLength(1));
      expect(memory.onboardingCompleted, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('account change selects independent onboarding state', (
    tester,
  ) async {
    final accounts = FakeAccounts();
    final repos = <String, MemoryWorkspace>{};
    await tester.pumpWidget(
      AccountHost(
        accounts: accounts,
        repositoryFactory: (name) => repos.putIfAbsent(
          name,
          () => MemoryWorkspace(onboardingCompleted: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Use offline guest workspace');
    await tap(tester, 'Skip setup');
    accounts.setUser('alice');
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Work Life'), findsOneWidget);
    accounts.setUser(null);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your real account.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
