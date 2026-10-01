import 'package:flutter_test/flutter_test.dart';
import 'package:work_life/ai/ai_proposals.dart';

import 'support/memory_workspace.dart';

void main() {
  const parser = AiProposalParser();

  test('valid project proposal parses into editable tasks', () {
    final proposal = parser.project(
      '''{"type":"project_proposal","project":{"title":"AWS preparation","area":"Study","tasks":[{"title":"Study core services","priority":"high","minutes":40}]},"questions":["Which exam date?"]}''',
    );
    expect(proposal.title, 'AWS preparation');
    expect(proposal.tasks.single.priority, 'high');
    expect(proposal.tasks.single.minutes, 40);
    expect(proposal.questions, ['Which exam date?']);
  });

  test('project diff operations parse for native review cards', () {
    final proposal = parser.project(
      '''{"type":"project_proposal","project":{"title":"AWS","tasks":[{"taskId":null,"operation":"add","title":"Mock exam"},{"taskId":"one","operation":"change","title":"Study core services"},{"taskId":"two","operation":"move","title":"Practice exam","deadline":"2026-10-10"},{"taskId":"three","operation":"remove","title":"Old task"},{"taskId":"four","operation":"unchanged","title":"Keep task"}]},"questions":[]}''',
    );
    expect(proposal.tasks.map((task) => task.change), [
      AiProjectChange.add,
      AiProjectChange.change,
      AiProjectChange.move,
      AiProjectChange.remove,
      AiProjectChange.unchanged,
    ]);
  });

  test('project proposal accepts JSON wrapped in a Markdown code fence', () {
    final proposal = parser.project('''```json
{"type":"project_proposal","project":{"title":"Return parcel","tasks":[{"title":"Check return instructions","priority":"medium","minutes":10}]},"questions":[]}
```''');
    expect(proposal.title, 'Return parcel');
    expect(proposal.tasks.single.title, 'Check return instructions');
  });

  test('malformed or unsafe proposal is rejected', () {
    expect(
      () => parser.project(
        '{"type":"project_proposal","project":{"title":"x","tasks":[]}}',
      ),
      throwsFormatException,
    );
    expect(
      () => parser.project(
        '{"type":"project_proposal","project":{"title":"x","tasks":[{"title":"x","priority":"urgent"}]}}',
      ),
      throwsFormatException,
    );
  });

  test('schedule proposal preserves unknown date/time as null', () {
    final proposal = parser.schedule(
      '''{"type":"schedule_proposal","events":[{"title":"Walk","date":null,"start":null,"end":null}],"questions":["Which day?"]}''',
    );
    expect(proposal.events.single.title, 'Walk');
    expect(proposal.events.single.date, isNull);
    expect(proposal.questions, ['Which day?']);
  });

  test('schedule extraction reads weekday for recurring timetable review', () {
    final proposal = parser.schedule(
      '''{"type":"schedule_proposal","events":[{"title":"Software Engineering","weekday":"Monday","start":"09:00","end":"10:30"},{"title":"Lab","weekday":5,"start":"13:00","end":"15:00"}],"questions":[]}''',
    );
    expect(proposal.events.map((e) => e.weekday), [1, 5]);
  });

  test(
    'capture classification parses every supported native proposal type',
    () {
      final task = parser.capture(
        '''{"type":"capture_proposal","kind":"standalone_task","task":{"title":"Submit assignment","deadline":"2026-10-01","priority":"high","minutes":30},"questions":[]}''',
      );
      final project = parser.capture(
        '''{"type":"capture_proposal","kind":"project","project":{"title":"AWS certification","tasks":[{"title":"Choose exam","priority":"medium","minutes":25}]},"questions":[]}''',
      );
      final routine = parser.capture(
        '''{"type":"capture_proposal","kind":"routine","routine":{"title":"Exercise","window":"Monday, Wednesday and Friday","minimum":"Walk 10 minutes"},"questions":[]}''',
      );
      final reminder = parser.capture(
        '''{"type":"capture_proposal","kind":"reminder","task":{"title":"Call lecturer","reminder":"2026-10-01T15:00:00+07:00","priority":"medium","minutes":10},"questions":[]}''',
      );
      final planning = parser.capture(
        '''{"type":"capture_proposal","kind":"planning_request","planningDate":"2026-10-01","questions":[]}''',
      );

      expect(task.kind, AiCaptureKind.standaloneTask);
      expect(task.task!.deadline, '2026-10-01');
      expect(project.project!.tasks, hasLength(1));
      expect(routine.routine!.window, contains('Wednesday'));
      expect(reminder.task!.reminder, isNotNull);
      expect(planning.planningDate, '2026-10-01');
    },
  );

  test(
    'capture classification rejects missing reminder time and invalid dates',
    () {
      expect(
        () => parser.capture(
          '''{"type":"capture_proposal","kind":"reminder","task":{"title":"Call","priority":"medium","minutes":10},"questions":[]}''',
        ),
        throwsFormatException,
      );
      expect(
        () => parser.capture(
          '''{"type":"capture_proposal","kind":"planning_request","planningDate":"tomorrow","questions":[]}''',
        ),
        throwsFormatException,
      );
    },
  );

  test('approved proposal creates real records once', () async {
    final repo = MemoryWorkspace();
    final proposal = AiProjectProposal(
      title: 'Portfolio',
      area: 'Study',
      tasks: [
        AiTaskProposal(
          title: 'Collect projects',
          checklist: ['Choose three projects', 'Prepare screenshots'],
        ),
        AiTaskProposal(title: 'Build pages', minutes: 60),
      ],
    );
    await repo.applyProjectProposal(proposal, operationId: 'operation');
    await repo.applyProjectProposal(proposal, operationId: 'operation');
    expect(repo.projects, hasLength(1));
    expect(repo.tasks, hasLength(2));
    expect(repo.tasks.first.checklist, hasLength(2));
  });

  test(
    'new Life Area requires approval and reuses names case-insensitively',
    () async {
      final repo = MemoryWorkspace();
      final rejected = AiProjectProposal(
        title: 'Trip preparation',
        area: 'Travel',
        tasks: [AiTaskProposal(title: 'Pack bag')],
      );
      await expectLater(
        repo.applyProjectProposal(rejected, operationId: 'not-approved'),
        throwsArgumentError,
      );
      expect(repo.areas, isNot(contains('Travel')));
      expect(repo.projects, isEmpty);

      rejected.createArea = true;
      await repo.applyProjectProposal(rejected, operationId: 'approved');
      final reused = AiProjectProposal(
        title: 'Next trip',
        area: 'travel',
        tasks: [AiTaskProposal(title: 'Check route')],
      );
      await repo.applyProjectProposal(reused, operationId: 'reused');
      expect(
        repo.areas.where((area) => area.toLowerCase() == 'travel'),
        hasLength(1),
      );
      expect(repo.projects.last.area, 'Travel');
    },
  );

  test(
    'approved task, reminder, and routine proposals use domain records once',
    () async {
      final repo = MemoryWorkspace();
      final future = DateTime.now().toUtc().add(const Duration(days: 2));
      final task = AiCaptureProposal(
        kind: AiCaptureKind.standaloneTask,
        task: AiTaskProposal(title: 'Submit assignment', area: 'Study'),
      );
      final reminder = AiCaptureProposal(
        kind: AiCaptureKind.reminder,
        task: AiTaskProposal(
          title: 'Call lecturer',
          area: 'Study',
          reminder: future.toIso8601String(),
        ),
      );
      final routine = AiCaptureProposal(
        kind: AiCaptureKind.routine,
        routine: AiRoutineProposal(
          title: 'Exercise',
          area: 'Health',
          window: 'Monday, Wednesday and Friday',
          minimum: 'Walk 10 minutes',
        ),
      );

      await repo.applyCaptureProposal(task, operationId: 'task');
      await repo.applyCaptureProposal(task, operationId: 'task');
      await repo.applyCaptureProposal(reminder, operationId: 'reminder');
      await repo.applyCaptureProposal(routine, operationId: 'routine');
      expect(repo.tasks, hasLength(2));
      expect(repo.reminders, hasLength(1));
      expect(repo.routines.single.window, contains('Wednesday'));
    },
  );
}
