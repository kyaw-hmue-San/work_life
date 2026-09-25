import 'package:flutter/material.dart';

import '../notifications/reminder_notifications.dart';
import '../notifications/snooze.dart';

import 'editors.dart';
import 'focus_screen.dart';
import 'records.dart';
import 'reminder_editor.dart';
import 'workspace_model.dart';

class TaskDetail extends StatelessWidget {
  const TaskDetail({super.key, required this.model, required this.taskId});
  final WorkspaceModel model;
  final String taskId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final task = model.task(taskId);
      if (task == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Task')),
          body: const Center(child: Text('This task is unavailable.')),
        );
      }
      final projects = model.data.projects.where((p) => p.id == task.projectId);
      final reminder = model.reminderFor(taskId);
      Future<void> snooze(SnoozeOption option) async {
        if (reminder == null) return;
        await model.change(
          () => model.repository.saveReminder(
            snoozedReminder(reminder, option),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Task details'),
          actions: [
            IconButton(
              tooltip: 'Edit task',
              onPressed: model.busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<bool>(
                        builder: (_) => RecordEditor(
                          model: model,
                          kind: 'task',
                          task: task,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                task.area.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '${task.active ? (task.status == TaskStatus.inProgress ? 'In progress' : 'Open') : task.status.name} · ${task.minutes} min estimated',
              ),
              if (projects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Project: ${projects.first.title}'),
                ),
              const SizedBox(height: 12),
              Text(
                task.deadline == null
                    ? 'No deadline set'
                    : 'Confirmed deadline: ${task.deadline}',
              ),
              if (task.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SelectableText(task.notes),
                ),
              if (task.active) ...[
                const SizedBox(height: 16),
                Text(
                  reminder == null
                      ? 'No reminder set'
                      : 'Reminder: ${reminderTimeLabel(context, reminder.scheduledAt)}\n${reminderDeliveryLabel(reminder.deliveryStatus)}',
                ),
                OutlinedButton.icon(
                  onPressed: model.busy
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              ReminderEditor(model: model, taskId: taskId),
                        ),
                  icon: const Icon(Icons.notifications_outlined),
                  label: Text(
                    reminder == null ? 'Set reminder' : 'Reschedule reminder',
                  ),
                ),
                if (reminder != null)
                  PopupMenuButton<SnoozeOption>(
                    enabled: !model.busy,
                    onSelected: snooze,
                    itemBuilder: (_) => [
                      for (final option in SnoozeOption.values)
                        PopupMenuItem(
                          value: option,
                          child: Text(snoozeLabel(option)),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.snooze_outlined),
                          SizedBox(width: 8),
                          Text('Snooze'),
                        ],
                      ),
                    ),
                  ),
                if (reminder != null)
                  TextButton(
                    onPressed: model.busy
                        ? null
                        : () => model.change(
                            () => model.repository.removeReminder(taskId),
                          ),
                    child: const Text('Remove reminder'),
                  ),
              ],
              if (task.checklist.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Preparation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final item in task.checklist)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(item.text),
                    value: item.done,
                    onChanged: model.busy
                        ? null
                        : (_) => model.change(
                            () => model.repository.saveTask(
                              task.withChecklist(
                                task.checklist
                                    .map(
                                      (c) => c.id == item.id ? c.toggle() : c,
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                  ),
              ],
              if (task.entryId != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Source project entry',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final entry in model.data.entries.where(
                  (e) => e.id == task.entryId,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(
                      '${entry.title} (${entry.kind})\n${entry.body}',
                    ),
                  ),
              ],
              if (task.captureId != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Original capture',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FutureBuilder(
                  future: model.repository.load(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'Couldn’t load the original. It remains saved in Inbox.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final sources = snapshot.data!.where(
                      (c) => c.id == task.captureId,
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SelectableText(
                        sources.isEmpty
                            ? 'Original capture unavailable.'
                            : sources.first.originalText,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              if (task.active) ...[
                FilledButton.icon(
                  onPressed: model.busy
                      ? null
                      : () async {
                          final active = model.activeSession;
                          if (active == null) {
                            final now = DateTime.now().toUtc();
                            final ok = await model.change(
                              () => model.repository.saveSession(
                                FocusSession(
                                  id: newId(),
                                  taskId: task.id,
                                  minutes: task.minutes,
                                  startedAt: now,
                                  runningSince: now,
                                ),
                              ),
                            );
                            if (!ok || !context.mounted) return;
                          }
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => FocusScreen(model: model),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    model.activeSession == null
                        ? 'Start focus · ${task.minutes} min'
                        : 'Return to active focus',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (_) => RecordEditor(
                        model: model,
                        kind: 'plan',
                        plan: PlanBlock(
                          id: newId(),
                          title: task.title,
                          start: DateTime.now().add(const Duration(hours: 1)),
                          minutes: task.minutes,
                          area: task.area,
                          taskId: task.id,
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Plan time for this'),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: model.busy
                      ? null
                      : () => model.setStatus(task, TaskStatus.completed),
                  child: const Text('Mark task completed'),
                ),
                TextButton(
                  onPressed: model.busy
                      ? null
                      : () => model.setStatus(task, TaskStatus.cancelled),
                  child: const Text('Cancel task'),
                ),
              ] else
                OutlinedButton(
                  onPressed: model.busy
                      ? null
                      : () => model.setStatus(task, TaskStatus.open),
                  child: const Text('Reopen task'),
                ),
              if (model.error != null)
                Text(
                  model.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      );
    },
  );
}
