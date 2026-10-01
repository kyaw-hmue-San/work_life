import 'package:flutter/material.dart';

import 'records.dart';
import 'workspace_model.dart';

class DayArchitectSettings extends StatefulWidget {
  const DayArchitectSettings({super.key, required this.model});
  final WorkspaceModel model;
  @override
  State<DayArchitectSettings> createState() => _DayArchitectSettingsState();
}

class _DayArchitectSettingsState extends State<DayArchitectSettings> {
  PlanningPreferences get prefs => widget.model.data.planningPreferences;
  Future<void> _editPreferences() async {
    var value = prefs;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Planning preferences'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: value.style,
                  decoration: const InputDecoration(
                    labelText: 'Planning style',
                  ),
                  items: const ['balanced', 'productive', 'flexible']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setDialog(
                    () => value = PlanningPreferences(
                      wakeTime: value.wakeTime,
                      bedTime: value.bedTime,
                      transitionMinutes: value.transitionMinutes,
                      breakMinutes: value.breakMinutes,
                      exercisePeriod: value.exercisePeriod,
                      avoidFocusAfter: value.avoidFocusAfter,
                      maxFocusMinutes: value.maxFocusMinutes,
                      style: v ?? value.style,
                      breakfastWindow: value.breakfastWindow,
                      lunchWindow: value.lunchWindow,
                      dinnerWindow: value.dinnerWindow,
                    ),
                  ),
                ),
                _clock(
                  'Wake time',
                  value.wakeTime,
                  (v) => setDialog(() => value = _copy(value, wake: v)),
                ),
                _clock(
                  'Bedtime',
                  value.bedTime,
                  (v) => setDialog(() => value = _copy(value, bed: v)),
                ),
                _clock(
                  'Avoid focus after',
                  value.avoidFocusAfter,
                  (v) => setDialog(() => value = _copy(value, avoid: v)),
                ),
                DropdownButtonFormField<String>(
                  initialValue: value.exercisePeriod,
                  decoration: const InputDecoration(
                    labelText: 'Preferred exercise time',
                  ),
                  items: const ['flexible', 'morning', 'afternoon', 'evening']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => value = _copy(value, exercise: v)),
                ),
                _text(
                  'Breakfast window (HH:mm-HH:mm)',
                  value.breakfastWindow,
                  (v) => setDialog(() => value = _copy(value, breakfast: v)),
                ),
                _text(
                  'Lunch window (HH:mm-HH:mm)',
                  value.lunchWindow,
                  (v) => setDialog(() => value = _copy(value, lunch: v)),
                ),
                _text(
                  'Dinner window (HH:mm-HH:mm)',
                  value.dinnerWindow,
                  (v) => setDialog(() => value = _copy(value, dinner: v)),
                ),
                _number(
                  'Transition buffer (minutes)',
                  value.transitionMinutes,
                  (v) => setDialog(() => value = _copy(value, transition: v)),
                ),
                _number(
                  'Break duration (minutes)',
                  value.breakMinutes,
                  (v) => setDialog(() => value = _copy(value, breakM: v)),
                ),
                _number(
                  'Max focus block (minutes)',
                  value.maxFocusMinutes,
                  (v) => setDialog(() => value = _copy(value, maxFocus: v)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await widget.model.change(
                  () => widget.model.repository.savePlanningPreferences(value),
                );
                if (context.mounted) Navigator.pop(context);
                if (mounted && ok) setState(() {});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  PlanningPreferences _copy(
    PlanningPreferences p, {
    String? wake,
    String? bed,
    String? avoid,
    String? exercise,
    int? transition,
    int? breakM,
    int? maxFocus,
    String? breakfast,
    String? lunch,
    String? dinner,
  }) => PlanningPreferences(
    wakeTime: wake ?? p.wakeTime,
    bedTime: bed ?? p.bedTime,
    avoidFocusAfter: avoid ?? p.avoidFocusAfter,
    exercisePeriod: exercise ?? p.exercisePeriod,
    transitionMinutes: transition ?? p.transitionMinutes,
    breakMinutes: breakM ?? p.breakMinutes,
    maxFocusMinutes: maxFocus ?? p.maxFocusMinutes,
    style: p.style,
    breakfastWindow: breakfast ?? p.breakfastWindow,
    lunchWindow: lunch ?? p.lunchWindow,
    dinnerWindow: dinner ?? p.dinnerWindow,
  );
  Widget _text(String label, String value, ValueChanged<String> changed) =>
      TextFormField(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: changed,
      );
  Widget _number(String label, int value, ValueChanged<int> changed) =>
      TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null) changed(n);
        },
      );
  Widget _clock(
    String label,
    String value,
    ValueChanged<String> changed,
  ) => ListTile(
    title: Text(label),
    subtitle: Text(value),
    trailing: const Icon(Icons.schedule),
    onTap: () async {
      final p = value.split(':');
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
      );
      if (t != null) {
        changed(
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        );
      }
    },
  );

  Future<void> _editSchedule([RecurringSchedule? current]) async {
    final title = TextEditingController(text: current?.title ?? '');
    final location = TextEditingController(text: current?.location ?? '');
    var weekday = current?.weekday ?? DateTime.monday;
    var start = current?.startTime ?? '09:00';
    var end = current?.endTime ?? '10:00';
    var from = current?.startDate ?? dayKey(DateTime.now());
    var through = current?.endDate;
    var type = current?.type ?? RecurringScheduleType.classSession;
    var fixed = current?.fixed ?? true;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(
            current == null
                ? 'Add recurring commitment'
                : 'Edit recurring commitment',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                  ),
                ),
                DropdownButtonFormField<RecurringScheduleType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: RecurringScheduleType.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_typeLabel(v)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => type = v ?? type),
                ),
                DropdownButtonFormField<int>(
                  initialValue: weekday,
                  decoration: const InputDecoration(labelText: 'Repeats every'),
                  items: List.generate(
                    7,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        [
                          'Monday',
                          'Tuesday',
                          'Wednesday',
                          'Thursday',
                          'Friday',
                          'Saturday',
                          'Sunday',
                        ][i],
                      ),
                    ),
                  ),
                  onChanged: (v) => setDialog(() => weekday = v ?? weekday),
                ),
                _clock('Starts', start, (v) => setDialog(() => start = v)),
                _clock('Ends', end, (v) => setDialog(() => end = v)),
                SwitchListTile.adaptive(
                  title: const Text('Treat as fixed'),
                  subtitle: const Text('AI will plan around this time'),
                  value: fixed,
                  onChanged: (v) => setDialog(() => fixed = v),
                ),
                ListTile(
                  title: const Text('First date'),
                  subtitle: Text(from),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(from),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (d != null) setDialog(() => from = dayKey(d));
                  },
                ),
                ListTile(
                  title: const Text('Last date (optional)'),
                  subtitle: Text(through ?? 'No end date'),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(through ?? from) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (d != null) setDialog(() => through = dayKey(d));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                final value = RecurringSchedule(
                  id: current?.id ?? newId(),
                  title: title.text.trim(),
                  type: type,
                  weekday: weekday,
                  startTime: start,
                  endTime: end,
                  startDate: from,
                  endDate: through,
                  location: location.text.trim(),
                  fixed: fixed,
                );
                final ok = await widget.model.change(
                  () => widget.model.repository.saveRecurringSchedule(value),
                );
                if (context.mounted) Navigator.pop(context);
                if (mounted && ok) setState(() {});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    location.dispose();
  }

  String _typeLabel(RecurringScheduleType type) => switch (type) {
    RecurringScheduleType.classSession => 'Class',
    RecurringScheduleType.work => 'Work',
    RecurringScheduleType.meeting => 'Meeting',
    RecurringScheduleType.commitment => 'Regular commitment',
    RecurringScheduleType.other => 'Other',
  };

  Future<void> _exception(RecurringSchedule item) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (date == null || !mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change this occurrence'),
        content: Text(
          'What should happen to ${item.title} on ${dayKey(date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, null),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: const Text('Cancel occurrence'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'move'),
            child: const Text('Move to another date'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'time'),
            child: const Text('Change time'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'cancel') {
      await widget.model.change(
        () => widget.model.repository.saveScheduleException(
          ScheduleException(scheduleId: item.id, day: dayKey(date)),
        ),
      );
    } else if (action == 'move') {
      final target = await showDatePicker(
        context: context,
        initialDate: calendarDay(date, 1),
        firstDate: DateTime(2000),
        lastDate: DateTime(2200),
      );
      if (target == null || dayKey(target) == dayKey(date)) return;
      await widget.model.change(
        () => widget.model.repository.saveScheduleException(
          ScheduleException(
            scheduleId: item.id,
            day: dayKey(date),
            cancelled: false,
            movedToDate: dayKey(target),
          ),
        ),
      );
    } else {
      final parts = item.startTime.split(':');
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ),
      );
      if (t == null) return;
      final dur =
          DateTime(
            2000,
            1,
            1,
            int.parse(item.endTime.split(':')[0]),
            int.parse(item.endTime.split(':')[1]),
          ).difference(
            DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1])),
          );
      final e = TimeOfDay.fromDateTime(
        DateTime(2000, 1, 1, t.hour, t.minute).add(dur),
      );
      await widget.model.change(
        () => widget.model.repository.saveScheduleException(
          ScheduleException(
            scheduleId: item.id,
            day: dayKey(date),
            cancelled: false,
            startTime:
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
            endTime:
                '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}',
          ),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Day Architect')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune),
            title: Text('Planning preferences · ${prefs.style}'),
            subtitle: Text(
              'Wake ${prefs.wakeTime} · bed ${prefs.bedTime} · focus until ${prefs.avoidFocusAfter}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editPreferences,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Recurring commitments',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Classes and regular commitments are reused automatically in future plans.',
        ),
        for (final item in widget.model.data.recurringSchedules)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_repeat),
              title: Text(item.title),
              subtitle: Text(
                '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][item.weekday - 1]} · ${item.startTime}–${item.endTime}${item.endDate == null ? '' : ' · through ${item.endDate}'}',
              ),
              onTap: () => _editSchedule(item),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') await _editSchedule(item);
                  if (v == 'exception') await _exception(item);
                  if (v == 'delete') {
                    await widget.model.change(
                      () => widget.model.repository.removeRecurringSchedule(
                        item.id,
                      ),
                    );
                    if (mounted) setState(() {});
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'exception',
                    child: Text('Change one date'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Remove series')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _editSchedule(),
          icon: const Icon(Icons.add),
          label: const Text('Add recurring commitment'),
        ),
      ],
    ),
  );
}
