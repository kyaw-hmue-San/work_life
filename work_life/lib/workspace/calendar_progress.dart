import 'package:flutter/material.dart';

import 'records.dart';

class DailyTaskProgress {
  const DailyTaskProgress({required this.tasks});
  final List<Task> tasks;

  int get completed =>
      tasks.where((task) => task.status == TaskStatus.completed).length;
  int get total => tasks.length;
  double get fraction => total == 0 ? 0 : completed / total;
}

class CalendarProgress {
  const CalendarProgress(this.data);
  final WorkspaceData data;

  DailyTaskProgress forDay(DateTime day) {
    final key = dayKey(day);
    final ids = <String>{};
    for (final plan in data.plans) {
      if (plan.taskId != null && plan.occursOn(day)) ids.add(plan.taskId!);
    }
    for (final task in data.tasks) {
      if (task.deadline == key) ids.add(task.id);
    }
    final tasks = data.tasks
        .where(
          (task) =>
              ids.contains(task.id) && task.status != TaskStatus.cancelled,
        )
        .toList();
    return DailyTaskProgress(tasks: tasks);
  }

  Map<String, DailyTaskProgress> forRange(DateTime start, int days) {
    final keys = <String>{
      for (var index = 0; index < days; index++)
        dayKey(calendarDay(start, index)),
    };
    final idsByDay = <String, Set<String>>{
      for (final key in keys) key: <String>{},
    };
    for (final task in data.tasks) {
      final deadline = task.deadline;
      if (deadline != null && keys.contains(deadline)) {
        idsByDay[deadline]!.add(task.id);
      }
    }
    for (final plan in data.plans) {
      final taskId = plan.taskId;
      if (taskId == null) continue;
      var cursor = DateUtils.dateOnly(plan.start);
      final last = DateUtils.dateOnly(
        plan.end.subtract(const Duration(microseconds: 1)),
      );
      while (!cursor.isAfter(last)) {
        final key = dayKey(cursor);
        if (keys.contains(key)) idsByDay[key]!.add(taskId);
        cursor = calendarDay(cursor, 1);
      }
    }
    final taskById = {for (final task in data.tasks) task.id: task};
    return {
      for (final entry in idsByDay.entries)
        entry.key: DailyTaskProgress(
          tasks: entry.value
              .map((id) => taskById[id])
              .whereType<Task>()
              .where((task) => task.status != TaskStatus.cancelled)
              .toList(),
        ),
    };
  }
}

class WorkLifeCalendar extends StatelessWidget {
  const WorkLifeCalendar({
    super.key,
    required this.data,
    required this.selectedDay,
    required this.onSelected,
  });

  final WorkspaceData data;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(selectedDay.year, selectedDay.month);
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday - DateTime.monday),
    );
    final progress = CalendarProgress(data).forRange(gridStart, 42);
    final labels = MaterialLocalizations.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => onSelected(
                    DateTime(selectedDay.year, selectedDay.month - 1, 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    labels.formatMonthYear(selectedDay),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => onSelected(
                    DateTime(selectedDay.year, selectedDay.month + 1, 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final day in [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ])
                  Expanded(
                    child: Center(
                      child: Text(day, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var week = 0; week < 6; week++)
              Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: _CalendarDay(
                        day: calendarDay(gridStart, week * 7 + weekday),
                        displayedMonth: selectedDay.month,
                        selected:
                            dayKey(
                              calendarDay(gridStart, week * 7 + weekday),
                            ) ==
                            dayKey(selectedDay),
                        progress:
                            progress[dayKey(
                              calendarDay(gridStart, week * 7 + weekday),
                            )] ??
                            const DailyTaskProgress(tasks: []),
                        onTap: onSelected,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.displayedMonth,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final DateTime day;
  final int displayedMonth;
  final bool selected;
  final DailyTaskProgress progress;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = dayKey(today) == dayKey(day);
    final colors = Theme.of(context).colorScheme;
    final percentage = (progress.fraction * 100).round();
    final label = MaterialLocalizations.of(context).formatFullDate(day);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label. ${progress.total} tasks. ${progress.completed} completed. $percentage percent complete.${isToday ? ' Today.' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => onTap(day),
        child: SizedBox(
          height: 48,
          child: Center(
            child: SizedBox.square(
              dimension: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (progress.total > 0)
                    SizedBox.square(
                      dimension: 38,
                      child: CircularProgressIndicator(
                        value: progress.fraction,
                        strokeWidth: 3,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? colors.primary : null,
                      border: isToday && !selected
                          ? Border.all(color: colors.primary, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: selected
                            ? colors.onPrimary
                            : day.month == displayedMonth
                            ? colors.onSurface
                            : colors.onSurfaceVariant.withValues(alpha: 0.45),
                        fontWeight: isToday || selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (progress.total > 0 &&
                      progress.completed == progress.total)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Icon(
                        Icons.check_circle,
                        size: 12,
                        color: colors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
