import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/accounts/account_config.dart';
import 'package:work_life/accounts/account_host.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/settings_screen.dart';
import 'package:work_life/workspace/workspace_model.dart';

import 'support/fake_accounts.dart';
import 'support/memory_workspace.dart';

void main() {
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'confirmation cancels safely; reset refreshes Inbox and preserves account isolation',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = FakeAccounts()..setUser('alice');
      final alice = MemoryWorkspace()
        ..captures.add(Capture.create('Alice original'));
      final guest = MemoryWorkspace()
        ..captures.add(Capture.create('Guest original'));
      await tester.pumpWidget(
        AccountHost(
          accounts: accounts,
          repositoryFactory: (name) =>
              name == accountDatabaseName(accounts.namespace, 'alice')
              ? alice
              : guest,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(NavigationDestination, 'Inbox'));
      expect(find.text('Alice original'), findsOneWidget);
      await tap(tester, find.widgetWithText(NavigationDestination, 'More'));
      await tap(tester, find.text('Settings'));
      await tap(tester, find.text('Delete all local data'));
      expect(alice.captures, hasLength(1));
      await tap(tester, find.text('Cancel'));
      expect(alice.captures, hasLength(1));
      await tap(tester, find.text('Delete all local data'));
      await tap(tester, find.text('Delete'));
      expect(find.text('Local workspace data deleted.'), findsOneWidget);
      expect(find.text('Welcome to Work Life'), findsOneWidget);
      await tap(tester, find.text('Skip setup'));
      expect(accounts.user!.id, 'alice');
      expect(guest.captures, hasLength(1));
      await tap(tester, find.widgetWithText(NavigationDestination, 'Inbox'));
      expect(find.text('Alice original'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'What’s on your mind?'),
        'New capture',
      );
      await tester.pump();
      await tap(tester, find.text('Save as note'));
      expect(alice.captures.single.originalText, 'New capture');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'deletion shows progress, blocks duplicates, and reports storage failure',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _SlowReset();
      final model = WorkspaceModel(repo);
      await model.load();
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(model: model)));
      await tap(tester, find.text('Delete all local data'));
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, 'Delete all local data'),
            )
            .enabled,
        isFalse,
      );
      expect(await model.deleteLocalData(), isFalse);
      repo.gate.completeError(StateError('Storage failed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not delete local data. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Local workspace data deleted.'), findsNothing);
      expect(model.busy, isFalse);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );

  testWidgets('backup and readable exports share purpose-specific files', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = WorkspaceModel(MemoryWorkspace());
    await model.load();
    final shared = <ShareParams>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          model: model,
          share: (params) async {
            shared.add(params);
            return const ShareResult('', ShareResultStatus.dismissed);
          },
        ),
      ),
    );
    await tap(tester, find.text('Create backup'));
    expect(shared.single.files!.single.mimeType, 'application/json');
    expect(shared.single.fileNameOverrides, ['work_life_backup.json']);
    expect(shared.single.sharePositionOrigin!.isEmpty, isFalse);
    expect(
      jsonDecode(
        utf8.decode(await shared.single.files!.single.readAsBytes()),
      )['formatVersion'],
      1,
    );
    await tap(tester, find.text('Export readable report'));
    expect(shared.last.files!.single.mimeType, 'text/markdown');
    expect(shared.last.fileNameOverrides, ['work_life_report.md']);
    expect(
      utf8.decode(await shared.last.files!.single.readAsBytes()),
      contains('# Work Life report'),
    );
    await tap(tester, find.text('Export tasks as CSV'));
    expect(shared.last.files!.single.mimeType, 'text/csv');
    expect(shared.last.fileNameOverrides, ['work_life_tasks.csv']);
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}

class _SlowReset extends MemoryWorkspace {
  final gate = Completer<void>();
  @override
  Future<void> clearLocalData() => gate.future;
}
