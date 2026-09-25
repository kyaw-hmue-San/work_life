import 'package:flutter/material.dart';

import 'records.dart';
import 'reminder_defaults.dart';
import 'workspace_model.dart';

/// First-run editing of the same records used by Settings and Life Map.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.model, this.onFinished});
  final WorkspaceModel model;
  final VoidCallback? onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  late ReminderDefault reminder = widget.model.data.reminderDefault;
  final area = TextEditingController();

  @override
  void dispose() {
    area.dispose();
    super.dispose();
  }

  Future<void> finish({bool skip = false}) async {
    final saved = await widget.model.change(
      () => widget.model.repository.completeOnboarding(
        reminderDefault: skip ? null : reminder,
      ),
    );
    if (saved && mounted) widget.onFinished?.call();
  }

  Future<void> addArea() async {
    if (area.text.trim().isEmpty) return;
    if (await widget.model.change(
      () => widget.model.repository.addArea(area.text),
    )) {
      if (mounted) area.clear();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.model,
    builder: (context, _) {
      final busy = widget.model.busy;
      return PopScope(
        canPop: widget.onFinished != null && step == 0 && !busy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !busy && step > 0) setState(() => step--);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text('${step + 1} of 3'),
            leading: step == 0
                ? null
                : IconButton(
                    tooltip: 'Back',
                    onPressed: busy ? null : () => setState(() => step--),
                    icon: const Icon(Icons.arrow_back),
                  ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  key: ValueKey(step),
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    Text(
                      [
                        'Welcome to Work Life',
                        'Make room for your life',
                        'Reminders that suit you',
                      ][step],
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    if (step == 0)
                      const Text(
                        'Capture what matters. Plan realistically. Focus on one thing. Make room for work, relationships, and rest.\n\nYour workspace works offline. You can adjust your choices later.',
                      ),
                    if (step == 1) ...[
                      const Text(
                        'These life areas are always available. Use only the ones that matter to you when organizing tasks and projects. You can add your own here or later in Life Map.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.model.data.areas
                            .map((name) => Chip(label: Text(name)))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: area,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Custom life area (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: busy ? null : addArea,
                        child: const Text('Add life area'),
                      ),
                    ],
                    if (step == 2) ...[
                      const Text(
                        'Choose a default for tasks you give a planned time. Existing reminders stay as they are. Change this later in Settings.\n\nPhone alerts require notification permission, which you can enable later from Today.',
                      ),
                      const SizedBox(height: 16),
                      ...ReminderDefault.values.map(
                        (value) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(reminderDefaultLabel(value)),
                          value: reminder == value,
                          onChanged: busy
                              ? null
                              : (_) => setState(() => reminder = value),
                        ),
                      ),
                    ],
                    if (widget.model.error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.model.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (step == 2) {
                                finish();
                              } else {
                                setState(() => step++);
                              }
                            },
                      child: Text(
                        step == 0
                            ? 'Get Started'
                            : step == 2
                            ? 'Start using Work Life'
                            : 'Continue',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => finish(skip: true),
                      child: const Text('Skip setup'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
