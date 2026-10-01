import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:work_life/ai/aimlapi_client.dart';
import 'package:work_life/ai/capture_assistant.dart';
import 'package:work_life/ai/ai_capture_proposal_screen.dart';
import 'package:work_life/ai/ai_proposal_screen.dart';
import 'package:work_life/ai/ai_proposals.dart';
import 'package:work_life/ai/ai_schedule_screen.dart';
import 'package:work_life/workspace/calendar_progress.dart';
import 'package:work_life/workspace/records.dart';
import 'package:work_life/workspace/workspace_model.dart';

import 'support/memory_workspace.dart';

void main() {
  test('offline capture fallback recognizes ordinary commitments', () {
    final suggestion = const CaptureAssistant().suggest(
      'I have to return my parcel coming Tuesday',
    );
    expect(suggestion?.kind, 'Possible task');
  });

  test('AI provider failures become safe user-facing errors', () async {
    final client = AimlApiClient(
      apiKey: 'test-key',
      model: 'retired-model',
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"message":"technical provider details"}}',
          404,
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.suggest(capture: 'Plan this'),
      throwsA(
        isA<AiServiceException>()
            .having(
              (error) => error.message,
              'friendly message',
              contains('selected AI model'),
            )
            .having(
              (error) => error.message,
              'does not expose provider body',
              isNot(contains('technical provider details')),
            ),
      ),
    );
  });

  test('secure AI proxy receives auth token and operation wrapper', () async {
    late http.Request sent;
    final client = AimlApiClient(
      proxyUrl: 'https://example.test/functions/v1/ai-proxy',
      accessToken: () async => 'account-token',
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          '{"choices":[{"message":{"content":"A useful suggestion"}}]}',
          200,
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await client.suggest(capture: 'Plan this');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(sent.headers['authorization'], 'Bearer account-token');
    expect(body['operation'], 'suggest');
    expect((body['request'] as Map)['messages'], isA<List>());
    expect(result.text, 'A useful suggestion');
  });

  test('secure AI proxy requires an account session', () async {
    final client = AimlApiClient(
      proxyUrl: 'https://example.test/functions/v1/ai-proxy',
      accessToken: () async => null,
      client: MockClient((_) async => http.Response('{}', 500)),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.suggest(capture: 'Plan this'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'capture classifier sends existing areas and preserves ordered actions',
    () async {
      late Map<String, dynamic> sent;
      final client = AimlApiClient(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'type': 'capture_proposal',
                      'kind': 'project',
                      'project': {
                        'title': 'Airport pickups',
                        'area': 'Personal',
                        'tasks': [
                          {
                            'title': 'Pick up friend',
                            'group': 'Airport',
                            'minutes': 30,
                          },
                          {
                            'title': 'Pick up parcel at terminal',
                            'minutes': 15,
                          },
                        ],
                      },
                      'questions': [],
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      final proposal = await client.classifyCapture(
        'Pick up my friend, then collect my parcel at the terminal',
        existingAreas: ['Work', 'Personal'],
        planningContext: {
          'existingCalendar': [
            {'title': 'Class', 'start': '2099-05-01T09:00:00+07:00'},
          ],
        },
      );
      final userMessage = (sent['messages'] as List).last as Map;
      final context = jsonDecode(userMessage['content'] as String) as Map;
      expect(context['existingAreas'], ['Work', 'Personal']);
      expect(context['planningContext'], isNotEmpty);
      expect(proposal.kind, AiCaptureKind.project);
      expect(proposal.project!.tasks.map((task) => task.title), [
        'Pick up friend',
        'Pick up parcel at terminal',
      ]);
      expect(proposal.project!.tasks.first.group, 'Airport');
    },
  );

  test(
    'capture clarification sends answers and current editable plan',
    () async {
      late Map<String, dynamic> sent;
      final client = AimlApiClient(
        apiKey: 'test-key',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'type': 'project_proposal',
                      'project': {
                        'title': 'Birthday and immigration plan',
                        'area': 'Personal',
                        'tasks': [
                          {
                            'title': 'Submit visa extension',
                            'group': 'Immigration',
                            'deadline': '2099-05-03',
                          },
                        ],
                      },
                      'questions': [],
                    }),
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await client.refineCaptureProject(
        originalInput: 'Plan a birthday and extend my visa',
        proposal: AiProjectProposal(
          title: 'My plan',
          area: 'Personal',
          tasks: [AiTaskProposal(title: 'Visit immigration')],
          questions: const ['When does your visa expire?'],
        ),
        answers: const {'When does your visa expire?': 'May 3, 2099'},
        existingAreas: const ['Personal'],
        planningContext: const {'timezone': 'Asia/Bangkok'},
      );
      final userMessage = (sent['messages'] as List).last as Map;
      final context = jsonDecode(userMessage['content'] as String) as Map;
      expect(
        (context['answers'] as Map)['When does your visa expire?'],
        'May 3, 2099',
      );
      expect((context['currentProposal'] as Map)['title'], 'My plan');
      expect(context['planningContext'], {'timezone': 'Asia/Bangkok'});
      expect(result.tasks.single.group, 'Immigration');
      expect(result.tasks.single.deadline, '2099-05-03');
    },
  );

  test('schedule image requests stop at the configured timeout', () async {
    final pending = Completer<http.Response>();
    final client = AimlApiClient(
      apiKey: 'test-key',
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) => pending.future),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.analyzeScheduleImage(Uint8List.fromList([1, 2, 3])),
      throwsA(
        isA<AiServiceException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test(
    'schedule image import reports real stages and sends one request',
    () async {
      final stages = <ScheduleImportStage>[];
      var requests = 0;
      late Map<String, dynamic> sent;
      final client = AimlApiClient(
        apiKey: 'test-key',
        model: 'text-model',
        visionModel: 'fast-vision-model',
        client: MockClient((request) async {
          requests++;
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'type': 'schedule_proposal',
                      'events': [
                        {
                          'title': 'Software class',
                          'kind': 'classSession',
                          'weekday': 1,
                          'start': '09:00',
                          'end': '10:00',
                        },
                      ],
                      'questions': [],
                    }),
                  },
                },
              ],
            }),
            200,
            headers: const {
              'server-timing': 'auth;dur=8.0, provider;dur=1200.0',
            },
          );
        }),
      );
      addTearDown(client.dispose);
      final proposal = await client.analyzeScheduleImage(
        Uint8List.fromList([1, 2, 3]),
        onProgress: (value) => stages.add(value.stage),
      );
      expect(requests, 1);
      expect(sent['model'], 'fast-vision-model');
      expect(stages, [
        ScheduleImportStage.preparingImage,
        ScheduleImportStage.uploadingAndReading,
        ScheduleImportStage.buildingProposal,
        ScheduleImportStage.ready,
      ]);
      expect(proposal.events.single.title, 'Software class');
    },
  );

  testWidgets('suggested Life Area is explicit and rejecting saves nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryWorkspace();
    final model = WorkspaceModel(repo);
    await model.load();
    addTearDown(model.dispose);
    AiProjectProposal proposal() => AiProjectProposal(
      title: 'Plan holiday',
      area: 'Travel',
      tasks: [AiTaskProposal(title: 'Check flights')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AiProjectProposalScreen(model: model, proposal: proposal()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Suggested Life Area'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(repo.projects, isEmpty);
    expect(repo.areas, isNot(contains('Travel')));

    await tester.pumpWidget(
      MaterialApp(
        home: AiProjectProposalScreen(model: model, proposal: proposal()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Approve plan'));
    await tester.tap(find.text('Approve plan'));
    await tester.pumpAndSettle();
    expect(repo.areas, contains('Travel'));
    expect(repo.projects.single.area, 'Travel');
  });

  testWidgets('single capture questions can refine the draft before approval', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryWorkspace();
    final model = WorkspaceModel(repo);
    await model.load();
    addTearDown(model.dispose);
    Map<String, String>? received;
    await tester.pumpWidget(
      MaterialApp(
        home: AiCaptureProposalScreen(
          model: model,
          proposal: AiCaptureProposal(
            kind: AiCaptureKind.standaloneTask,
            task: AiTaskProposal(title: 'Visit immigration'),
            questions: const ['When does your visa expire?'],
          ),
          onClarify: (current, answers) async {
            received = answers;
            return AiCaptureProposal(
              kind: current.kind,
              task: AiTaskProposal(
                title: 'Prepare visa extension documents',
                deadline: '2099-05-03',
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('When does your visa expire?'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Type your answer…'),
      'May 3, 2099',
    );
    await tester.tap(find.text('Update with answers'));
    await tester.pumpAndSettle();
    expect(received?['When does your visa expire?'], 'May 3, 2099');
    expect(find.text('Prepare visa extension documents'), findsOneWidget);
    expect(repo.tasks, isEmpty);
  });

  testWidgets(
    'proposal questions accept answers and refresh only the draft plan',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryWorkspace();
      final model = WorkspaceModel(repo);
      await model.load();
      addTearDown(model.dispose);
      final initial = AiProjectProposal(
        title: 'Important errands',
        tasks: [AiTaskProposal(title: 'Visit immigration')],
        questions: const ['When does your visa expire?'],
      );
      Map<String, String>? received;
      await tester.pumpWidget(
        MaterialApp(
          home: AiProjectProposalScreen(
            model: model,
            proposal: initial,
            onClarify: (current, answers) async {
              received = answers;
              return AiProjectProposal(
                title: current.title,
                tasks: [
                  AiTaskProposal(
                    title: 'Prepare visa extension documents',
                    group: 'Immigration',
                    deadline: '2099-05-03',
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('When does your visa expire?'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Type your answer…'),
        'May 3, 2099',
      );
      await tester.tap(find.text('Update plan with answers'));
      await tester.pumpAndSettle();
      expect(received?['When does your visa expire?'], 'May 3, 2099');
      expect(find.text('Immigration'), findsOneWidget);
      expect(find.text('Prepare visa extension documents'), findsOneWidget);
      expect(repo.projects, isEmpty);
    },
  );

  test('calendar progress counts each task once and updates to complete', () {
    final day = DateTime(2035, 4, 16);
    const first = Task(
      id: 'first',
      title: 'First',
      area: 'Work',
      deadline: '2035-04-16',
      status: TaskStatus.completed,
    );
    const second = Task(id: 'second', title: 'Second', area: 'Study');
    final plan = PlanBlock(
      id: 'plan',
      title: 'Second',
      taskId: second.id,
      start: DateTime(2035, 4, 16, 10),
      minutes: 30,
      area: 'Study',
    );
    final duplicatePlan = PlanBlock(
      id: 'duplicate',
      title: 'First again',
      taskId: first.id,
      start: DateTime(2035, 4, 16, 11),
      minutes: 30,
      area: 'Work',
    );
    final partial = CalendarProgress(
      WorkspaceData(tasks: const [first, second], plans: [plan, duplicatePlan]),
    ).forDay(day);
    expect(partial.total, 2);
    expect(partial.completed, 1);
    expect(partial.fraction, .5);

    final complete = CalendarProgress(
      WorkspaceData(
        tasks: [first, second.withStatus(TaskStatus.completed)],
        plans: [plan, duplicatePlan],
      ),
    ).forDay(day);
    expect(complete.fraction, 1);
  });

  test(
    'approved schedule creates normal planner blocks exactly once',
    () async {
      final repo = MemoryWorkspace();
      repo.tasks.add(
        const Task(id: 'task', title: 'Prepare slides', area: 'Work'),
      );
      final proposal = AiScheduleProposal(
        events: [
          AiScheduleEvent(
            title: 'Prepare slides',
            taskId: 'task',
            area: 'Work',
            date: '2035-04-16',
            start: '09:00',
            end: '10:00',
          ),
          AiScheduleEvent(
            title: 'Walk and reset',
            area: 'Health',
            date: '2035-04-16',
            start: '10:15',
            end: '10:35',
          ),
        ],
      );
      await repo.applyScheduleProposal(proposal, operationId: 'day-plan');
      await repo.applyScheduleProposal(proposal, operationId: 'day-plan');
      expect(repo.plans, hasLength(2));
      expect(repo.plans.first.taskId, 'task');
      expect(repo.plans.last.area, 'Health');
    },
  );

  test(
    'approved project improvement updates existing records safely',
    () async {
      final repo = MemoryWorkspace();
      repo.projects.add(
        const Project(id: 'project', title: 'Portfolio', area: 'Work'),
      );
      repo.tasks.add(
        const Task(id: 'existing', title: 'Build pages', area: 'Work'),
      );
      final proposal = AiProjectProposal(
        title: 'Professional portfolio',
        description: 'Show selected work clearly.',
        area: 'Work',
        tasks: [
          AiTaskProposal(
            taskId: 'existing',
            title: 'Build accessible project pages',
            priority: 'high',
          ),
          AiTaskProposal(title: 'Deploy and review', priority: 'medium'),
        ],
      );
      await repo.applyProjectProposal(
        proposal,
        operationId: 'improve',
        targetProjectId: 'project',
      );
      expect(repo.projects, hasLength(1));
      expect(repo.projects.single.title, 'Professional portfolio');
      expect(repo.tasks, hasLength(2));
      expect(
        repo.tasks.singleWhere((task) => task.id == 'existing').priority,
        TaskPriority.high,
      );
    },
  );

  testWidgets(
    'proposal screens render native controls and rejection saves nothing',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = MemoryWorkspace();
      final model = WorkspaceModel(repo);
      await model.load();
      addTearDown(model.dispose);
      final proposal = AiProjectProposal(
        title: 'AWS preparation',
        tasks: [AiTaskProposal(title: 'Review core services')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AiProjectProposalScreen(model: model, proposal: proposal),
        ),
      );
      expect(find.text('Plan title'), findsOneWidget);
      expect(find.text('Review core services'), findsOneWidget);
      expect(find.textContaining('{"type"'), findsNothing);
      await tester.tap(find.text('Keep only the original note'));
      await tester.pumpAndSettle();
      expect(repo.projects, isEmpty);
      expect(repo.tasks, isEmpty);
    },
  );

  testWidgets('schedule proposal uses editable native cards rather than JSON', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryWorkspace();
    final model = WorkspaceModel(repo);
    await model.load();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AiScheduleProposalScreen(
          model: model,
          proposal: AiScheduleProposal(
            events: [
              AiScheduleEvent(
                title: 'Exercise',
                date: '2035-04-16',
                start: '16:00',
                end: '16:30',
                area: 'Health',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Suggested schedule'), findsOneWidget);
    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('Start 16:00'), findsOneWidget);
    expect(find.textContaining('{"events"'), findsNothing);
  });

  testWidgets('weekly proposal groups all seven days and supports selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryWorkspace();
    final model = WorkspaceModel(repo);
    await model.load();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AiScheduleProposalScreen(
          model: model,
          weekStart: DateTime(2035, 4, 16),
          proposal: AiScheduleProposal(
            events: [
              AiScheduleEvent(
                title: 'Deep work',
                date: '2035-04-16',
                start: '09:00',
                end: '10:00',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Suggested week'), findsOneWidget);
    expect(find.text('Monday, April 16, 2035'), findsOneWidget);
    expect(find.text('Sunday, April 22, 2035'), findsOneWidget);
    expect(find.text('Intentional open time'), findsNWidgets(6));
    expect(find.text('Apply selected week'), findsOneWidget);
    expect(find.textContaining('{"events"'), findsNothing);
  });
}
