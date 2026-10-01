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
  });
  final WorkspaceModel model;
  final AiProjectProposal proposal;
  final String? captureId;
  final String? targetProjectId;
  final Future<AiProjectProposal> Function()? onRegenerate;

  @override
  State<AiProjectProposalScreen> createState() =>
      _AiProjectProposalScreenState();
}

class _AiProjectProposalScreenState extends State<AiProjectProposalScreen> {
  late AiProjectProposal proposal = widget.proposal;
  late TextEditingController projectTitle, description, suggestedArea;
  late List<TextEditingController> taskTitles;
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
  }

  @override
  void dispose() {
    projectTitle.dispose();
    description.dispose();
    suggestedArea.dispose();
    for (final controller in taskTitles) {
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
            ? 'Review AI proposal'
            : 'Review proposed changes',
      ),
    ),
    body: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Suggested · nothing is saved until you approve.'),
        const SizedBox(height: 16),
        TextField(
          controller: projectTitle,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Project title'),
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
        for (var index = 0; index < proposal.tasks.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: Icon(
                        changeFor(proposal.tasks[index]) == AiProjectChange.add
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
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: TextField(
                      controller: taskTitles[index],
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                      ),
                    ),
                    value: proposal.tasks[index].included,
                    onChanged: saving
                        ? null
                        : (value) => setState(
                            () =>
                                proposal.tasks[index].included = value ?? false,
                          ),
                  ),
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
                                    proposal.tasks[index].priority = value;
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
                          onChanged: (value) => proposal.tasks[index].minutes =
                              int.tryParse(value) ?? 25,
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
                          ? 'Choose deadline (optional)'
                          : 'Due ${proposal.tasks[index].deadline}',
                    ),
                  ),
                  if (proposal.tasks[index].deadline != null)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => setState(
                              () => proposal.tasks[index].deadline = null,
                            ),
                      child: const Text('Remove deadline'),
                    ),
                  TextFormField(
                    initialValue: proposal.tasks[index].checklist.join('\n'),
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Checklist (one item per line)',
                    ),
                    onChanged: (value) =>
                        proposal.tasks[index].checklist = value
                            .split('\n')
                            .map((line) => line.trim())
                            .where((line) => line.isNotEmpty)
                            .toList(),
                  ),
                  if (proposal.tasks[index].taskId != null)
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
        OutlinedButton.icon(
          onPressed: saving ? null : addTask,
          icon: const Icon(Icons.add),
          label: const Text('Add task'),
        ),
        if (proposal.questions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Questions', style: Theme.of(context).textTheme.titleMedium),
          for (final question in proposal.questions) Text('• $question'),
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
                ? 'Approve and create'
                : 'Apply approved changes',
          ),
        ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Reject proposal'),
        ),
      ],
    ),
  );
}
