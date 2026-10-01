import 'package:flutter/material.dart';

import '../workspace/records.dart';
import '../workspace/workspace_model.dart';
import 'ai_proposals.dart';

class AiCaptureProposalScreen extends StatefulWidget {
  const AiCaptureProposalScreen({
    super.key,
    required this.model,
    required this.proposal,
    this.captureId,
  });

  final WorkspaceModel model;
  final AiCaptureProposal proposal;
  final String? captureId;

  @override
  State<AiCaptureProposalScreen> createState() =>
      _AiCaptureProposalScreenState();
}

class _AiCaptureProposalScreenState extends State<AiCaptureProposalScreen> {
  final operationId = newId();
  late final TextEditingController title;
  late final TextEditingController window;
  late final TextEditingController minimum;
  late final TextEditingController normal;
  late final TextEditingController strong;
  late final TextEditingController suggestedArea;
  late String area;
  bool saving = false, createSuggestedArea = false;

  AiTaskProposal? get task => widget.proposal.task;
  AiRoutineProposal? get routine => widget.proposal.routine;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: task?.title ?? routine?.title ?? '');
    window = TextEditingController(text: routine?.window ?? '');
    minimum = TextEditingController(text: routine?.minimum ?? '');
    normal = TextEditingController(text: routine?.normal ?? '');
    strong = TextEditingController(text: routine?.strong ?? '');
    final requestedArea = task?.area ?? routine?.area;
    area =
        _existingArea(requestedArea) ??
        _existingArea('Work') ??
        widget.model.data.areas.first;
    suggestedArea = TextEditingController(
      text: _existingArea(requestedArea) == null ? requestedArea?.trim() : '',
    );
  }

  @override
  void dispose() {
    title.dispose();
    window.dispose();
    minimum.dispose();
    normal.dispose();
    strong.dispose();
    suggestedArea.dispose();
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

  Future<void> pickDeadline() async {
    final value = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(task?.deadline ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (value != null) setState(() => task!.deadline = dayKey(value));
  }

  Future<void> pickReminder() async {
    final current =
        DateTime.tryParse(task?.reminder ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime(2200),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    setState(() {
      task!.reminder = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toUtc().toIso8601String();
    });
  }

  Future<void> approve() async {
    if (saving) return;
    final text = title.text.trim();
    if (text.isEmpty || (routine != null && minimum.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title and required details.')),
      );
      return;
    }
    final suggestion = suggestedArea.text.trim();
    final reusedArea = _existingArea(suggestion);
    final approvedArea = createSuggestedArea && suggestion.isNotEmpty
        ? reusedArea ?? suggestion
        : area;
    widget.proposal.createArea =
        createSuggestedArea && suggestion.isNotEmpty && reusedArea == null;
    task?.title = text;
    task?.area = approvedArea;
    if (routine case final value?) {
      value
        ..title = text
        ..area = approvedArea
        ..window = window.text.trim()
        ..minimum = minimum.text.trim()
        ..normal = normal.text.trim()
        ..strong = strong.text.trim();
    }
    setState(() => saving = true);
    final ok = await widget.model.change(
      () => widget.model.repository.applyCaptureProposal(
        widget.proposal,
        operationId: operationId,
        captureId: widget.captureId,
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
  Widget build(BuildContext context) {
    final isReminder = widget.proposal.kind == AiCaptureKind.reminder;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          routine != null
              ? 'Review routine'
              : isReminder
              ? 'Review reminder'
              : 'Review task',
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Suggested by AI · nothing is saved until you approve.'),
          const SizedBox(height: 16),
          TextField(
            controller: title,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: routine != null ? 'Routine title' : 'Task title',
            ),
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
                      'AI suggested a new reusable area. It will only be created if you approve it below.',
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
            initialValue: widget.model.data.areas.contains(area)
                ? area
                : 'Work',
            decoration: const InputDecoration(labelText: 'Life area'),
            items: widget.model.data.areas
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: saving
                ? null
                : (value) => setState(() => area = value ?? 'Work'),
          ),
          if (task case final value?) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: value.priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const ['low', 'medium', 'high']
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (item) => value.priority = item ?? 'medium',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '${value.minutes}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                    onChanged: (text) =>
                        value.minutes = int.tryParse(text) ?? 25,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: saving ? null : pickDeadline,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                value.deadline == null
                    ? 'Choose deadline (optional)'
                    : 'Due ${value.deadline}',
              ),
            ),
            if (isReminder) ...[
              OutlinedButton.icon(
                onPressed: saving ? null : pickReminder,
                icon: const Icon(Icons.notifications_outlined),
                label: Text(
                  value.reminder == null
                      ? 'Choose reminder time'
                      : MaterialLocalizations.of(context).formatFullDate(
                          DateTime.parse(value.reminder!).toLocal(),
                        ),
                ),
              ),
              if (value.reminder != null)
                Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay.fromDateTime(
                      DateTime.parse(value.reminder!).toLocal(),
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
            TextFormField(
              initialValue: value.checklist.join('\n'),
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Checklist (one item per line)',
              ),
              onChanged: (text) => value.checklist = text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList(),
            ),
          ],
          if (routine != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: window,
              decoration: const InputDecoration(
                labelText: 'When / repeating schedule',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minimum,
              decoration: const InputDecoration(labelText: 'Minimum version'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: normal,
              decoration: const InputDecoration(labelText: 'Normal version'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: strong,
              decoration: const InputDecoration(labelText: 'Strong version'),
            ),
          ],
          if (widget.proposal.questions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Check before approving',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final question in widget.proposal.questions)
              Text('• $question'),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: saving ? null : approve,
            icon: const Icon(Icons.check),
            label: Text(saving ? 'Saving…' : 'Approve and save'),
          ),
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: const Text('Reject proposal'),
          ),
        ],
      ),
    );
  }
}
