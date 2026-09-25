import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'records.dart';
import 'onboarding_screen.dart';
import 'reminder_defaults.dart';
import 'workspace_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.model, this.share});
  final WorkspaceModel model;
  final Future<ShareResult> Function(ShareParams)? share;

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

  Future<void> _export() async {
    if (_exporting || widget.model.busy) return;
    setState(() => _exporting = true);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final json = await widget.model.exportLocalData();
      if (!mounted) return;
      await (widget.share ?? SharePlus.instance.share)(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(json)),
              mimeType: 'application/json',
              name: 'work_life_export.json',
            ),
          ],
          fileNameOverrides: const ['work_life_export.json'],
          subject: 'Work Life data export',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not create or share the data export. Please retry.',
          ),
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
    listenable: widget.model,
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
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Export my data'),
                subtitle: const Text('Share a versioned JSON export'),
                enabled: !widget.model.busy && !_exporting,
                onTap: _export,
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
