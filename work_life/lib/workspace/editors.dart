import 'package:flutter/material.dart';

import '../captures/capture.dart';
import 'records.dart';
import 'workspace_model.dart';

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.model,
    required this.kind,
    this.task,
    this.entry,
    this.sourceEntry,
    this.project,
    this.plan,
    this.routine,
    this.capture,
    this.projectId,
    this.day,
  });
  final WorkspaceModel model;
  final String kind;
  final Task? task;
  final ProjectEntry? entry, sourceEntry;
  final Project? project;
  final PlanBlock? plan;
  final Routine? routine;
  final Capture? capture;
  final String? projectId;
  final DateTime? day;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title,
      notes,
      minutes,
      checklist,
      window,
      alternative,
      normal,
      strong;
  late String area;
  String? projectId, taskId, deadline, relatedId;
  String entryKind = 'note';
  late DateTime start;
  bool fixed = false, saving = false;
  String? error;
  late final String id;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final p = widget.project;
    final b = widget.plan;
    final r = widget.routine;
    id = t?.id ?? p?.id ?? b?.id ?? r?.id ?? widget.entry?.id ?? newId();
    relatedId = widget.entry?.relatedId;
    entryKind = widget.entry?.kind ?? 'note';
    title = TextEditingController(
      text:
          t?.title ??
          p?.title ??
          b?.title ??
          r?.title ??
          widget.entry?.title ??
          widget.sourceEntry?.title ??
          widget.capture?.originalText.trim() ??
          '',
    );
    notes = TextEditingController(
      text:
          t?.notes ??
          p?.description ??
          widget.entry?.body ??
          widget.sourceEntry?.body ??
          widget.capture?.originalText ??
          '',
    );
    minutes = TextEditingController(text: '${t?.minutes ?? b?.minutes ?? 25}');
    checklist = TextEditingController(
      text: t?.checklist.map((c) => c.text).join('\n') ?? '',
    );
    window = TextEditingController(text: r?.window ?? '');
    alternative = TextEditingController(text: r?.alternative ?? '');
    normal = TextEditingController(text: r?.normal ?? '');
    strong = TextEditingController(text: r?.strong ?? '');
    projectId =
        t?.projectId ??
        widget.entry?.projectId ??
        widget.sourceEntry?.projectId ??
        widget.projectId;
    final projects = widget.model.data.projects.where((p) => p.id == projectId);
    area =
        t?.area ??
        p?.area ??
        b?.area ??
        r?.area ??
        (projects.isEmpty ? 'Work' : projects.first.area);
    taskId = b?.taskId;
    deadline = t?.deadline;
    final day = widget.day ?? DateTime.now();
    start = b?.start ?? DateTime(day.year, day.month, day.day, 9);
    fixed = b?.fixed ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      title,
      notes,
      minutes,
      checklist,
      window,
      alternative,
      normal,
      strong,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2200),
  );

  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false) || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    final model = widget.model;
    Future<void> Function() operation;
    switch (widget.kind) {
      case 'task':
        final existing = widget.task?.checklist ?? <ChecklistItem>[];
        final used = <String>{};
        final steps = checklist.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((text) {
              final matches = existing.where(
                (c) => c.text == text && !used.contains(c.id),
              );
              final item = matches.isEmpty
                  ? ChecklistItem(id: newId(), text: text)
                  : matches.first;
              used.add(item.id);
              return item;
            })
            .toList();
        final t = Task(
          id: id,
          title: title.text.trim(),
          area: area,
          projectId: projectId,
          captureId:
              widget.task?.captureId ??
              widget.capture?.id ??
              widget.sourceEntry?.captureId,
          entryId: widget.task?.entryId ?? widget.sourceEntry?.id,
          deadline: deadline,
          minutes: int.parse(minutes.text),
          notes: notes.text,
          checklist: steps,
          status: widget.task?.status ?? TaskStatus.open,
        );
        operation = () => model.repository.saveTask(t);
      case 'entry':
        operation = () => model.repository.saveEntry(
          ProjectEntry(
            id: id,
            projectId: projectId!,
            title: title.text.trim(),
            body: notes.text,
            kind: entryKind,
            relatedId: relatedId,
            captureId: widget.entry?.captureId ?? widget.capture?.id,
          ),
        );
      case 'project':
        operation = () => model.repository.saveProject(
          Project(
            id: id,
            title: title.text.trim(),
            area: area,
            description: notes.text,
          ),
        );
      case 'plan':
        final block = PlanBlock(
          id: id,
          title: title.text.trim(),
          area: area,
          start: start,
          minutes: int.parse(minutes.text),
          taskId: taskId,
          fixed: fixed,
        );
        final conflicts = model.data.plans.where(
          (p) => p.id != id && p.overlaps(block),
        );
        if (conflicts.isNotEmpty) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('These times overlap'),
              content: Text(
                'This overlaps ${conflicts.map((p) => p.title).join(', ')}. Keep both blocks? Existing plans will stay where they are.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Adjust time'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Keep both'),
                ),
              ],
            ),
          );
          if (proceed != true) {
            if (mounted) setState(() => saving = false);
            return;
          }
        }
        operation = () => model.repository.savePlan(block);
      case 'routine':
        operation = () => model.repository.saveRoutine(
          Routine(
            id: id,
            title: title.text.trim(),
            area: area,
            window: window.text.trim(),
            alternative: alternative.text.trim(),
            normal: normal.text.trim(),
            strong: strong.text.trim(),
            createdDay: widget.routine?.createdDay ?? dayKey(DateTime.now()),
          ),
        );
      default:
        throw StateError('Unknown editor');
    }
    final success = await model.change(operation);
    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        saving = false;
        error =
            model.error ?? 'Please wait for the current change, then retry.';
      });
    }
  }

  Widget textInput(
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool required = false,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.multiline,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Please enter a title.';
        }
        if (number &&
            (int.tryParse(value ?? '') == null ||
                int.parse(value!) < 1 ||
                int.parse(value) > 1440)) {
          return 'Choose 1–1440 minutes.';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing =
        widget.task != null ||
        widget.project != null ||
        (widget.plan != null &&
            widget.model.data.plans.any((p) => p.id == widget.plan!.id)) ||
        widget.entry != null ||
        widget.routine != null;
    final isTask = widget.kind == 'task';
    final isPlan = widget.kind == 'plan';
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${editing ? 'Edit' : 'New'} ${widget.kind}'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: form,
              child: AbsorbPointer(
                absorbing: saving,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.capture != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Clarify the next action. Your original capture stays unchanged. No dates are inferred from your note.',
                        ),
                      ),
                    textInput(title, 'Title', required: true),
                    if (widget.kind != 'entry')
                      DropdownButtonFormField<String>(
                        key: ValueKey(area),
                        initialValue: area,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Life area',
                        ),
                        items: widget.model.data.areas
                            .map(
                              (a) => DropdownMenuItem(value: a, child: Text(a)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => area = v!),
                      ),
                    const SizedBox(height: 16),
                    if (widget.kind == 'entry') ...[
                      DropdownButtonFormField<String>(
                        initialValue: projectId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Project'),
                        validator: (v) =>
                            v == null ? 'Choose a project first.' : null,
                        items: widget.model.data.projects
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.title),
                              ),
                            )
                            .toList(),
                        onChanged: widget.entry != null
                            ? null
                            : (v) => setState(() {
                                projectId = v;
                                relatedId = null;
                              }),
                      ),
                      if (widget.model.data.projects.isEmpty)
                        const Text(
                          'Create a project from the Projects tab first.',
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: entryKind,
                        decoration: const InputDecoration(
                          labelText: 'Entry type',
                        ),
                        items: ['note', 'bug', 'idea', 'decision']
                            .map(
                              (k) => DropdownMenuItem(value: k, child: Text(k)),
                            )
                            .toList(),
                        onChanged: (v) => entryKind = v!,
                      ),
                      const SizedBox(height: 16),
                      textInput(
                        notes,
                        'Details / observations / unknowns',
                        lines: 5,
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey(projectId),
                        initialValue: relatedId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Related entry',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No related entry'),
                          ),
                          ...widget.model.data.entries
                              .where(
                                (e) => e.projectId == projectId && e.id != id,
                              )
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.id,
                                  child: Text(
                                    e.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (v) => relatedId = v == '' ? null : v,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ideas and possible causes remain hypotheses until you have evidence. An entry does not automatically create a task.',
                      ),
                    ],
                    if (isTask) ...[
                      DropdownButtonFormField<String>(
                        initialValue: projectId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Project'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('No project'),
                          ),
                          ...widget.model.data.projects.map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.title),
                            ),
                          ),
                        ],
                        onChanged: (v) => projectId = v == '' ? null : v,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final date = await pickDate(
                            deadline == null
                                ? DateTime.now()
                                : DateTime.parse(deadline!),
                          );
                          if (date != null && mounted) {
                            setState(() => deadline = dayKey(date));
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          deadline == null
                              ? 'Choose a confirmed deadline (optional)'
                              : 'Deadline: $deadline',
                        ),
                      ),
                      if (deadline != null)
                        TextButton(
                          onPressed: () => setState(() => deadline = null),
                          child: const Text('Remove deadline'),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'A deadline is a due date. Choose work time separately in Planner.',
                        ),
                      ),
                      textInput(minutes, 'Estimated minutes', number: true),
                      textInput(
                        notes,
                        'Notes / what does done look like?',
                        lines: 3,
                      ),
                      textInput(
                        checklist,
                        'Preparation checklist (one item per line)',
                        lines: 4,
                      ),
                    ],
                    if (widget.kind == 'project')
                      textInput(notes, 'Project notes / purpose', lines: 4),
                    if (isPlan) ...[
                      DropdownButtonFormField<String>(
                        initialValue: taskId ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Linked task',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Personal time / appointment'),
                          ),
                          ...widget.model.data.tasks
                              .where((t) => t.active || t.id == taskId)
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            taskId = v == '' ? null : v;
                            final t = taskId == null
                                ? null
                                : widget.model.task(taskId!);
                            if (t != null) {
                              title.text = t.title;
                              minutes.text = '${t.minutes}';
                              area = t.area;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () async {
                          final d = await pickDate(start);
                          if (d != null && mounted) {
                            setState(
                              () => start = DateTime(
                                d.year,
                                d.month,
                                d.day,
                                start.hour,
                                start.minute,
                              ),
                            );
                          }
                        },
                        child: Text('Date: ${dayKey(start)}'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (time != null && mounted) {
                            setState(
                              () => start = DateTime(
                                start.year,
                                start.month,
                                start.day,
                                time.hour,
                                time.minute,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'Start: ${TimeOfDay.fromDateTime(start).format(context)}',
                        ),
                      ),
                      const SizedBox(height: 16),
                      textInput(minutes, 'Duration in minutes', number: true),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fixed appointment'),
                        subtitle: const Text(
                          'Other plan changes never move this block.',
                        ),
                        value: fixed,
                        onChanged: (v) => setState(() => fixed = v),
                      ),
                      const Text(
                        'Times use this device’s current timezone. Saving a block does not schedule a notification.',
                      ),
                    ],
                    if (widget.kind == 'routine') ...[
                      textInput(
                        normal,
                        'Normal (optional; uses routine title if empty)',
                        lines: 2,
                      ),
                      textInput(
                        strong,
                        'Strong (optional, for example, workout 45 minutes)',
                        lines: 2,
                      ),
                      textInput(
                        window,
                        'Flexible window (for example, after lunch)',
                      ),
                      textInput(
                        alternative,
                        'Minimum (optional, for example, stretch 5 minutes)',
                        lines: 2,
                      ),
                      const Text(
                        'Repeats daily from today, following the date on this device. “Later” keeps today’s occurrence pending. No reminder is scheduled.',
                      ),
                    ],
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving ? null : save,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(saving ? 'Saving…' : 'Save ${widget.kind}'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
