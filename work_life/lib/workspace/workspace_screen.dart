import 'dart:async';

import 'package:flutter/material.dart';

import '../captures/capture.dart';
import '../captures/inbox_screen.dart';
import '../notifications/reminder_notifications.dart';
import 'editors.dart';
import 'focus_screen.dart';
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
  });
  final WorkspaceRepository repository;
  final WidgetBuilder? accountBuilder;
  final String? accountLabel, accountNotice;
  final ReminderNotifications? notifications;
  final String notificationScope;
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
    )..load();
    dayTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
      unawaited(model.refreshNotifications());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      unawaited(model.refreshNotifications());
    }
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
        '${task.area} · ${task.minutes} min${task.deadline == null ? '' : ' · Due ${task.deadline}'}${task.active ? '' : ' · ${task.status.name}'}',
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
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: notifications.working || model.busy
                  ? null
                  : () => model.refreshNotifications(requestPermission: true),
              child: const Text('Enable notifications'),
            ),
            TextButton(
              onPressed: notifications.working
                  ? null
                  : notifications.openSettings,
              child: const Text('Notification settings'),
            ),
            TextButton(
              onPressed: notifications.working || model.busy
                  ? null
                  : model.refreshNotifications,
              child: const Text('Retry notifications'),
            ),
          ],
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
      section('Your time'),
      if (plans.isEmpty)
        empty(
          'Leave breathing room. Add work, a meal, time together, or a break in Planner.',
        ),
      ...plans.map(planTile),
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
    for (final p in model.data.projects)
      Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(p.title),
          subtitle: Text(
            '${p.area} · ${model.data.tasks.where((t) => t.projectId == p.id && t.active).length} open tasks',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => projectDetail(p.id),
        ),
      ),
  ]);

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

  Widget planner() {
    final plans = model.data.plans
        .where((p) => p.occursOn(selectedDay))
        .toList();
    return content([
      heading(
        'Planner',
        'Plan effort and personal time. Deadlines stay separate.',
      ),
      Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => setState(
              () => selectedDay = DateTime(
                selectedDay.year,
                selectedDay.month,
                selectedDay.day - 1,
              ),
            ),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: TextButton(
              onPressed: () async {
                final day = await showDatePicker(
                  context: context,
                  initialDate: selectedDay,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2200),
                );
                if (day != null && mounted) setState(() => selectedDay = day);
              },
              child: Text(
                MaterialLocalizations.of(context).formatMediumDate(selectedDay),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => setState(
              () => selectedDay = DateTime(
                selectedDay.year,
                selectedDay.month,
                selectedDay.day + 1,
              ),
            ),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      FilledButton.icon(
        onPressed: () => edit('plan'),
        icon: const Icon(Icons.add),
        label: const Text('Add time block'),
      ),
      const SizedBox(height: 20),
      if (plans.isEmpty)
        empty('An open day. Make room for commitments, buffers, and yourself.'),
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
        () => push(SettingsScreen(model: model)),
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
    const Text(
      'Saved on this device. Cloud backup, notifications, and AI are not connected yet. Your captures and tasks work offline.',
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
