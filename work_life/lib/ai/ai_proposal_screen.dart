import 'package:flutter/material.dart';

import '../workspace/records.dart';
import '../workspace/workspace_model.dart';
import 'ai_proposals.dart';

class AiProjectProposalScreen extends StatefulWidget {
  const AiProjectProposalScreen({
    super.key,
    required this.model,
    required this.proposal,
    this.captureId,
    this.targetProjectId,
    this.onRegenerate,
    this.onClarify,
  });
  final WorkspaceModel model;
  final AiProjectProposal proposal;
  final String? captureId;
  final String? targetProjectId;
  final Future<AiProjectProposal> Function()? onRegenerate;
  final Future<AiProjectProposal> Function(
    AiProjectProposal current,
    Map<String, String> answers,
  )?
  onClarify;

  @override
  State<AiProjectProposalScreen> createState() =>
      _AiProjectProposalScreenState();
}

class _AiProjectProposalScreenState extends State<AiProjectProposalScreen> {
  late AiProjectProposal proposal = widget.proposal;
  late TextEditingController projectTitle, description, suggestedArea;
  late List<TextEditingController> taskTitles;
  late List<TextEditingController> questionAnswers;
  late String area;
  final operationId = newId();
  bool saving = false, regenerating = false, createSuggestedArea = false;

  @override
  void initState() {
    super.initState();
    _controllers();
  }

  void _controllers() {
    projectTitle = TextEditingController(text: proposal.title);
    description = TextEditingController(text: proposal.description);
    final requestedArea = proposal.area;
    area =
        _existingArea(requestedArea) ??
        _existingArea('Work') ??
        widget.model.data.areas.first;
    suggestedArea = TextEditingController(
      text: _existingArea(requestedArea) == null ? requestedArea?.trim() : '',
    );
    taskTitles = proposal.tasks
        .map((task) => TextEditingController(text: task.title))
        .toList();
    questionAnswers = proposal.questions
        .map((_) => TextEditingController())
        .toList();
  }

  @override
  void dispose() {
    projectTitle.dispose();
    description.dispose();
    suggestedArea.dispose();
    for (final controller in taskTitles) {
      controller.dispose();
    }
    for (final controller in questionAnswers) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _existingArea(String? value) {
    final wanted = value?.trim().toLowerCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final existing in widget.model.data.areas) {
      if (existing.toLowerCase() == wanted) return existing;
    }
    return null;
  }

  void addTask() {
    setState(() {
      proposal.tasks.add(AiTaskProposal(title: ''));
      taskTitles.add(TextEditingController());
    });
  }

