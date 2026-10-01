import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:work_life/ai/aimlapi_client.dart';
import 'package:work_life/captures/inbox_screen.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/captures/capture_repository.dart';

class MemoryRepository implements CaptureRepository {
  final List<Capture> items = [];
  bool failSave = false;
  bool failLoad = false;
  @override
  Future<List<Capture>> load() async {
    if (failLoad) throw StateError('unavailable');
    return List.of(items);
  }

  @override
  Future<void> save(Capture capture) async {
    if (failSave) throw StateError('disk full');
    items.add(capture);
  }
}

void main() {
  void roomyScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('capture, search, read original, and rebuild inbox', (
    tester,
  ) async {
    roomyScreen(tester);
    final repository = MemoryRepository();
    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '  Dinner with family\nFriday?  ',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save capture'));
    await tester.tap(find.text('Save capture'));
    await tester.pumpAndSettle();
    expect(
      repository.items.single.originalText,
      '  Dinner with family\nFriday?  ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Search your captures'),
      'missing',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching captures'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search your captures'),
      'FAMILY',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ListTile));
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('  Dinner with family\nFriday?  '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('  Dinner with family\nFriday?  '), findsOneWidget);
  });

  testWidgets('save failure preserves draft and retry saves once', (
    tester,
  ) async {
    roomyScreen(tester);
    final repository = MemoryRepository()..failSave = true;
    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Take a walk');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save capture'));
    await tester.tap(find.text('Save capture'));
    await tester.pumpAndSettle();
    expect(find.text('Take a walk'), findsOneWidget);
    expect(find.textContaining('Couldn’t save yet'), findsOneWidget);
    repository.failSave = false;
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save capture'));
    await tester.tap(find.text('Save capture'));
    await tester.pumpAndSettle();
    expect(repository.items, hasLength(1));
  });

  testWidgets('loading failure offers retry; blank capture disabled', (
    tester,
  ) async {
    roomyScreen(tester);
    final repository = MemoryRepository()..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(home: InboxScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    repository.failLoad = false;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '   ');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('small screen with large text lays out without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: InboxScreen(repository: MemoryRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule import blocks duplicate submissions', (tester) async {
    roomyScreen(tester);
    final selection = Completer<XFile?>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(
          repository: MemoryRepository(),
          scheduleImagePicker: () {
            calls++;
            return selection.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import a schedule image'));
    await tester.tap(find.text('Import a schedule image'));
    await tester.tap(find.text('Import a schedule image'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    selection.complete(null);
    await tester.pumpAndSettle();
  });

  testWidgets('schedule import shows progress and a safe retry on failure', (
    tester,
  ) async {
    roomyScreen(tester);
    final response = Completer<http.Response>();
    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(
          repository: MemoryRepository(),
          scheduleImagePicker: () async =>
              XFile.fromData(Uint8List.fromList([1, 2, 3])),
          scheduleAiClientFactory: () => AimlApiClient(
            apiKey: 'test-key',
            client: MockClient((_) => response.future),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import a schedule image'));
    await tester.tap(find.text('Import a schedule image'));
    await tester.pump();
    expect(find.text('Reading your schedule'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    response.complete(http.Response('{"error":{}}', 500));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('existing data are safe'), findsOneWidget);
  });
}
