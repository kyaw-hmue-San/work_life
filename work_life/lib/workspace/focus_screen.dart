import 'dart:async';

import 'package:flutter/material.dart';

import 'records.dart';
import 'workspace_model.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.model});
  final WorkspaceModel model;
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  late final Timer ticker;
  final notes = TextEditingController();
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final model = widget.model;
      final session = model.activeSession;
      final task = session == null ? null : model.task(session.taskId);
      return Scaffold(
        appBar: AppBar(title: const Text('Focus')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (session == null || task == null) ...[
                const Text('No active focus session. Start one from a task.'),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to your day'),
                ),
              ] else ...[
                Text(
                  task.area.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                Text(
                  '${(session.elapsed(DateTime.now().toUtc()) ~/ 60).toString().padLeft(2, '0')}:${(session.elapsed(DateTime.now().toUtc()) % 60).toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                Text(
                  '${session.minutes} min planned · ${session.runningSince == null ? 'Paused' : 'Running'}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The timer continues when you leave this screen or close the app. Pause for breaks; ending a timer never completes a task automatically.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (task.notes.isNotEmpty) Text(task.notes),
                for (final item in task.checklist)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: model.busy || !task.active
                      ? null
                      : () => model.change(
                          () => model.repository.saveSession(
                            session.runningSince == null
                                ? session.resume(DateTime.now().toUtc())
                                : session.pause(DateTime.now().toUtc()),
                          ),
                        ),
                  icon: Icon(
                    session.runningSince == null
                        ? Icons.play_arrow
                        : Icons.pause,
                  ),
                  label: Text(
                    session.runningSince == null
                        ? 'Resume'
                        : 'Pause for a break',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Session notes / next step',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'How did it go?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final outcome in FocusOutcome.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.tonal(
                      onPressed:
                          model.busy ||
                              (outcome == FocusOutcome.completed &&
                                  !task.active)
                          ? null
                          : () async {
                              final ok = await model.change(
                                () => model.repository.saveSession(
                                  session.finish(
                                    DateTime.now().toUtc(),
                                    outcome,
                                    notes.text,
                                  ),
                                ),
                              );
                              if (ok && context.mounted) Navigator.pop(context);
                            },
                      child: Text(switch (outcome) {
                        FocusOutcome.completed => 'Finish and complete task',
                        FocusOutcome.partial =>
                          'Made progress · leave task open',
                        FocusOutcome.blocked => 'Blocked · leave task open',
                      }),
                    ),
                  ),
                if (model.error != null)
                  Text(
                    model.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