  void moveTask(int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= proposal.tasks.length) return;
    setState(() {
      final task = proposal.tasks.removeAt(index);
      final controller = taskTitles.removeAt(index);
      proposal.tasks.insert(target, task);
      taskTitles.insert(target, controller);
    });
  }

  AiProjectChange changeFor(AiTaskProposal task) {
    if (task.change != AiProjectChange.auto) return task.change;
    if (task.taskId == null) return AiProjectChange.add;
    final existing = widget.model.task(task.taskId!);
    if (existing == null) return AiProjectChange.change;
    final changedExceptDate =
        existing.title != task.title ||
        existing.area != (task.area ?? proposal.area ?? existing.area) ||
        existing.priority.name != task.priority ||
        existing.minutes != task.minutes ||
        (task.checklist.isNotEmpty &&
            existing.checklist.map((item) => item.text).join('\n') !=
                task.checklist.join('\n'));
    if (!changedExceptDate && existing.deadline != task.deadline) {
      return AiProjectChange.move;
    }
    if (changedExceptDate || existing.deadline != task.deadline) {
      return AiProjectChange.change;
    }
    return AiProjectChange.unchanged;
  }

  String changeLabel(AiProjectChange value) => switch (value) {
    AiProjectChange.add => 'ADD',
    AiProjectChange.change => 'CHANGE',
    AiProjectChange.move => 'MOVE',
    AiProjectChange.remove => 'REMOVE',
    AiProjectChange.unchanged => 'UNCHANGED',
    AiProjectChange.auto => 'CHANGE',
  };

  String? previousValue(AiTaskProposal task, AiProjectChange change) {
    if (task.taskId == null) return null;
    final existing = widget.model.task(task.taskId!);
    if (existing == null) return null;
    if (change == AiProjectChange.move) {
      return '${existing.deadline ?? 'No date'} → ${task.deadline ?? 'No date'}';
    }
    if (change == AiProjectChange.change && existing.title != task.title) {
      return '${existing.title} → ${task.title}';
    }
    if (change == AiProjectChange.remove) return existing.title;
    return null;
  }

  Future<void> pickDeadline(AiTaskProposal task) async {
    final initial = DateTime.tryParse(task.deadline ?? '') ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (value != null && mounted) {
      setState(() => task.deadline = dayKey(value));
    }
  }

  Future<String?> _pickDateTime(String? current) async {
    final initial =
        DateTime.tryParse(current ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime(2200),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).toIso8601String();
  }

  Future<void> _answerQuestions() async {
    final action = widget.onClarify;
    if (action == null || regenerating) return;
    final answers = <String, String>{};
    for (var index = 0; index < proposal.questions.length; index++) {
      final answer = questionAnswers[index].text.trim();
      if (answer.isNotEmpty) answers[proposal.questions[index]] = answer;
    }
    if (answers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answer at least one question first.')),
      );
      return;
    }
    setState(() => regenerating = true);
    try {
      final replacement = await action(proposal, answers);
      if (!mounted) return;
      projectTitle.dispose();
      description.dispose();
      suggestedArea.dispose();
      for (final controller in taskTitles) {
        controller.dispose();
      }
      for (final controller in questionAnswers) {
        controller.dispose();
      }
      setState(() {
        proposal = replacement;
        createSuggestedArea = false;
        _controllers();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t update the plan from those answers. Your current proposal is unchanged.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => regenerating = false);
    }
  }

  Future<void> approve() async {
    if (saving) return;
    proposal.title = projectTitle.text.trim();
    final suggestion = suggestedArea.text.trim();
    final reusedArea = _existingArea(suggestion);
    final approvedArea = createSuggestedArea && suggestion.isNotEmpty
        ? reusedArea ?? suggestion
        : area;
    proposal
      ..area = approvedArea
      ..createArea =
          createSuggestedArea && suggestion.isNotEmpty && reusedArea == null;
    for (var index = 0; index < proposal.tasks.length; index++) {
      final task = proposal.tasks[index];
      task.title = taskTitles[index].text.trim();
      final taskArea = _existingArea(task.area);
      if (taskArea != null) {
        task.area = taskArea;
      } else if (task.area == null ||
          task.area!.trim().toLowerCase() != approvedArea.toLowerCase()) {
        task.area = approvedArea;
      }
    }
    if (proposal.title.isEmpty ||
        proposal.tasks
            .where((task) => task.included && task.title.isNotEmpty)
            .isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a project title and at least one task.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    final ok = await widget.model.change(
      () => widget.model.repository.applyProjectProposal(
        proposal,
        operationId: operationId,
        captureId: widget.captureId,
        targetProjectId: widget.targetProjectId,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.targetProjectId == null
            ? 'Review your plan'
            : 'Review project updates',
      ),
    ),
    body: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Review the plan in plain language. Nothing except your original note is saved until you approve.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: projectTitle,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Plan title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: description,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(labelText: 'Project purpose'),
          onChanged: (value) => proposal.description = value,
        ),
        if (suggestedArea.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested Life Area',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Nothing new is created until you explicitly approve this reusable area.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: suggestedArea,
                    enabled: !saving,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Area name'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Create and use this area'),
                    value: createSuggestedArea,
                    onChanged: saving
                        ? null
                        : (value) =>
                              setState(() => createSuggestedArea = value),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: widget.model.data.areas.contains(area) ? area : 'Work',
          decoration: const InputDecoration(labelText: 'Life area'),
          items: widget.model.data.areas
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: saving
              ? null
              : (value) => setState(() {
                  area = value ?? 'Work';
                  proposal.area = area;
                }),
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < proposal.tasks.length; index++) ...[
          if ((proposal.tasks[index].group?.trim().isNotEmpty ?? false) &&
              (index == 0 ||
                  proposal.tasks[index - 1].group !=
                      proposal.tasks[index].group)) ...[
            const SizedBox(height: 12),
            Text(
              proposal.tasks[index].group!,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (widget.targetProjectId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: Icon(
                          changeFor(proposal.tasks[index]) ==
                                  AiProjectChange.add
                              ? Icons.add
                              : changeFor(proposal.tasks[index]) ==
                                    AiProjectChange.remove
                              ? Icons.remove
                              : changeFor(proposal.tasks[index]) ==
                                    AiProjectChange.move
                              ? Icons.event_repeat
                              : Icons.edit_outlined,
                          size: 18,
                        ),
                        label: Text(
                          changeLabel(changeFor(proposal.tasks[index])),
                        ),
                      ),
                    ),
                  if (previousValue(
                        proposal.tasks[index],
                        changeFor(proposal.tasks[index]),
                      )
                      case final value?)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(value),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Checkbox(
                          value: proposal.tasks[index].included,
                          onChanged: saving
                              ? null
                              : (value) => setState(
                                  () => proposal.tasks[index].included =
                                      value ?? false,
                                ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: taskTitles[index],
                          minLines: 1,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Task title',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (proposal.tasks[index].details.trim().isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(proposal.tasks[index].details),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(proposal.tasks[index].priority)),
                      Chip(label: Text('${proposal.tasks[index].minutes} min')),
                      if (proposal.tasks[index].deadline != null)
                        Chip(
                          avatar: const Icon(Icons.event_outlined, size: 16),
                          label: Text('Due ${proposal.tasks[index].deadline}'),
                        ),
                      if (proposal.tasks[index].plannedStart != null)
                        const Chip(
                          avatar: Icon(Icons.calendar_month_outlined, size: 16),
                          label: Text('Calendar'),
                        ),
                      if (proposal.tasks[index].reminder != null)
                        const Chip(
                          avatar: Icon(Icons.notifications_outlined, size: 16),
                          label: Text('Reminder'),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                    title: const Text('Edit details, dates and reminders'),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: proposal.tasks[index].priority,
                              decoration: const InputDecoration(
                                labelText: 'Priority',
                              ),
                              items: const ['low', 'medium', 'high']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: saving
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(
                                          () => proposal.tasks[index].priority =
                                              value,
                                        );
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: '${proposal.tasks[index].minutes}',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                              ),
                              onChanged: (value) => setState(
                                () => proposal.tasks[index].minutes =
                                    int.tryParse(value) ?? 25,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () => pickDeadline(proposal.tasks[index]),
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          proposal.tasks[index].deadline == null
                              ? 'Set deadline'
                              : 'Due ${proposal.tasks[index].deadline}',
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      proposal.tasks[index].plannedStart,
                                    );
                                    if (value != null && mounted) {
                                      setState(
                                        () =>
                                            proposal.tasks[index].plannedStart =
                                                value,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(
                              proposal.tasks[index].plannedStart == null
                                  ? 'Add to calendar'
                                  : 'Change calendar time',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    final value = await _pickDateTime(
                                      proposal.tasks[index].reminder,
                                    );
                                    if (value != null && mounted) {
                                      setState(
                                        () => proposal.tasks[index].reminder =
                                            value,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.notifications_outlined),
                            label: Text(
                              proposal.tasks[index].reminder == null
                                  ? 'Add reminder'
                                  : 'Change reminder',
                            ),
                          ),
                        ],
                      ),
                      if (proposal.tasks[index].deadline != null ||
                          proposal.tasks[index].plannedStart != null ||
                          proposal.tasks[index].reminder != null)
                        TextButton(
                          onPressed: saving
                              ? null
                              : () => setState(() {
                                  proposal.tasks[index]
                                    ..deadline = null
                                    ..plannedStart = null
                                    ..reminder = null;
                                }),
                          child: const Text('Clear dates and reminder'),
                        ),
                      TextFormField(
                        initialValue: proposal.tasks[index].checklist.join(
                          '\n',
                        ),
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Preparation checklist',
                        ),
                        onChanged: (value) =>
                            proposal.tasks[index].checklist = value
                                .split('\n')
                                .map((line) => line.trim())
                                .where((line) => line.isNotEmpty)
                                .toList(),
                      ),
                    ],
                  ),
                  if (widget.targetProjectId != null &&
                      proposal.tasks[index].taskId != null)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Chip(label: Text('Updates existing task')),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Move task up',
                        onPressed: saving || index == 0
                            ? null
                            : () => moveTask(index, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Move task down',
                        onPressed: saving || index == proposal.tasks.length - 1
                            ? null
                            : () => moveTask(index, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        OutlinedButton.icon(
          onPressed: saving ? null : addTask,
          icon: const Icon(Icons.add),
          label: const Text('Add task'),
        ),
        if (proposal.questions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Help AI finish the plan',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Answer what you know. The plan will update without saving anything.',
                  ),
                  const SizedBox(height: 12),
                  for (
                    var index = 0;
                    index < proposal.questions.length;
                    index++
                  ) ...[
                    Text(proposal.questions[index]),
                    const SizedBox(height: 6),
                    TextField(
                      controller: questionAnswers[index],
                      enabled: !regenerating,
                      decoration: const InputDecoration(
                        hintText: 'Type your answer…',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: saving || regenerating ? null : _answerQuestions,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      regenerating
                          ? 'Updating plan…'
                          : 'Update plan with answers',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (widget.onRegenerate != null)
          OutlinedButton.icon(
            onPressed: saving || regenerating
                ? null
                : () async {
                    setState(() => regenerating = true);
                    try {
                      final replacement = await widget.onRegenerate!();
                      if (!mounted) return;
                      projectTitle.dispose();
                      description.dispose();
                      suggestedArea.dispose();
                      for (final controller in taskTitles) {
                        controller.dispose();
                      }
                      for (final controller in questionAnswers) {
                        controller.dispose();
                      }
                      setState(() {
                        proposal = replacement;
                        createSuggestedArea = false;
                        _controllers();
                      });
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Couldn’t rebuild the proposal. Nothing was changed.',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => regenerating = false);
                    }
                  },
            icon: const Icon(Icons.refresh),
            label: Text(regenerating ? 'Rebuilding…' : 'Regenerate'),
          ),
        FilledButton.icon(
          onPressed: saving ? null : approve,
          icon: const Icon(Icons.check),
          label: Text(
            saving
                ? 'Saving…'
                : widget.targetProjectId == null
                ? 'Approve plan'
                : 'Apply approved changes',
          ),
        ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: Text(
            widget.targetProjectId == null
                ? 'Keep only the original note'
                : 'Discard suggested changes',
          ),
        ),
      ],
    ),
  );
}
