import 'package:flutter/material.dart';

import 'records.dart';
import 'reminder_defaults.dart';
import 'workspace_model.dart';

String reminderTimeLabel(BuildContext context, DateTime instant) {
  final local = instant.toLocal();
  final labels = MaterialLocalizations.of(context);
  return '${labels.formatFullDate(local)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

class ReminderEditor extends StatefulWidget {
  const ReminderEditor({super.key, required this.model, required this.taskId});
  final WorkspaceModel model;
  final String taskId;

  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  late DateTime selected;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final existing = widget.model
        .reminderFor(widget.taskId)
        ?.scheduledAt
        .toLocal();
    final now = DateTime.now();
    final planned = widget.model.data.plans
      .where((plan) => plan.taskId == widget.taskId && plan.start.isAfter(now))
      .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final defaultTime = planned.isEmpty
      ? null
      : defaultReminderTime(
        widget.model.data.reminderDefault,
        planned.first.start,
        )?.toLocal();
    final initial = existing != null && existing.isAfter(now)
      ? existing
      : defaultTime != null && defaultTime.isAfter(now)
      ? defaultTime
      : now.add(const Duration(hours: 1));
    selected = DateTime(
      initial.year,
      initial.month,
      initial.day,
      initial.hour,
      initial.minute,
    );
  }

  Future<void> save() async {
    if (!selected.isAfter(DateTime.now())) {
      setState(() => error = 'Choose a future date and time.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final ok = await widget.model.change(
      () => widget.model.repository.saveReminder(
        TaskReminder(
          id: widget.model.reminderFor(widget.taskId)?.id ?? newId(),
          taskId: widget.taskId,
          scheduledAt: selected.toUtc(),
        ),
      ),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.model.error ?? 'Please retry saving your reminder.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Task reminder'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your reminder stays in Today. Enable device notifications in Today for a phone alert; device settings may delay it. Your deadline stays the same.',
          ),
          const SizedBox(height: 16),
          const Text('Date and time on this device'),
          Text(reminderTimeLabel(context, selected)),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final now = DateTime.now();
                    final first = DateUtils.dateOnly(now);
                    final day = await showDatePicker(
                      context: context,
                      initialDate: selected.isBefore(first) ? first : selected,
                      firstDate: first,
                      lastDate: DateTime(now.year + 100, 12, 31),
                    );
                    if (day != null && mounted) {
                      setState(() {
                        selected = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          selected.hour,
                          selected.minute,
                        );
                        error = null;
                      });
                    }
                  },
            child: const Text('Choose date'),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selected),
                    );
                    if (time != null && mounted) {
                      setState(() {
                        selected = DateTime(
                          selected.year,
                          selected.month,
                          selected.day,
                          time.hour,
                          time.minute,
                        );
                        error = null;
                      });
                    }
                  },
            child: const Text('Choose time'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save reminder'),
      ),
    ],
  );
}
