import 'dart:convert';

enum AiCaptureKind {
  standaloneTask,
  project,
  routine,
  reminder,
  planningRequest,
}

enum AiProjectChange { auto, add, change, move, remove, unchanged }

class AiRoutineProposal {
  AiRoutineProposal({
    required this.title,
    this.area,
    this.window = '',
    this.minimum = '',
    this.normal = '',
    this.strong = '',
  });
  String title;
  String? area;
  String window, minimum, normal, strong;
}

class AiCaptureProposal {
  AiCaptureProposal({
    required this.kind,
    this.task,
    this.project,
    this.routine,
    this.planningDate,
    this.questions = const [],
    this.createArea = false,
  });
  final AiCaptureKind kind;
  final AiTaskProposal? task;
  final AiProjectProposal? project;
  final AiRoutineProposal? routine;
  final String? planningDate;
  final List<String> questions;
  bool createArea;
}

class AiTaskProposal {
  AiTaskProposal({
    required this.title,
    this.taskId,
    this.area,
    this.priority = 'medium',
    this.minutes = 25,
    this.deadline,
    this.reminder,
    this.checklist = const [],
    this.included = true,
    this.change = AiProjectChange.auto,
  });
  String title;
  String? taskId;
  String? area;
  String priority;
  int minutes;
  String? deadline;
  String? reminder;
  List<String> checklist;
  bool included;
  AiProjectChange change;
}

class AiProjectProposal {
  AiProjectProposal({
    required this.title,
    required this.tasks,
    this.area,
    this.description = '',
    this.questions = const [],
    this.createArea = false,
  });
  String title;
  String? area;
  String description;
  final List<AiTaskProposal> tasks;
  final List<String> questions;
  bool createArea;
}

class AiScheduleProposal {
  AiScheduleProposal({
    required this.events,
    this.questions = const [],
    Map<String, String>? baseFingerprints,
  }) : baseFingerprints = baseFingerprints ?? <String, String>{};
  final List<AiScheduleEvent> events;
  final List<String> questions;
  final Map<String, String> baseFingerprints;
}

class StaleScheduleProposalException implements Exception {
  const StaleScheduleProposalException();

  @override
  String toString() => 'The schedule changed after this proposal was created.';
}

class AiScheduleEvent {
  AiScheduleEvent({
    required this.title,
    this.planId,
    this.taskId,
    this.area,
    this.date,
    this.start,
    this.end,
    this.notes = '',
    this.included = true,
    this.kind = 'task',
    this.operation = 'add',
    this.locked = false,
    this.weekday,
    this.recurringScheduleId,
  });
  String title;
  String? planId, taskId, area, date, start, end;
  String notes;
  bool included;
  String kind, operation;
  bool locked;
  int? weekday;
  String? recurringScheduleId;
}

class AiProposalParser {
  const AiProposalParser();

  AiCaptureProposal capture(String raw) {
    final value = _json(raw);
    if (value['type'] != 'capture_proposal') {
      throw const FormatException('AI response is not a capture proposal.');
    }
    final kind = switch (value['kind']) {
      'standalone_task' => AiCaptureKind.standaloneTask,
      'project' => AiCaptureKind.project,
      'routine' => AiCaptureKind.routine,
      'reminder' => AiCaptureKind.reminder,
      'planning_request' => AiCaptureKind.planningRequest,
      _ => throw const FormatException('Invalid capture type.'),
    };
    final questions = _strings(value['questions']);
    switch (kind) {
      case AiCaptureKind.project:
        return AiCaptureProposal(
          kind: kind,
          project: _project(_object(value['project']), questions),
          questions: questions,
        );
      case AiCaptureKind.standaloneTask:
      case AiCaptureKind.reminder:
        final task = _task(_object(value['task']));
        if (kind == AiCaptureKind.reminder && task.reminder == null) {
          throw const FormatException('Reminder proposal has no time.');
        }
        return AiCaptureProposal(kind: kind, task: task, questions: questions);
      case AiCaptureKind.routine:
        final routine = _object(value['routine']);
        return AiCaptureProposal(
          kind: kind,
          routine: AiRoutineProposal(
            title: _requiredString(routine['title'], 'routine.title'),
            area: routine['area']?.toString(),
            window: _requiredString(routine['window'], 'routine.window'),
            minimum: _requiredString(routine['minimum'], 'routine.minimum'),
            normal: routine['normal']?.toString() ?? '',
            strong: routine['strong']?.toString() ?? '',
          ),
          questions: questions,
        );
      case AiCaptureKind.planningRequest:
        final date = _requiredString(value['planningDate'], 'planningDate');
        if (!_validDate(date)) {
          throw const FormatException('Invalid planning date.');
        }
        return AiCaptureProposal(
          kind: kind,
          planningDate: date,
          questions: questions,
        );
    }
  }

