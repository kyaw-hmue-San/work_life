import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ai/capture_assistant.dart';
import '../ai/aimlapi_client.dart';
import '../ai/day_context_builder.dart';
import '../ai/ai_proposal_screen.dart';
import '../ai/ai_capture_proposal_screen.dart';
import '../ai/ai_proposals.dart';
import '../ai/ai_schedule_screen.dart';
import '../captures/capture.dart';
import '../captures/inbox_screen.dart';
import '../notifications/reminder_notifications.dart';
import '../notifications/notification_driver.dart';
import '../sync/workspace_sync_coordinator.dart';
import 'editors.dart';
import 'focus_screen.dart';
import 'day_architect_settings.dart';
import 'calendar_progress.dart';
import 'records.dart';
import 'reminder_editor.dart';
import 'settings_screen.dart';
import 'onboarding_screen.dart';
import 'task_detail.dart';
import 'workspace_model.dart';
import 'workspace_repository.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.repository,
    this.accountBuilder,
    this.accountLabel,
    this.accountNotice,
    this.notifications,
    this.notificationScope = 'guest',
    this.sync,
  });
  final WorkspaceRepository repository;
  final WidgetBuilder? accountBuilder;
  final String? accountLabel, accountNotice;
  final ReminderNotifications? notifications;
  final String notificationScope;
  final WorkspaceSyncCoordinator? sync;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver {
  late final WorkspaceModel model;
  int tab = 0;
  DateTime selectedDay = DateTime.now();
  late final Timer dayTicker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model = WorkspaceModel(
      widget.repository,
      notifications: widget.notifications,
      notificationScope: widget.notificationScope,
      afterChange: widget.sync?.sync,
    );
    unawaited(_loadAndSync());
    dayTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
      unawaited(model.refreshNotifications());
    });
  }

  Future<void> _loadAndSync() async {
    await model.load();
    await _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      unawaited(model.refreshNotifications());
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    final coordinator = widget.sync;
    if (coordinator == null) return;
    await coordinator.sync();
    if (!mounted) return;
    await model.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    dayTicker.cancel();
    model.dispose();
    super.dispose();
  }

  void push(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  void edit(
    String kind, {
    Task? task,
    Project? project,
    PlanBlock? plan,
    Routine? routine,
    Capture? capture,
    ProjectEntry? entry,
    ProjectEntry? sourceEntry,
    String? projectId,
    bool routineTemplate = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => RecordEditor(
          model: model,
          kind: kind,
          task: task,
          project: project,
          plan: plan,
          routine: routine,
          capture: capture,
          entry: entry,
          sourceEntry: sourceEntry,
          projectId: projectId,
          day: selectedDay,
          routineTemplate: routineTemplate,
        ),
      ),
    );
  }

  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(subtitle),
      ],
    ),
  );
  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget empty(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFFECEFE7),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(text),
  );
  Widget taskTile(Task task) => Card(
    elevation: 0,
    color: Colors.white,
    child: ListTile(
      leading: Icon(
        task.status == TaskStatus.completed
            ? Icons.check_circle_outline
            : task.status == TaskStatus.cancelled
            ? Icons.cancel_outlined
            : Icons.radio_button_unchecked,
      ),
      title: Text(task.title),
      subtitle: Text(
        '${task.area} · ${task.priority.name} priority · ${task.minutes} min${task.deadline == null ? '' : ' · Due ${task.deadline}'}${task.active ? '' : ' · ${task.status.name}'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => push(TaskDetail(model: model, taskId: task.id)),
    ),
  );
  Widget content(List<Widget> children) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: children,
      ),
    ),
  );

  Widget today() {
    final now = DateTime.now();
    final todays = model.tasksForDay(now);
    final plans = model.data.plans.where((p) => p.occursOn(now)).toList();
    final recurring = _recurringOccurrences(now);
    final scheduledMinutes =
        plans.fold<int>(0, (sum, p) => sum + p.minutes) +
        recurring.fold<int>(0, (sum, event) {
          int minute(String text) {
            final parts = text.split(':');
            return int.parse(parts[0]) * 60 + int.parse(parts[1]);
          }

          return sum +
              minute(event['end'] as String) -
              minute(event['start'] as String);
        });
    final unplanned = model.data.tasks
        .where((t) => t.active && !todays.any((v) => v.id == t.id))
        .take(3)
        .toList();
    return content([
      heading(
        'Make room for your day.',
        'A manageable next step, with space for the rest of life.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => edit('task'),
            icon: const Icon(Icons.add),
            label: const Text('New task'),
          ),
          OutlinedButton.icon(
            onPressed: () => edit('plan'),
            icon: const Icon(Icons.spa_outlined),
            label: const Text('Protect personal time'),
          ),
          OutlinedButton.icon(
            onPressed: model.busy ? null : () => _planWithAi(now),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Plan My Day'),
          ),
          if (todays.isNotEmpty)
            OutlinedButton.icon(
              onPressed: model.busy ? null : () => _reorganizeWithAi(now),
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('Reschedule with AI'),
            ),
        ],
      ),
      if (model.activeSession != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.timelapse),
            title: const Text('Your focus session'),
            subtitle: Text(
              model.task(model.activeSession!.taskId)?.title ?? '',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(FocusScreen(model: model)),
          ),
        ),
      section('Pending reminders'),
      if (model.notifications case final notifications?) ...[
        Text(notifications.message),
        if (notifications.permission == NotificationPermission.notDetermined)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: notifications.working || model.busy
                  ? null
                  : () => model.refreshNotifications(requestPermission: true),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Enable notifications'),
            ),
          )
        else if (notifications.permission == NotificationPermission.blocked)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: notifications.working
                  ? null
                  : notifications.openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open notification settings'),
            ),
          )
        else if (notifications.permission?.canSchedule == true &&
            notifications.message.startsWith('Couldn’t'))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: notifications.working || model.busy
                  ? null
                  : model.refreshNotifications,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry notifications'),
            ),
          ),
      ] else
        const Text(
          'In-app reminders · device notifications unavailable in this session.',
        ),
      if (model.pendingReminders.isEmpty)
        const Text('No reminders set. Add one from task details.'),
      for (final reminder in model.pendingReminders)
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(model.task(reminder.taskId)!.title),
            subtitle: Text(
              '${reminder.scheduledAt.isAfter(now) ? 'Upcoming' : 'Ready to revisit'} · ${reminderTimeLabel(context, reminder.scheduledAt)}\n${reminderDeliveryLabel(reminder.deliveryStatus)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                push(TaskDetail(model: model, taskId: reminder.taskId)),
          ),
        ),
      section('Due or planned today'),
      if (todays.isEmpty)
        empty('Nothing due or planned. Choose a next step when you’re ready.'),
      ...todays.map(taskTile),
      if (scheduledMinutes >= 480)
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const ListTile(
            leading: Icon(Icons.balance_outlined),
            title: Text('This is a heavily scheduled day'),
            subtitle: Text(
              'Protect a break, movement, and some unscheduled time. AI planning will avoid filling every gap.',
            ),
          ),
        ),
      section('Your time'),
      if (plans.isEmpty && recurring.isEmpty)
        empty(
          'Leave breathing room. Add work, a meal, time together, or a break in Planner.',
        ),
      ...plans.map(planTile),
      if (recurring.isNotEmpty) ...[
        section('Recurring commitments'),
        ...recurring.map(recurringTile),
      ],
      if (model.data.routines.isNotEmpty) ...[
        section('Everyday care'),
        ...model.data.routines.map(routineTile),
      ],
      section('Other next steps'),
      ...unplanned.map(taskTile),
      if (unplanned.isEmpty)
        const Text('New tasks can start here or come from a capture in Inbox.'),
      TextButton(onPressed: allTasks, child: const Text('View all tasks')),
    ]);
  }

  void allTasks() => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('All tasks')),
        body: content([
          if (model.data.tasks.isEmpty)
            empty(
              'No tasks yet. Save a thought in Inbox or add a task from Today.',
            ),
          section('Open'),
          ...model.data.tasks.where((t) => t.active).map(taskTile),
          section('Completed or cancelled'),
          ...model.data.tasks.where((t) => !t.active).map(taskTile),
        ]),
      ),
    ),
  );

  void openCapture(Capture capture) => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final linked = model.data.tasks.where((t) => t.captureId == capture.id);
        return Scaffold(
          appBar: AppBar(title: const Text('Your capture')),
          body: content([
            heading(
              'Keep the original.',
              'A thought can stay a note, or become your next action.',
            ),
            SelectableText(
              capture.originalText,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (const CaptureAssistant().suggest(capture.originalText)
                case final suggestion?) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text('Quick suggestion · ${suggestion.kind}'),
                  subtitle: Text(suggestion.prompt),
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: () => _organizeWithAi(capture),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Understand with AI'),
            ),
            const SizedBox(height: 24),
            if (linked.isEmpty)
              FilledButton.icon(
                onPressed: () => edit('task', capture: capture),
                icon: const Icon(Icons.add_task),
                label: const Text('Turn into a task'),
              )
            else ...[
              section('Linked task'),
              taskTile(linked.first),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => edit('entry', capture: capture),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add to a project as a note'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your original words are kept unchanged. Deadlines are only set when you choose a date.',
            ),
          ]),
        );
      },
    ),
  );

  Future<void> _organizeWithAi(Capture capture) async {
    final client = AimlApiClient();
    if (!client.configured) {
      client.dispose();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI assistance is unavailable'),
          content: const Text(
            'AI assistance is not enabled in this build. Your original capture and offline suggestions remain available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Building an editable proposal…'),
        content: LinearProgressIndicator(),
      ),
    );
    try {
      final proposal = await client.classifyCapture(
        capture.originalText,
        existingAreas: model.data.areas,
        planningContext: _capturePlanningContext(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (proposal.kind == AiCaptureKind.project) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => AiProjectProposalScreen(
              model: model,
              proposal: proposal.project!,
              captureId: capture.id,
              onClarify: (current, answers) => client.refineCaptureProject(
                originalInput: capture.originalText,
                proposal: current,
                answers: answers,
                existingAreas: model.data.areas,
                planningContext: _capturePlanningContext(),
              ),
            ),
          ),
        );
      } else if (proposal.kind == AiCaptureKind.planningRequest) {
        final day = DateTime.parse(proposal.planningDate!);
        final schedule = await _requestDayPlan(day);
        if (!mounted) return;
        await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => AiScheduleProposalScreen(
              model: model,
              proposal: schedule,
              title: 'Review ${proposal.planningDate} plan',
            ),
          ),
        );
      } else {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => AiCaptureProposalScreen(
              model: model,
              proposal: proposal,
              captureId: capture.id,
              onClarify: (current, answers) => client.refineCapture(
                originalInput: capture.originalText,
                proposal: current,
                answers: answers,
                existingAreas: model.data.areas,
                planningContext: _capturePlanningContext(),
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${error is AiServiceException ? error.message : 'AI returned a proposal this app could not read.'} Your capture is safe.',
            ),
          ),
        );
      }
    } finally {
      client.dispose();
    }
  }

  Map<String, Object?> _capturePlanningContext() {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 14));
    final preferences = model.data.planningPreferences;
    return {
      'existingCalendar': model.data.plans
          .where(
            (block) => block.end.isAfter(now) && block.start.isBefore(horizon),
          )
          .map(
            (block) => {
              'title': block.title,
              'start': block.start.toIso8601String(),
              'minutes': block.minutes,
              'fixed': block.fixed,
            },
          )
          .toList(),
      'weeklyCommitments': model.data.recurringSchedules
          .map(
            (item) => {
              'title': item.title,
              'weekday': item.weekday,
              'start': item.startTime,
              'end': item.endTime,
              'location': item.location,
              'fixed': item.fixed,
            },
          )
          .toList(),
      'preferences': {
        'wakeTime': preferences.wakeTime,
        'bedTime': preferences.bedTime,
        'transitionMinutes': preferences.transitionMinutes,
        'avoidFocusAfter': preferences.avoidFocusAfter,
        'maxFocusMinutes': preferences.maxFocusMinutes,
      },
    };
  }

  Future<AiProjectProposal> _requestProjectImprovement(
    Project project,
    List<Task> tasks,
  ) async {
    final client = AimlApiClient();
    try {
      return await client.improveProject(
        jsonEncode({
          'project': {
            'id': project.id,
            'title': project.title,
            'description': project.description,
            'area': project.area,
          },
          'tasks': tasks
              .map(
                (task) => {
                  'taskId': task.id,
                  'title': task.title,
                  'area': task.area,
                  'priority': task.priority.name,
                  'minutes': task.minutes,
                  'deadline': task.deadline,
                  'status': task.status.name,
                  'checklist': task.checklist.map((item) => item.text).toList(),
                },
              )
              .toList(),
          'request': 'Make this project realistic, preserve useful existing tasks, clarify titles, and suggest only genuinely missing next actions.',
        }),
      );
    } finally {
      client.dispose();
    }
  }

  Future<void> _improveProject(Project project, List<Task> tasks) async {
    final configured = AimlApiClient().configured;
    if (!configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI assistance is not available in this build.'),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Checking this project…'),
        content: LinearProgressIndicator(),
      ),
    );
    try {
      final proposal = await _requestProjectImprovement(project, tasks);
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AiProjectProposalScreen(
            model: model,
            proposal: proposal,
            targetProjectId: project.id,
            onRegenerate: () => _requestProjectImprovement(project, tasks),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${error is AiServiceException ? error.message : 'Couldn’t create project improvements.'} Your project was not changed.',
          ),
        ),
      );
    }
  }

  Future<AiScheduleProposal> _requestDayPlan(
    DateTime day, {
    String request = '',
  }) async {
    final client = AimlApiClient();
    try {
      final dayContext = const DayContextBuilder().build(
        model.data,
        day,
        request: request,
      );
      final result = await client.planDay(jsonEncode(dayContext));
      final dayKeyValue = dayKey(day);
      if (result.events.isEmpty) {
        throw const FormatException('AI returned an empty day plan.');
      }
      if (result.events.any(
        (event) => event.date != null && event.date != dayKeyValue,
      )) {
        throw const FormatException(
          'AI returned a block outside the selected day.',
        );
      }
      result.baseFingerprints[dayKeyValue] = const DayContextBuilder()
          .fingerprint(model.data, day);
      final commitments = (dayContext['fixedCommitments'] as List)
          .cast<Map<String, Object?>>();
      for (final recurring in commitments) {
        final scheduleId = recurring['scheduleId'] as String;
        final existingEvent = result.events
            .where(
              (event) =>
                  event.recurringScheduleId == scheduleId ||
                  event.title.trim().toLowerCase() ==
                      (recurring['title'] as String).trim().toLowerCase(),
            )
            .toList();
        final event = existingEvent.isEmpty
            ? AiScheduleEvent(title: recurring['title'] as String)
            : existingEvent.first;
        result.events.removeWhere(
          (candidate) =>
              existingEvent.length > 1 &&
              candidate != event &&
              candidate.title.trim().toLowerCase() ==
                  (recurring['title'] as String).trim().toLowerCase(),
        );
        event.recurringScheduleId = scheduleId;
        event.title = recurring['title'] as String;
        event.taskId = null;
        event.area = 'Study';
        event.date = dayKeyValue;
        event.start = recurring['start'] as String;
        event.end = recurring['end'] as String;
        event.kind = 'existing_planner';
        event.operation = 'unchanged';
        event.locked = recurring['fixed'] as bool? ?? true;
        if (existingEvent.isEmpty) result.events.insert(0, event);
      }
      final existing = model.data.plans.where((p) => p.occursOn(day));
      for (final event in result.events) {
        PlanBlock? original;
        for (final block in existing) {
          if (block.id == event.planId) {
            original = block;
            break;
          }
        }
        if (original?.fixed == true) {
          event.locked = true;
          event.operation = 'unchanged';
          event.title = original!.title;
          event.start =
              '${original.start.hour.toString().padLeft(2, '0')}:${original.start.minute.toString().padLeft(2, '0')}';
          event.end =
              '${original.end.hour.toString().padLeft(2, '0')}:${original.end.minute.toString().padLeft(2, '0')}';
          event.taskId = original.taskId;
          event.area = original.area;
        }
      }
      for (final block in existing) {
        if (result.events.any((e) => e.planId == block.id)) continue;
        result.events.add(
          AiScheduleEvent(
            title: block.title,
            planId: block.id,
            taskId: block.taskId,
            area: block.area,
            date: dayKey(block.start),
            start:
                '${block.start.hour.toString().padLeft(2, '0')}:${block.start.minute.toString().padLeft(2, '0')}',
            end:
                '${block.end.hour.toString().padLeft(2, '0')}:${block.end.minute.toString().padLeft(2, '0')}',
            kind: 'existing_planner',
            operation: block.fixed ? 'unchanged' : 'remove',
            locked: block.fixed,
            notes: block.fixed
                ? 'Kept as a locked commitment.'
                : 'Not included in the new proposal.',
          ),
        );
      }
      return result;
    } finally {
      client.dispose();
    }
  }

  Future<void> _planWithAi(DateTime day) async {
    if (!AimlApiClient().configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI planning is not available in this build.'),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Building a balanced day…'),
        content: LinearProgressIndicator(),
      ),
    );
    try {
      final proposal = await _requestDayPlan(day);
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AiScheduleProposalScreen(
            model: model,
            proposal: proposal,
            title: 'Plan My Day',
            onRegenerate: () => _requestDayPlan(day),
            onAdjust: (adjustment) => _requestDayPlan(day, request: adjustment),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_planningFailure(error, 'Couldn’t create a day plan.')} Your current Planner was not changed.',
          ),
        ),
      );
    }
  }

  Future<AiScheduleProposal> _requestWeekPlan(
    DateTime selected, {
    String request = '',
  }) async {
    final monday = calendarDay(selected, -(selected.weekday - 1));
    const builder = WeekContextBuilder();
    final contexts = builder.build(model.data, monday);
    final client = AimlApiClient();
    try {
      final result = await client.planWeek(
        jsonEncode(
          builder.buildPlanningContext(model.data, monday, request: request),
        ),
      );
      final weekEnd = calendarDay(monday, 7);
      if (result.events.isEmpty) {
        throw const FormatException('AI returned an empty weekly plan.');
      }
      for (final event in result.events) {
        if (event.date case final date?) {
          final parsed = DateTime.tryParse(date);
          if (parsed == null ||
              parsed.isBefore(monday) ||
              !parsed.isBefore(weekEnd)) {
            throw const FormatException(
              'AI returned a block outside the selected week.',
            );
          }
        }
      }
      result.baseFingerprints.addAll(builder.fingerprints(model.data, monday));

      for (final dayContext in contexts) {
        final date = dayContext['date'] as String;
        final commitments = (dayContext['fixedCommitments'] as List)
            .cast<Map<String, Object?>>();
        for (final recurring in commitments) {
          final scheduleId = recurring['scheduleId'] as String;
          final matches = result.events
              .where(
                (event) =>
                    event.recurringScheduleId == scheduleId ||
                    (event.date == date &&
                        event.title.trim().toLowerCase() ==
                            (recurring['title'] as String)
                                .trim()
                                .toLowerCase()),
              )
              .toList();
          final event = matches.isEmpty
              ? AiScheduleEvent(title: recurring['title'] as String)
              : matches.first;
          for (final duplicate in matches.skip(1)) {
            result.events.remove(duplicate);
          }
          event
            ..recurringScheduleId = scheduleId
            ..title = recurring['title'] as String
            ..taskId = null
            ..area = 'Study'
            ..date = date
            ..start = recurring['start'] as String
            ..end = recurring['end'] as String
            ..kind = 'existing_planner'
            ..operation = 'unchanged'
            ..locked = recurring['fixed'] as bool? ?? true;
          if (matches.isEmpty) result.events.add(event);
        }
      }

      final endExclusive = calendarDay(monday, 7);
      final existing = model.data.plans
          .where(
            (plan) =>
                !plan.start.isBefore(monday) &&
                plan.start.isBefore(endExclusive),
          )
          .toList();
      for (final event in result.events) {
        PlanBlock? original;
        for (final block in existing) {
          if (block.id == event.planId) {
            original = block;
            break;
          }
        }
        if (original?.fixed == true) {
          event
            ..locked = true
            ..operation = 'unchanged'
            ..title = original!.title
            ..date = dayKey(original.start)
            ..start = _planClock(original.start)
            ..end = _planClock(original.end)
            ..taskId = original.taskId
            ..area = original.area;
        }
      }
      for (final block in existing) {
        if (result.events.any((event) => event.planId == block.id)) continue;
        result.events.add(
          AiScheduleEvent(
            title: block.title,
            planId: block.id,
            taskId: block.taskId,
            area: block.area,
            date: dayKey(block.start),
            start: _planClock(block.start),
            end: _planClock(block.end),
            kind: 'existing_planner',
            operation: block.fixed ? 'unchanged' : 'remove',
            locked: block.fixed,
            notes: block.fixed
                ? 'Kept as a locked commitment.'
                : 'Not included in the new weekly proposal.',
          ),
        );
      }
      result.events.sort((a, b) {
        final date = (a.date ?? '').compareTo(b.date ?? '');
        return date != 0 ? date : (a.start ?? '').compareTo(b.start ?? '');
      });
      return result;
    } finally {
      client.dispose();
    }
  }

  String _planClock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _planningFailure(Object error, String fallback) {
    if (error is AiServiceException) return error.message;
    if (error is FormatException) {
      return 'AI returned an incomplete or inconsistent schedule. Try again with exact dates and availability.';
    }
    return fallback;
  }

  Future<void> _planWeekWithAi(DateTime selected) async {
    final availability = AimlApiClient();
    final configured = availability.configured;
    availability.dispose();
    if (!configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI weekly planning is not available in this build.'),
        ),
      );
      return;
    }
    final monday = calendarDay(selected, -(selected.weekday - 1));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Balancing your week…'),
        content: LinearProgressIndicator(),
      ),
    );
    try {
      final proposal = await _requestWeekPlan(monday);
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AiScheduleProposalScreen(
            model: model,
            proposal: proposal,
            title: 'Plan My Week',
            weekStart: monday,
            onRegenerate: () => _requestWeekPlan(monday),
            onAdjust: (adjustment) =>
                _requestWeekPlan(monday, request: adjustment),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_planningFailure(error, 'Couldn’t create a weekly plan.')} Your current Planner was not changed.',
          ),
        ),
      );
    }
  }

  Future<AiScheduleProposal> _requestRecoveryPlan(DateTime from) async {
    final end = DateTime(from.year, from.month, from.day + 7);
    final client = AimlApiClient();
    try {
      final result = await client.planDay(
        jsonEncode({
          'dateRange': {'from': dayKey(from), 'through': dayKey(end)},
          'unfinishedTasks': model.data.tasks
              .where((task) => task.active)
              .map(
                (task) => {
                  'taskId': task.id,
                  'title': task.title,
                  'area': task.area,
                  'priority': task.priority.name,
                  'minutes': task.minutes,
                  'deadline': task.deadline,
                },
              )
              .toList(),
          'existingPlanner': model.data.plans
              .where(
                (plan) =>
                    !plan.start.isBefore(DateUtils.dateOnly(from)) &&
                    plan.start.isBefore(calendarDay(end, 1)),
              )
              .map(
                (plan) => {
                  'planId': plan.id,
                  'taskId': plan.taskId,
                  'title': plan.title,
                  'start': plan.start.toIso8601String(),
                  'minutes': plan.minutes,
                  'fixed': plan.fixed,
                },
              )
              .toList(),
          'instructions': 'Redistribute unfinished work across the range. Respect deadlines and fixed blocks. Do not push everything to tomorrow. Leave recovery time and avoid overloaded days.',
        }),
      );
      const builder = DayContextBuilder();
      for (var index = 0; index <= 7; index++) {
        final day = DateTime(from.year, from.month, from.day + index);
        result.baseFingerprints[dayKey(day)] = builder.fingerprint(
          model.data,
          day,
        );
      }
      return result;
    } finally {
      client.dispose();
    }
  }

  Future<void> _reorganizeWithAi(DateTime from) async {
    if (!AimlApiClient().configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI rescheduling is not available in this build.'),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        title: Text('Reorganizing unfinished work…'),
        content: LinearProgressIndicator(),
      ),
    );
    try {
      final proposal = await _requestRecoveryPlan(from);
      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AiScheduleProposalScreen(
            model: model,
            proposal: proposal,
            title: 'Review rescheduled work',
            onRegenerate: () => _requestRecoveryPlan(from),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${error is AiServiceException ? error.message : 'Couldn’t reorganize this work.'} Your current plan was not changed.',
          ),
        ),
      );
    }
  }

  Widget projects() => content([
    heading(
      'Projects',
      'Keep a purpose, its notes, and the next steps together.',
    ),
    FilledButton.icon(
      onPressed: () => edit('project'),
      icon: const Icon(Icons.add),
      label: const Text('New project'),
    ),
    const SizedBox(height: 20),
    if (model.data.projects.isEmpty)
      empty(
        'Start with something that matters: a work project, a course, or a holiday together.',
      ),
    for (final p in model.data.projects) _projectCard(p),
  ]);

  Widget _projectCard(Project project) {
    final tasks = model.data.tasks
        .where((task) => task.projectId == project.id)
        .toList();
    final completed = tasks
        .where((task) => task.status == TaskStatus.completed)
        .length;
    final progress = tasks.isEmpty ? 0.0 : completed / tasks.length;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.title),
            subtitle: Text(
              '${project.area} · $completed of ${tasks.length} tasks complete',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => projectDetail(project.id),
          ),
          Semantics(
            label:
                '${project.title}, ${(progress * 100).round()} percent complete',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: LinearProgressIndicator(value: progress),
            ),
          ),
        ],
      ),
    );
  }

  void projectDetail(String id) => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final p = model.data.projects.firstWhere((p) => p.id == id);
        final tasks = model.data.tasks.where((t) => t.projectId == id).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(p.title),
            actions: [
              IconButton(
                onPressed: () => edit('project', project: p),
                tooltip: 'Edit project',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: content([
            heading(
              p.area,
              p.description.isEmpty
                  ? 'Keep related next steps in one place.'
                  : p.description,
            ),
            FilledButton.icon(
              onPressed: () => edit('task', projectId: p.id),
              icon: const Icon(Icons.add),
              label: const Text('Add project task'),
            ),
            OutlinedButton.icon(
              onPressed: () => edit('entry', projectId: p.id),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add note, bug, idea or decision'),
            ),
            OutlinedButton.icon(
              onPressed: model.busy ? null : () => _improveProject(p, tasks),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Improve with AI'),
            ),
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${tasks.where((task) => task.status == TaskStatus.completed).length} / ${tasks.length} tasks complete',
              ),
              LinearProgressIndicator(
                value:
                    tasks
                        .where((task) => task.status == TaskStatus.completed)
                        .length /
                    tasks.length,
              ),
            ],
            section('Project entries'),
            ...model.data.entries
                .where((e) => e.projectId == p.id)
                .map(
                  (e) => Card(
                    elevation: 0,
                    color: Colors.white,
                    child: ListTile(
                      title: Text(e.title),
                      subtitle: Text(e.kind),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => entryDetail(e.id),
                    ),
                  ),
                ),
            section('Next steps'),
            if (tasks.isEmpty)
              empty(
                'Add a next step or link a capture by choosing this project when you turn it into a task.',
              ),
            ...tasks.map(taskTile),
          ]),
        );
      },
    ),
  );

  void entryDetail(String id) => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final entry = model.data.entries.firstWhere((e) => e.id == id);
        final related = model.data.entries.where(
          (e) => e.id == entry.relatedId || e.relatedId == id,
        );
        final tasks = model.data.tasks.where(
          (t) =>
              t.entryId == id ||
              (entry.captureId != null && t.captureId == entry.captureId),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(entry.kind),
            actions: [
              IconButton(
                tooltip: 'Edit entry',
                onPressed: () => edit('entry', entry: entry),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          body: content([
            heading(entry.title, 'Project note · kept separately from tasks'),
            SelectableText(entry.body),
            section('Related entries'),
            for (final other in related)
              ListTile(
                title: Text(other.title),
                subtitle: Text(other.kind),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => entryDetail(other.id),
              ),
            if (entry.captureId != null)
              FutureBuilder(
                future: model.repository.load(),
                builder: (context, snapshot) {
                  final captures = snapshot.data?.where(
                    (c) => c.id == entry.captureId,
                  );
                  return captures == null || captures.isEmpty
                      ? const SizedBox()
                      : OutlinedButton(
                          onPressed: () => openCapture(captures.first),
                          child: const Text('Read original capture'),
                        );
                },
              ),
            section('Next action'),
            if (tasks.isEmpty)
              FilledButton.icon(
                onPressed: () => edit('task', sourceEntry: entry),
                icon: const Icon(Icons.add_task),
                label: const Text('Create a next step'),
              ),
            ...tasks.map(taskTile),
          ]),
        );
      },
    ),
  );

  Widget planTile(PlanBlock p) {
    final task = p.taskId == null ? null : model.task(p.taskId!);
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: Icon(
          p.fixed
              ? Icons.event
              : p.taskId == null
              ? Icons.spa_outlined
              : Icons.schedule,
        ),
        title: Text(task?.title ?? p.title),
        subtitle: Text(
          '${dayKey(p.start) == dayKey(p.end) ? '' : '${dayKey(p.start)} · '}${TimeOfDay.fromDateTime(p.start).format(context)}–${TimeOfDay.fromDateTime(p.end).format(context)}${dayKey(p.start) == dayKey(p.end) ? '' : ' (${dayKey(p.end)})'} · ${task?.area ?? p.area}${p.fixed ? ' · Fixed' : ''}${task != null && !task.active ? ' · ${task.status.name}' : ''}',
        ),
        onTap: () => edit('plan', plan: p),
        trailing: PopupMenuButton<String>(
          tooltip: 'Plan options',
          onSelected: (v) {
            if (v == 'task' && task != null) {
              push(TaskDetail(model: model, taskId: task.id));
            }
            if (v == 'remove') {
              model.change(() => model.repository.removePlan(p.id));
            }
          },
          itemBuilder: (_) => [
            if (task != null)
              const PopupMenuItem(
                value: 'task',
                child: Text('Open linked task'),
              ),
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove plan block'),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, Object?>> _recurringOccurrences(DateTime day) =>
      ((const DayContextBuilder().build(model.data, day)['fixedCommitments']
                as List)
            .cast<Map<String, Object?>>())
        ..sort(
          (a, b) => (a['start'] as String).compareTo(b['start'] as String),
        );

  Widget recurringTile(Map<String, Object?> occurrence) => Card(
    elevation: 0,
    color: Colors.white,
    child: ListTile(
      leading: const Icon(Icons.event_repeat),
      title: Text(occurrence['title'] as String),
      subtitle: Text(
        '${occurrence['start']}–${occurrence['end']} · ${occurrence['kind']}${occurrence['location'] == '' ? '' : ' · ${occurrence['location']}'}${occurrence['movedFrom'] == null ? '' : ' · moved from ${occurrence['movedFrom']}'}',
      ),
      trailing: Icon(
        occurrence['fixed'] == true ? Icons.lock_outline : Icons.tune,
      ),
      onTap: () => push(DayArchitectSettings(model: model)),
    ),
  );

  Widget planner() {
    final plans = model.data.plans
        .where((p) => p.occursOn(selectedDay))
        .toList();
    final recurring = _recurringOccurrences(selectedDay);
    final dayProgress = CalendarProgress(model.data).forDay(selectedDay);
    return content([
      heading(
        'Planner',
        'Plan effort and personal time. Deadlines stay separate.',
      ),
      WorkLifeCalendar(
        data: model.data,
        selectedDay: selectedDay,
        onSelected: (day) => setState(() => selectedDay = day),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MaterialLocalizations.of(context).formatFullDate(selectedDay),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                dayProgress.total == 0
                    ? 'No linked or due tasks'
                    : '${dayProgress.completed} of ${dayProgress.total} tasks completed',
              ),
              const SizedBox(height: 8),
              Semantics(
                label:
                    '${(dayProgress.fraction * 100).round()} percent complete',
                child: LinearProgressIndicator(value: dayProgress.fraction),
              ),
              for (final task in dayProgress.tasks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    task.status == TaskStatus.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(task.title),
                  subtitle: Text(
                    '${task.priority.name} priority${model.reminderFor(task.id) == null ? '' : ' · reminder set'}',
                  ),
                  onTap: () => push(TaskDetail(model: model, taskId: task.id)),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Plan My Week',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Balance deadlines, commitments, focus, exercise and open time across Monday to Sunday.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: model.busy
                    ? null
                    : () => _planWeekWithAi(selectedDay),
                icon: const Icon(Icons.calendar_view_week),
                label: const Text('Plan My Week with AI'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => edit('plan'),
        icon: const Icon(Icons.add),
        label: const Text('Add time block'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: model.busy ? null : () => _planWithAi(selectedDay),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Optimize this day with AI'),
      ),
      const SizedBox(height: 20),
      if (plans.isEmpty && recurring.isEmpty)
        empty('An open day. Make room for commitments, buffers, and yourself.'),
      if (recurring.isNotEmpty) ...[
        section('Recurring commitments'),
        ...recurring.map(recurringTile),
      ],
      if (plans.isNotEmpty) section('Planned blocks'),
      ...plans.map(planTile),
      section('Due this day'),
      ...model.data.tasks
          .where((t) => t.deadline == dayKey(selectedDay))
          .map(taskTile),
      const SizedBox(height: 12),
      const Text(
        'Removing a block never cancels or completes its task. Times are shown in your device’s current timezone.',
      ),
    ]);
  }

  Widget routineTile(Routine r) {
    final today = dayKey(DateTime.now());
    final records = model.data.routineRecords.where(
      (v) => v.routineId == r.id && v.day == today,
    );
    final outcome = records.isEmpty ? null : records.first.outcome;
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.title),
              subtitle: Text(
                '${r.area}${r.window.isEmpty ? '' : ' · ${r.window}'}',
              ),
              trailing: IconButton(
                tooltip: 'Edit routine',
                onPressed: () => edit('routine', routine: r),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
            if (r.alternative.isNotEmpty) Text('Minimum: ${r.alternative}'),
            Text('Normal: ${r.descriptionFor(RoutineLevel.normal)}'),
            if (r.strong.isNotEmpty) Text('Strong: ${r.strong}'),
            const SizedBox(height: 8),
            Text(
              outcome == null
                  ? 'No outcome recorded today'
                  : 'Today: ${switch (outcome) {
                      'done' => 'Normal completed',
                      'smaller' => 'Minimum completed',
                      'strong' => 'Strong completed',
                      'later' => 'later · still pending',
                      _ => 'skipped',
                    }}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {
                  if (r.alternative.isNotEmpty) 'smaller': 'Minimum',
                  'done': 'Normal',
                  if (r.strong.isNotEmpty) 'strong': 'Strong',
                  'later': 'Later',
                  'skipped': 'Skip today',
                }.entries)
                  TextButton(
                    onPressed: model.busy
                        ? null
                        : () => model.change(
                            () => model.repository.recordRoutine(
                              RoutineRecord(
                                routineId: r.id,
                                day: today,
                                outcome: entry.key,
                              ),
                            ),
                          ),
                    child: Text(entry.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void routines() => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Routines')),
        body: content([
          heading(
            'Everyday care',
            'Flexible daily rhythms. A smaller step still counts.',
          ),
          FilledButton.icon(
            onPressed: () => edit('routine'),
            icon: const Icon(Icons.add),
            label: const Text('New routine'),
          ),
          OutlinedButton.icon(
            onPressed: () => edit('routine', routineTemplate: true),
            icon: const Icon(Icons.fitness_center_outlined),
            label: const Text('Add an exercise routine'),
          ),
          const SizedBox(height: 16),
          if (model.data.routines.isEmpty)
            empty(
              'Try a meal break, a walk, or time to catch up with someone.',
            ),
          ...model.data.routines.map(routineTile),
          const Text(
            'Routines follow the date on this device. Missing records mean unknown, not a missed day.',
          ),
        ]),
      ),
    ),
  );

  void reflection() => push(
    ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
        final sessions = model.data.sessions
            .where((s) => s.outcome != null && s.startedAt.isAfter(cutoff))
            .toList();
        final records = model.data.routineRecords
            .where(
              (r) =>
                  r.day.compareTo(
                    dayKey(DateTime.now().subtract(const Duration(days: 6))),
                  ) >=
                  0,
            )
            .toList();
        final completedSessions = sessions
            .where((s) => s.outcome != null)
            .toList();
        final focusMinutes =
            completedSessions.fold<int>(
              0,
              (sum, session) => sum + session.seconds,
            ) ~/
            60;
        final completedRoutines = records.where((r) => r.completed).length;
        final areasWithActivity = model.data.areas.where((area) {
          return completedSessions.any((s) => s.area == area) ||
              records.any((r) => r.completed && r.area == area);
        }).length;
        final reviewMessage =
            completedSessions.isEmpty && completedRoutines == 0
            ? 'No activity was recorded this week. That is unknown, not a failure — choose one small thing to make room for next week.'
            : 'You recorded $focusMinutes focus minutes and $completedRoutines routine outcomes across $areasWithActivity life areas. Keep what helped and choose one thing to protect next week.';
        final exerciseIds = model.data.routines
            .where((routine) {
              final text = '${routine.title} ${routine.area}'.toLowerCase();
              return text.contains('exercise') ||
                  text.contains('workout') ||
                  text.contains('fitness') ||
                  text.contains('health');
            })
            .map((routine) => routine.id)
            .toSet();
        final exerciseRecords = records
            .where(
              (record) =>
                  exerciseIds.contains(record.routineId) && record.completed,
            )
            .toList();
        final completedFocus = sessions
            .where((session) => session.outcome != null)
            .toList();
        final focusCompleted = completedFocus
            .where((s) => s.outcome == FocusOutcome.completed)
            .length;
        final focusPartial = completedFocus
            .where((s) => s.outcome == FocusOutcome.partial)
            .length;
        final focusBlocked = completedFocus
            .where((s) => s.outcome == FocusOutcome.blocked)
            .length;
        return Scaffold(
          appBar: AppBar(title: const Text('Life Map & reflection')),
          body: content([
            heading(
              'What have you made room for?',
              'Your recorded focus and routines over the last seven days.',
            ),
            const Text(
              'These are records, not a score for your life. Unrecorded time is unknown. Focus minutes are timer time you chose to finish; they do not prove uninterrupted activity.',
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your week at a glance',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _reviewMetric(
                          context,
                          Icons.timelapse,
                          '$focusMinutes min',
                          'recorded focus',
                        ),
                        _reviewMetric(
                          context,
                          Icons.check_circle_outline,
                          '$completedRoutines',
                          'routine outcomes',
                        ),
                        _reviewMetric(
                          context,
                          Icons.spa_outlined,
                          '$areasWithActivity',
                          'life areas touched',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(reviewMessage),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (exerciseIds.isNotEmpty)
              Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.fitness_center_outlined),
                  title: const Text('Exercise this week'),
                  subtitle: Text(
                    '${exerciseRecords.length} recorded session${exerciseRecords.length == 1 ? '' : 's'} · ${exerciseRecords.map((record) => record.day).toSet().length} active day${exerciseRecords.map((record) => record.day).toSet().length == 1 ? '' : 's'}',
                  ),
                  trailing: exerciseRecords.isEmpty
                      ? const Icon(Icons.chevron_right)
                      : Text('${exerciseRecords.length}/7'),
                ),
              ),
            if (completedFocus.isNotEmpty)
              Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.timelapse),
                  title: const Text('Focus history'),
                  subtitle: Text(
                    '$focusMinutes recorded minutes · $focusCompleted completed · $focusPartial partial · $focusBlocked blocked',
                  ),
                ),
              ),
            for (final area in model.data.areas)
              Card(
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.spa_outlined),
                  title: Text(area),
                  subtitle: Text(
                    '${sessions.where((s) => s.area == area).fold<int>(0, (sum, s) => sum + s.seconds) ~/ 60} recorded focus min · ${records.where((r) => r.completed && r.area == area).length} routine outcomes',
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: addArea,
              icon: const Icon(Icons.add),
              label: const Text('Add a life area'),
            ),
            section('A moment to reflect'),
            const Text(
              'What felt manageable? What needs less pressure? Who or what would you like to make time for next?',
            ),
            section('Recent focus sessions'),
            if (sessions.isEmpty)
              empty('No finished focus sessions recorded yet.'),
            for (final s in sessions)
              ListTile(
                title: Text(model.task(s.taskId)?.title ?? 'Task'),
                subtitle: Text(
                  '${s.outcome!.name} · ${s.seconds ~/ 60} min${s.notes.isEmpty ? '' : '\n${s.notes}'}',
                ),
              ),
          ]),
        );
      },
    ),
  );

  Widget _reviewMetric(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 6),
      Text('$value\n$label'),
    ],
  );

  Future<void> addArea() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _LifeAreaDialog(),
    );
    if (name != null) await model.change(() => model.repository.addArea(name));
  }

  Widget more() => content([
    heading(
      'The rest of your life belongs here.',
      'Tools for care, focus, and a thoughtful weekly reset.',
    ),
    for (final entry in <(IconData, String, String, VoidCallback)>[
      (
        Icons.checklist,
        'All tasks',
        'Open, completed, and cancelled',
        allTasks,
      ),
      (
        Icons.repeat,
        'Routines',
        'Meals, movement, relationships, and rest',
        routines,
      ),
      (
        Icons.spa_outlined,
        'Life Map & reflection',
        'User-defined areas and recorded activity',
        reflection,
      ),
      if (model.activeSession != null)
        (
          Icons.timelapse,
          'Focus',
          'Return to your active session',
          () => push(FocusScreen(model: model)),
        ),
      (
        Icons.settings_outlined,
        'Settings',
        'Quiet Hours and notification preferences',
        () => push(SettingsScreen(model: model, sync: widget.sync)),
      ),
      (
        Icons.waving_hand_outlined,
        'Run onboarding again',
        'Replay setup without deleting your tasks or preferences',
        () => push(
          OnboardingScreen(
            model: model,
            onFinished: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ])
      Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: Icon(entry.$1),
          title: Text(entry.$2),
          subtitle: Text(entry.$3),
          trailing: const Icon(Icons.chevron_right),
          onTap: entry.$4,
        ),
      ),
    if (widget.accountBuilder != null)
      Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('Account'),
          subtitle: Text(widget.accountLabel ?? 'Guest workspace'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(widget.accountBuilder!(context)),
        ),
      ),
    section('Your data'),
    Text(
      widget.sync == null
          ? 'Saved on this device. Guest workspaces stay local unless you explicitly export them.'
          : 'Saved on this device first, then securely synchronized with your signed-in workspace.',
    ),
  ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => model.loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : model.data.areas.isNotEmpty && !model.data.onboardingCompleted
        ? OnboardingScreen(model: model)
        : Scaffold(
            appBar: tab == 1
                ? null
                : AppBar(
                    title: const Text('Work Life'),
                    actions: [
                      IconButton(
                        tooltip: 'Quick capture',
                        onPressed: () => setState(() => tab = 1),
                        icon: const Icon(Icons.edit_note),
                      ),
                    ],
                  ),
            body: SafeArea(
              child: model.loading
                  ? const Center(child: CircularProgressIndicator())
                  : model.error != null && model.data.areas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(model.error!),
                          TextButton(
                            onPressed: model.load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (widget.accountNotice != null)
                          MaterialBanner(
                            content: Text(widget.accountNotice!),
                            actions: [
                              TextButton(
                                onPressed: widget.accountBuilder == null
                                    ? null
                                    : () =>
                                          push(widget.accountBuilder!(context)),
                                child: const Text('Account'),
                              ),
                            ],
                          ),
                        if (model.error != null)
                          MaterialBanner(
                            content: Text(model.error!),
                            actions: [
                              TextButton(
                                onPressed: model.busy ? null : model.load,
                                child: const Text('Reload'),
                              ),
                            ],
                          ),
                        if (model.busy) const LinearProgressIndicator(),
                        Expanded(
                          child: IndexedStack(
                            index: tab,
                            children: [
                              today(),
                              InboxScreen(
                                key: ValueKey(model.resetRevision),
                                repository: widget.repository,
                                onOpenCapture: openCapture,
                                onOrganizeCapture: _organizeWithAi,
                                workspaceModel: model,
                                onLocalChange: widget.sync?.sync,
                              ),
                              projects(),
                              planner(),
                              more(),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (value) => setState(() => tab = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.wb_sunny_outlined),
                  selectedIcon: Icon(Icons.wb_sunny),
                  label: 'Today',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inbox_outlined),
                  selectedIcon: Icon(Icons.inbox),
                  label: 'Inbox',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Projects',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Planner',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
              ],
            ),
          ),
  );
}

class _LifeAreaDialog extends StatefulWidget {
  const _LifeAreaDialog();
  @override
  State<_LifeAreaDialog> createState() => _LifeAreaDialogState();
}

class _LifeAreaDialogState extends State<_LifeAreaDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a life area'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Add'),
      ),
    ],
  );
}
