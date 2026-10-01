import 'package:flutter/material.dart';

import '../workspace/records.dart';
import '../workspace/workspace_model.dart';
import 'aimlapi_client.dart';
import 'ai_proposals.dart';

class AiScheduleProposalScreen extends StatefulWidget {
  const AiScheduleProposalScreen({
    super.key,
    required this.model,
    required this.proposal,
    this.title = 'Review your proposed plan',
    this.onRegenerate,
    this.onAdjust,
    this.showRecurringSave = false,
    this.weekStart,
  });

  final WorkspaceModel model;
  final AiScheduleProposal proposal;
  final String title;
  final Future<AiScheduleProposal> Function()? onRegenerate;
  final Future<AiScheduleProposal> Function(String adjustment)? onAdjust;
  final bool showRecurringSave;
  final DateTime? weekStart;
  bool get isWeekly => weekStart != null;

  @override
  State<AiScheduleProposalScreen> createState() =>
      _AiScheduleProposalScreenState();
}

class _AiScheduleProposalScreenState extends State<AiScheduleProposalScreen> {
  late AiScheduleProposal proposal = widget.proposal;
  late List<TextEditingController> titles;
  final operationId = newId();
  bool saving = false;
  bool regenerating = false;
  final adjustment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _makeControllers();
  }

  void _makeControllers() {
    titles = proposal.events
        .map((event) => TextEditingController(text: event.title))
        .toList();
  }

  void _disposeControllers() {
    for (final controller in titles) {
      controller.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    adjustment.dispose();
    super.dispose();
  }

  DateTime _date(AiScheduleEvent event) =>
      DateTime.tryParse(event.date ?? '') ?? DateTime.now();

  TimeOfDay _time(String? value, {required TimeOfDay fallback}) {
    final parts = value?.split(':');
    if (parts?.length != 2) return fallback;
    return TimeOfDay(
      hour: int.tryParse(parts![0]) ?? fallback.hour,
      minute: int.tryParse(parts[1]) ?? fallback.minute,
    );
  }

  String _clock(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate(AiScheduleEvent event) async {
    final first = widget.weekStart == null
        ? DateTime(2000)
        : DateUtils.dateOnly(widget.weekStart!);
    final last = widget.weekStart == null
        ? DateTime(2200)
        : calendarDay(first, 6);
    final parsed = _date(event);
    final initial = parsed.isBefore(first) || parsed.isAfter(last)
        ? first
        : parsed;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (value != null && mounted) {
      setState(() => event.date = dayKey(value));
    }
  }

  Future<void> _pickTime(AiScheduleEvent event, {required bool end}) async {
    final fallback = end
        ? const TimeOfDay(hour: 10, minute: 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final value = await showTimePicker(
      context: context,
      initialTime: _time(end ? event.end : event.start, fallback: fallback),
    );
    if (value != null && mounted) {
      setState(() {
        if (end) {
          event.end = _clock(value);
        } else {
          event.start = _clock(value);
        }
      });
    }
  }

  void _move(int index, int direction) {
    final target = index + direction;
    if (target < 0 || target >= proposal.events.length) return;
    setState(() {
      final event = proposal.events.removeAt(index);
      final controller = titles.removeAt(index);
      proposal.events.insert(target, event);
      titles.insert(target, controller);
    });
  }

  void _add() {
    setState(() {
      final now = widget.weekStart ?? DateTime.now();
      proposal.events.add(
        AiScheduleEvent(
          title: '',
          date: dayKey(now),
          start: '09:00',
          end: '09:25',
          area: 'Work',
        ),
      );
      titles.add(TextEditingController());
    });
  }

  Future<void> _approve() async {
    if (saving) return;
    for (var index = 0; index < proposal.events.length; index++) {
      proposal.events[index].title = titles[index].text.trim();
    }
    final chosen = proposal.events.where((event) => event.included);
    if (chosen.isEmpty ||
        chosen.any(
          (event) =>
              event.title.isEmpty || event.date == null || event.start == null,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every selected block needs a title, date and time.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    final ok = await widget.model.change(
      () => widget.model.repository.applyScheduleProposal(
        proposal,
        operationId: operationId,
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => saving = false);
      if (widget.model.lastFailure is StaleScheduleProposalException) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Your schedule changed'),
            content: const Text(
              'This plan was created from an older version of your schedule. Review an updated plan before applying these changes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              if (widget.onRegenerate != null)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _regenerate();
                  },
                  child: const Text('Regenerate'),
                ),
            ],
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.model.error ??
                'The plan could not be applied. Your Planner was not changed.',
          ),
        ),
      );
    }
  }

  Future<void> _regenerate() async {
    final action = widget.onRegenerate;
    if (action == null || regenerating) return;
    setState(() => regenerating = true);
    try {
      for (var index = 0; index < proposal.events.length; index++) {
        proposal.events[index].title = titles[index].text.trim();
      }
      final locked = proposal.events
          .where((event) => event.locked && event.included)
          .toList();
      final replacement =
          widget.isWeekly && widget.onAdjust != null && locked.isNotEmpty
          ? await widget.onAdjust!(
              'Regenerate the week but keep these locked blocks exactly unchanged: ${locked.map((event) => '${event.title} on ${event.date} ${event.start}-${event.end}').join('; ')}.',
            )
          : await action();
      if (!mounted) return;
      _disposeControllers();
      setState(() {
        proposal = replacement;
        _makeControllers();
      });
    } catch (error) {
      if (mounted) {
        final message = error is AiServiceException
            ? error.message
            : error is FormatException
            ? 'AI returned an incomplete schedule. Add exact dates or availability and try again.'
            : 'Couldn’t rebuild the plan.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message Your current proposal is unchanged.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => regenerating = false);
    }
  }

  Future<void> _adjust() async {
    final action = widget.onAdjust;
    if (action == null || adjustment.text.trim().isEmpty || regenerating) {
      return;
    }
    setState(() => regenerating = true);
    try {
      final replacement = await action(adjustment.text.trim());
      if (!mounted) return;
      _disposeControllers();
      setState(() {
        proposal = replacement;
        _makeControllers();
        adjustment.clear();
      });
    } catch (error) {
      if (mounted) {
        final message = error is AiServiceException
            ? error.message
            : error is FormatException
            ? 'AI returned an incomplete adjustment. Include exact days or times and retry.'
            : 'Couldn’t adjust this proposal.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$message Nothing was changed.')),
        );
      }
    } finally {
      if (mounted) setState(() => regenerating = false);
    }
  }

  Future<void> _saveRecurring() async {
    final events = proposal.events.where((event) => event.included).toList();
    if (events.isEmpty ||
        events.any(
          (event) =>
              event.title.trim().isEmpty ||
              event.weekday == null ||
              event.start == null ||
              event.end == null,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Check each selected title, weekday and time before saving a weekly schedule.',
          ),
        ),
      );
      return;
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
      initialDateRange: DateTimeRange(
        start: DateTime.now(),
        end: calendarDay(DateTime.now(), 90),
      ),
    );
    if (range == null || !mounted) return;
    final schedules = events
        .map(
          (event) => RecurringSchedule(
            id: newId(),
            title: event.title.trim(),
            type: _recurringType(event.kind),
            weekday: event.weekday!,
            startTime: event.start!,
            endTime: event.end!,
            startDate: dayKey(range.start),
            endDate: dayKey(range.end),
            notes: event.notes,
            fixed: true,
          ),
        )
        .toList();
    setState(() => saving = true);
    final ok = await widget.model.change(
      () => widget.model.repository.saveRecurringSchedules(schedules),
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weekly schedule saved. You can edit it in Settings.'),
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.model.error ?? 'The weekly schedule was not saved.',
          ),
        ),
      );
    }
  }

  RecurringScheduleType _recurringType(String value) {
    for (final type in RecurringScheduleType.values) {
      if (type.name == value ||
          (value == 'class' && type == RecurringScheduleType.classSession)) {
        return type;
      }
    }
    return RecurringScheduleType.classSession;
  }

  String _recurringTypeLabel(RecurringScheduleType value) => switch (value) {
    RecurringScheduleType.classSession => 'Class',
    RecurringScheduleType.work => 'Work',
    RecurringScheduleType.meeting => 'Meeting',
    RecurringScheduleType.commitment => 'Regular commitment',
    RecurringScheduleType.other => 'Other',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(
                widget.isWeekly ? 'Suggested week' : 'Suggested schedule',
              ),
              subtitle: Text(
                widget.isWeekly
                    ? '${proposal.events.where((event) => event.included).length} selected blocks across seven days. Review, edit, lock or exclude each one before approval.'
                    : 'Review every block. Nothing is added to Planner until you approve.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.isWeekly) ...[
            _weeklySummary(context),
            const SizedBox(height: 12),
          ],
          if (widget.onAdjust != null) ...[
            TextField(
              controller: adjustment,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Answer questions or adjust this plan',
                hintText:
                    'Move exercise earlier; keep everything else the same',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: regenerating ? null : _adjust,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Suggest adjustment'),
              ),
            ),
          ],
          if (widget.showRecurringSave) ...[
            OutlinedButton.icon(
              onPressed: saving ? null : _saveRecurring,
              icon: const Icon(Icons.event_repeat),
              label: const Text('Save as a recurring weekly schedule'),
            ),
            const SizedBox(height: 8),
          ],
          ..._proposalCards(context),
          OutlinedButton.icon(
            onPressed: saving ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Add time block'),
          ),
          if (proposal.questions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Things to confirm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final question in proposal.questions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: Text(question),
              ),
          ],
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          if (widget.onRegenerate != null)
            OutlinedButton.icon(
              onPressed: saving || regenerating ? null : _regenerate,
              icon: const Icon(Icons.refresh),
              label: Text(
                regenerating
                    ? 'Rebuilding…'
                    : widget.isWeekly
                    ? 'Regenerate week'
                    : 'Regenerate',
              ),
            ),
          FilledButton.icon(
            onPressed: saving ? null : _approve,
            icon: const Icon(Icons.check),
            label: Text(
              saving
                  ? 'Applying…'
                  : widget.isWeekly
                  ? 'Apply selected week'
                  : 'Apply this plan',
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _proposalCards(BuildContext context) {
    if (!widget.isWeekly) {
      return [
        for (var index = 0; index < proposal.events.length; index++)
          _eventCard(index),
      ];
    }
    final widgets = <Widget>[];
    final monday = DateUtils.dateOnly(widget.weekStart!);
    for (var offset = 0; offset < 7; offset++) {
      final date = calendarDay(monday, offset);
      final key = dayKey(date);
      final indices =
          <int>[
            for (var index = 0; index < proposal.events.length; index++)
              if (proposal.events[index].date == key) index,
          ]..sort((a, b) {
            final left = proposal.events[a].start ?? '';
            final right = proposal.events[b].start ?? '';
            return left.compareTo(right);
          });
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatFullDate(date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${indices.where((index) => proposal.events[index].included).length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              IconButton(
                tooltip:
                    indices
                        .where(
                          (index) => !_isHardLocked(proposal.events[index]),
                        )
                        .every((index) => proposal.events[index].locked)
                    ? 'Unlock flexible blocks on this day'
                    : 'Lock selected blocks on this day',
                onPressed: indices.isEmpty
                    ? null
                    : () {
                        final flexible = indices
                            .where(
                              (index) => !_isHardLocked(proposal.events[index]),
                            )
                            .toList();
                        if (flexible.isEmpty) return;
                        final lock = !flexible.every(
                          (index) => proposal.events[index].locked,
                        );
                        setState(() {
                          for (final index in flexible) {
                            if (proposal.events[index].included) {
                              proposal.events[index].locked = lock;
                            }
                          }
                        });
                      },
                icon: const Icon(Icons.lock_outline),
              ),
            ],
          ),
        ),
      );
      if (indices.isEmpty) {
        widgets.add(
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.spa_outlined),
              title: Text('Intentional open time'),
              subtitle: Text('No block is proposed for this day.'),
            ),
          ),
        );
      } else {
        widgets.addAll(indices.map(_eventCard));
      }
    }
    final weekKeys = {
      for (var offset = 0; offset < 7; offset++)
        dayKey(calendarDay(monday, offset)),
    };
    final needsReview = <int>[
      for (var index = 0; index < proposal.events.length; index++)
        if (!weekKeys.contains(proposal.events[index].date)) index,
    ];
    if (needsReview.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            'Needs a date in this week',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
      widgets.addAll(needsReview.map(_eventCard));
    }
    return widgets;
  }

  bool _isHardLocked(AiScheduleEvent event) {
    if (event.recurringScheduleId != null) return true;
    return widget.model.data.plans.any(
      (plan) => plan.id == event.planId && plan.fixed,
    );
  }

  Widget _weeklySummary(BuildContext context) {
    final selected = proposal.events.where((event) => event.included).toList();
    final work = selected
        .where((event) => {'task', 'focus'}.contains(event.kind))
        .length;
    final life = selected
        .where(
          (event) => {
            'exercise',
            'meal',
            'break',
            'coffee',
            'personal',
            'free_time',
          }.contains(event.kind),
        )
        .length;
    final locked = selected.where((event) => event.locked).length;
    final usedDays = selected
        .map((event) => event.date)
        .whereType<String>()
        .toSet();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Week at a glance',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$work work blocks')),
                Chip(label: Text('$life life blocks')),
                Chip(label: Text('$locked locked')),
                Chip(label: Text('${7 - usedDays.length} open days')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(int index) {
    final event = proposal.events[index];
    PlanBlock? existingPlan;
    for (final plan in widget.model.data.plans) {
      if (plan.id == event.planId) {
        existingPlan = plan;
        break;
      }
    }
    final linkedTask = event.taskId == null
        ? null
        : widget.model.task(event.taskId!);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: event.included,
              onChanged: saving || event.locked
                  ? null
                  : (value) => setState(() => event.included = value ?? false),
              title: TextField(
                controller: titles[index],
                enabled: !saving && !event.locked,
                decoration: const InputDecoration(labelText: 'Block title'),
              ),
              subtitle: linkedTask == null
                  ? null
                  : Text('Linked task · ${linkedTask.title}'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: [
                  Chip(label: Text(event.operation.toUpperCase())),
                  Chip(label: Text(event.kind.replaceAll('_', ' '))),
                  if (event.locked)
                    const Chip(
                      avatar: Icon(Icons.lock_outline, size: 16),
                      label: Text('Locked'),
                    ),
                ],
              ),
            ),
            if (widget.showRecurringSave)
              DropdownButtonFormField<RecurringScheduleType>(
                initialValue: _recurringType(event.kind),
                decoration: const InputDecoration(labelText: 'Commitment type'),
                items: RecurringScheduleType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_recurringTypeLabel(type)),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(
                        () => event.kind = value?.name ?? event.kind,
                      ),
              ),
            if (widget.showRecurringSave)
              DropdownButtonFormField<int?>(
                initialValue: event.weekday,
                decoration: const InputDecoration(labelText: 'Repeats on'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Choose weekday'),
                  ),
                  ...List.generate(
                    7,
                    (index) => DropdownMenuItem<int?>(
                      value: index + 1,
                      child: Text(
                        [
                          'Monday',
                          'Tuesday',
                          'Wednesday',
                          'Thursday',
                          'Friday',
                          'Saturday',
                          'Sunday',
                        ][index],
                      ),
                    ),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => event.weekday = value),
              ),
            if (event.recurringScheduleId == null &&
                existingPlan?.fixed != true &&
                event.operation != 'remove' &&
                event.operation != 'unchanged')
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep fixed in future plans'),
                subtitle: const Text(
                  'Regeneration will treat this as a commitment',
                ),
                value: event.locked,
                onChanged: saving
                    ? null
                    : (value) => setState(() => event.locked = value),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: event.taskId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Linked task'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Personal time / no task'),
                ),
                ...widget.model.data.tasks
                    .where((task) => task.active)
                    .map(
                      (task) => DropdownMenuItem(
                        value: task.id,
                        child: Text(
                          task.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() {
                      event.taskId = value == null || value.isEmpty
                          ? null
                          : value;
                      final task = event.taskId == null
                          ? null
                          : widget.model.task(event.taskId!);
                      if (task != null) event.area = task.area;
                    }),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: saving ? null : () => _pickDate(event),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(event.date ?? 'Choose date'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : () => _pickTime(event, end: false),
                  icon: const Icon(Icons.schedule),
                  label: Text('Start ${event.start ?? '—'}'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : () => _pickTime(event, end: true),
                  icon: const Icon(Icons.timelapse),
                  label: Text('End ${event.end ?? '—'}'),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Move earlier',
                  onPressed: saving || index == 0
                      ? null
                      : () => _move(index, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Move later',
                  onPressed: saving || index == proposal.events.length - 1
                      ? null
                      : () => _move(index, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Remove block',
                  onPressed: saving
                      ? null
                      : () => setState(() => event.included = false),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