  AiProjectProposal project(String raw) {
    final value = _json(raw);
    if (value['type'] != 'project_proposal') {
      throw const FormatException('AI response is not a project proposal.');
    }
    return _project(_object(value['project']), _strings(value['questions']));
  }

  AiProjectProposal _project(
    Map<String, dynamic> project,
    List<String> questions,
  ) {
    final title = _requiredString(project['title'], 'project.title');
    final rawTasks = project['tasks'];
    if (rawTasks is! List || rawTasks.isEmpty) {
      throw const FormatException('AI project proposal has no tasks.');
    }
    final tasks = rawTasks.map((item) => _task(_object(item))).toList();
    return AiProjectProposal(
      title: title,
      area: project['area']?.toString(),
      description: project['description']?.toString() ?? '',
      tasks: tasks,
      questions: questions,
    );
  }

  AiTaskProposal _task(Map<String, dynamic> task) {
    final priority = task['priority']?.toString() ?? 'medium';
    if (!{'low', 'medium', 'high'}.contains(priority)) {
      throw const FormatException('Invalid task priority.');
    }
    final minutes = task['minutes'] is int ? task['minutes'] as int : 25;
    if (minutes < 1 || minutes > 1440) {
      throw const FormatException('Invalid task duration.');
    }
    final deadline = task['deadline']?.toString();
    if (deadline != null && !_validDate(deadline)) {
      throw const FormatException('Invalid task deadline.');
    }
    final reminder = task['reminder']?.toString();
    if (reminder != null && DateTime.tryParse(reminder) == null) {
      throw const FormatException('Invalid reminder time.');
    }
    return AiTaskProposal(
      title: _requiredString(task['title'], 'task.title'),
      taskId: task['taskId']?.toString(),
      area: task['area']?.toString(),
      priority: priority,
      minutes: minutes,
      deadline: deadline,
      reminder: reminder,
      checklist: _strings(task['checklist']),
      change: switch (task['operation']) {
        'add' => AiProjectChange.add,
        'change' => AiProjectChange.change,
        'move' => AiProjectChange.move,
        'remove' => AiProjectChange.remove,
        'unchanged' => AiProjectChange.unchanged,
        null => AiProjectChange.auto,
        _ => throw const FormatException('Invalid project change.'),
      },
    );
  }

  bool _validDate(String value) {
    final date = DateTime.tryParse(value);
    return date != null &&
        value ==
            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  AiScheduleProposal schedule(String raw) {
    final value = _json(raw);
    if (value['type'] != 'schedule_proposal') {
      throw const FormatException('AI response is not a schedule proposal.');
    }
    final rawEvents = value['events'];
    if (rawEvents is! List) {
      throw const FormatException('AI schedule has no events.');
    }
    return AiScheduleProposal(
      events: rawEvents.map((item) {
        final event = _object(item);
        return AiScheduleEvent(
          title: _requiredString(event['title'], 'event.title'),
          planId: event['planId']?.toString(),
          taskId: event['taskId']?.toString(),
          area: event['area']?.toString(),
          date: event['date']?.toString(),
          start: event['start']?.toString(),
          end: event['end']?.toString(),
          notes: event['notes']?.toString() ?? '',
          kind:
              event['kind']?.toString() ??
              (event['taskId'] == null ? 'personal' : 'task'),
          operation:
              event['operation']?.toString() ??
              (event['planId'] == null ? 'add' : 'change'),
          locked: event['locked'] == true || event['fixed'] == true,
          weekday:
              _weekday(event['weekday']) ??
              (event['date'] == null
                  ? null
                  : DateTime.tryParse(event['date'].toString())?.weekday),
          recurringScheduleId: event['recurringScheduleId']?.toString(),
        );
      }).toList(),
      questions: _strings(value['questions']),
    );
  }

  Map<String, dynamic> _json(String raw) {
    final trimmed = raw.trim();
    final firstObject = trimmed.indexOf('{');
    final lastObject = trimmed.lastIndexOf('}');
    if (firstObject < 0 || lastObject < firstObject) {
      throw const FormatException('AI response did not contain JSON.');
    }
    final decoded = jsonDecode(trimmed.substring(firstObject, lastObject + 1));
    return _object(decoded);
  }

  Map<String, dynamic> _object(Object? value) {
    if (value is! Map) {
      throw const FormatException('AI response must be an object.');
    }
    return Map<String, dynamic>.from(value);
  }

  String _requiredString(Object? value, String field) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw FormatException('Missing $field.');
    return text;
  }

  List<String> _strings(Object? value) =>
      value is List ? value.map((v) => v.toString()).toList() : const [];

  int? _weekday(Object? value) {
    if (value is int && value >= 1 && value <= 7) return value;
    final text = value?.toString().trim().toLowerCase();
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final index = names.indexWhere(
      (day) => day == text || day.substring(0, 3) == text,
    );
    return index < 0 ? int.tryParse(text ?? '') : index + 1;
  }
}
