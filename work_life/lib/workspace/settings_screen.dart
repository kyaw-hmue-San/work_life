import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/aimlapi_client.dart';
import '../sync/sync_models.dart';
import '../sync/workspace_sync_coordinator.dart';
import 'records.dart';
import 'onboarding_screen.dart';
import 'reminder_defaults.dart';
import 'workspace_model.dart';
import 'day_architect_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.model, this.share, this.sync});
  final WorkspaceModel model;
  final Future<ShareResult> Function(ShareParams)? share;
  final WorkspaceSyncCoordinator? sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;

  Future<void> _save(QuietHours value) async {
    await widget.model.change(
      () => widget.model.repository.saveQuietHours(value),
    );
  }

  Future<void> _saveReminderDefault(ReminderDefault value) async {
    await widget.model.change(
      () => widget.model.repository.saveReminderDefault(value),
    );
  }

  Future<void> _shareExport({
    required Future<String> Function() build,
    required String fileName,
    required String mimeType,
    required String subject,
  }) async {
    if (_exporting || widget.model.busy) return;
    setState(() => _exporting = true);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final content = await build();
      if (!mounted) return;
      await (widget.share ?? SharePlus.instance.share)(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(content)),
              mimeType: mimeType,
              name: fileName,
            ),
          ],
          fileNameOverrides: [fileName],
          subject: subject,
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create or share this file. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all local data?'),
        content: const Text(
          'This permanently removes captures, tasks, projects, planner and focus history, routines, reminders, and custom life areas in the current workspace. Settings return to defaults. Your account and sign-in remain; other workspaces are unchanged. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await widget.model.deleteLocalData();
    if (!mounted) return;
    if (success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local workspace data deleted.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not delete local data. Please retry.'),
      ),
    );
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore a backup'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Paste a Work Life JSON export',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Validate and restore'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (json == null || json.trim().isEmpty || !mounted) return;
    final ok = await widget.model.importLocalData(json);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Backup restored.'
              : (widget.model.error ?? 'Could not restore backup.'),
        ),
      ),
    );
  }

  Future<void> _pick(bool start) async {
    final quiet = widget.model.data.quietHours;
    final minute = start ? quiet.startMinute : quiet.endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (picked == null || !mounted) return;
    final selected = picked.hour * 60 + picked.minute;
    await _save(
      start
          ? quiet.copyWith(startMinute: selected)
          : quiet.copyWith(endMinute: selected),
    );
  }

  String _label(BuildContext context, int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.model,
      if (widget.sync != null) widget.sync!,
    ]),
    builder: (context, _) {
      final quiet = widget.model.data.quietHours;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: PopScope(
          canPop: !widget.model.busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              if (widget.model.busy || _exporting)
                const LinearProgressIndicator(),
              if (widget.sync case final sync?) ...[
                Text(
                  'Cloud synchronization',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(switch (sync.status.phase) {
                    SyncPhase.syncing => Icons.sync,
                    SyncPhase.synced => Icons.cloud_done_outlined,
                    SyncPhase.offline => Icons.cloud_off_outlined,
                    SyncPhase.problem => Icons.error_outline,
                    SyncPhase.idle => Icons.cloud_queue_outlined,
                  }),
                  title: Text(switch (sync.status.phase) {
                    SyncPhase.syncing => 'Syncing…',
                    SyncPhase.synced => 'Synced',
                    SyncPhase.offline => 'Offline — changes saved here',
                    SyncPhase.problem => 'Sync problem',
                    SyncPhase.idle => 'Ready to sync',
                  }),
                  subtitle: Text(
                    sync.status.message ??
                        (sync.status.pending == 0
                            ? 'Your signed-in workspace is up to date.'
                            : '${sync.status.pending} changes waiting to sync.'),
                  ),
                  trailing: sync.status.phase == SyncPhase.syncing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: 'Retry synchronization',
                          onPressed: () async {
                            await sync.retryNow();
                            await widget.model.load();
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                'AI assistance',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  AimlApiClient.environmentConfigured
                      ? Icons.auto_awesome
                      : Icons.cloud_off_outlined,
                ),
                title: Text(
                  AimlApiClient.environmentConfigured
                      ? 'AI assistance is available'
                      : 'AI assistance is not enabled',
                ),
                subtitle: const Text(
                  'Tasks, projects, Planner, Focus, routines, reminders, and Calendar continue to work without AI.',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Day Architect',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_repeat),
                title: const Text('Schedules and planning preferences'),
                subtitle: Text(
                  '${widget.model.data.recurringSchedules.length} recurring commitments · ${widget.model.data.planningPreferences.style} plan',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DayArchitectSettings(model: widget.model),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Notifications',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Quiet Hours delay normal task reminders until the end of the quiet period. Tasks and reminder times are not changed.',
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Quiet Hours'),
                subtitle: const Text(
                  'Protect this time from reminder interruptions',
                ),
                value: quiet.enabled,
                onChanged: widget.model.busy
                    ? null
                    : (enabled) => _save(quiet.copyWith(enabled: enabled)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Starts'),
                subtitle: Text(_label(context, quiet.startMinute)),
                trailing: const Icon(Icons.schedule),
                enabled: !widget.model.busy,
                onTap: () => _pick(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ends'),
                subtitle: Text(_label(context, quiet.endMinute)),
                trailing: const Icon(Icons.schedule),
                enabled: !widget.model.busy,
                onTap: () => _pick(false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Default reminder'),
                subtitle: const Text(
                  'Used when a task is first given a planned time',
                ),
                trailing: DropdownButton<ReminderDefault>(
                  value: widget.model.data.reminderDefault,
                  onChanged: widget.model.busy
                      ? null
                      : (value) {
                          if (value != null) _saveReminderDefault(value);
                        },
                  items: ReminderDefault.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(reminderDefaultLabel(value)),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Start is inclusive and end is exclusive. A period may cross midnight, such as 23:00–07:00. Equal start and end times mean no quiet period.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.waving_hand_outlined),
                title: const Text('Run setup again'),
                subtitle: const Text(
                  'Review your choices without resetting your workspace',
                ),
                enabled: !widget.model.busy && !_exporting,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (routeContext) => OnboardingScreen(
                      model: widget.model,
                      onFinished: () => Navigator.of(routeContext).pop(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Data', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Create backup'),
                subtitle: const Text(
                  'Versioned JSON for restoring Work Life later',
                ),
                enabled: !widget.model.busy && !_exporting,
                onTap: () => _shareExport(
                  build: widget.model.exportLocalData,
                  fileName: 'work_life_backup.json',
                  mimeType: 'application/json',
                  subject: 'Work Life backup',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: const Text('Export readable report'),
                subtitle: const Text(
                  'Markdown summary of projects, tasks and schedules',
                ),
                enabled: !widget.model.busy && !_exporting,
                onTap: () => _shareExport(
                  build: widget.model.exportReadableReport,
                  fileName: 'work_life_report.md',
                  mimeType: 'text/markdown',
                  subject: 'Work Life readable report',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Export tasks as CSV'),
                subtitle: const Text('Open your task list in a spreadsheet'),
                enabled: !widget.model.busy && !_exporting,
                onTap: () => _shareExport(
                  build: widget.model.exportTasksCsv,
                  fileName: 'work_life_tasks.csv',
                  mimeType: 'text/csv',
                  subject: 'Work Life tasks',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore a backup'),
                subtitle: const Text('Paste a versioned JSON export'),
                enabled: !widget.model.busy && !_exporting,
                onTap: _import,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete all local data'),
                subtitle: const Text(
                  'Reset the current workspace; keep your account',
                ),
                enabled: !widget.model.busy && !_exporting,
                onTap: _deleteLocalData,
              ),
            ],
          ),
        ),
      );
    },
  );
}
