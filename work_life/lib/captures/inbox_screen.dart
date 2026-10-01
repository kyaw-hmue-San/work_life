import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'capture.dart';
import 'capture_repository.dart';
import 'inbox_model.dart';
import '../ai/capture_assistant.dart';
import '../ai/aimlapi_client.dart';
import '../ai/ai_schedule_screen.dart';
import '../workspace/workspace_model.dart';

typedef ScheduleImagePicker = Future<XFile?> Function();
typedef ScheduleAiClientFactory = AimlApiClient Function();

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.repository,
    this.onOpenCapture,
    this.workspaceModel,
    this.onLocalChange,
    this.scheduleImagePicker,
    this.scheduleAiClientFactory,
  });
  final CaptureRepository repository;
  final ValueChanged<Capture>? onOpenCapture;
  final WorkspaceModel? workspaceModel;
  final Future<void> Function()? onLocalChange;
  final ScheduleImagePicker? scheduleImagePicker;
  final ScheduleAiClientFactory? scheduleAiClientFactory;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final InboxModel model;
  final draft = TextEditingController();
  final search = TextEditingController();
  final assistant = const CaptureAssistant();
  bool importingSchedule = false;

  @override
  void initState() {
    super.initState();
    model = InboxModel(widget.repository)..load();
  }

  @override
  void dispose() {
    model.dispose();
    draft.dispose();
    search.dispose();
    super.dispose();
  }

  String dateLabel(Capture capture) {
    final local = capture.createdAt.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatMediumDate(local)} · ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Future<void> save() async {
    final saved = await model.save(draft.text);
    if (!mounted || !saved) return;
    draft.clear();
    search.clear();
    FocusScope.of(context).unfocus();
    final callback = widget.onLocalChange;
    if (callback != null) unawaited(callback());
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved on this device')));
  }

  Future<void> importScheduleImage() async {
    if (importingSchedule) return;
    setState(() => importingSchedule = true);
    final selectionTimer = Stopwatch()..start();
    XFile? image;
    try {
      image =
          await (widget.scheduleImagePicker?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 88,
              ));
    } catch (_) {
      if (mounted) {
        setState(() => importingSchedule = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t open that image. Check photo access and try again.',
            ),
          ),
        );
      }
      return;
    }
    if (image == null || !mounted) {
      if (mounted) setState(() => importingSchedule = false);
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[WORK_LIFE_IMPORT] image selected and preprocessed in ${selectionTimer.elapsedMilliseconds}ms',
      );
    }
    final client = widget.scheduleAiClientFactory?.call() ?? AimlApiClient();
    var dialogOpen = false, cancelled = false;
    void cancel() {
      cancelled = true;
      dialogOpen = false;
      client.dispose();
    }

    if (!client.configured) {
      client.dispose();
      if (!mounted) return;
      setState(() => importingSchedule = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI schedule import is not enabled in this build.'),
        ),
      );
      return;
    }
    dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ScheduleImportProgressDialog(
          onCancel: () {
            cancel();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    try {
      final readTimer = Stopwatch()..start();
      final bytes = await image.readAsBytes();
      if (kDebugMode) {
        debugPrint(
          '[WORK_LIFE_IMPORT] read ${bytes.length} bytes in ${readTimer.elapsedMilliseconds}ms',
        );
      }
      if (cancelled) return;
      final result = await client.analyzeScheduleImage(bytes);
      if (!mounted || cancelled) return;
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      final workspace = widget.workspaceModel;
      if (workspace == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open schedule import from the Work Life workspace.'),
          ),
        );
        return;
      }
      await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AiScheduleProposalScreen(
            model: workspace,
            proposal: result,
            title: 'Review imported schedule',
            showRecurringSave: true,
          ),
        ),
      );
    } catch (error) {
      if (mounted && !cancelled) {
        if (dialogOpen) {
          dialogOpen = false;
          Navigator.of(context, rootNavigator: true).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${error is AiServiceException ? error.message : 'AI could not read that schedule image.'} Your image and existing data are safe.',
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: importScheduleImage,
            ),
          ),
        );
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => importingSchedule = false);
    }
  }

  void openCapture(Capture capture) {
    if (widget.onOpenCapture != null) {
      widget.onOpenCapture!(capture);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Your capture')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ORIGINAL NOTE',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(dateLabel(capture)),
                  const SizedBox(height: 24),
                  SelectableText(
                    capture.originalText,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Saved on this device. Your original words are kept as written.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, draft, search]),
    builder: (context, _) {
      final query = search.text.trim().toLowerCase();
      final items = model.captures
          .where((item) => item.originalText.toLowerCase().contains(query))
          .toList();
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Work Life'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 20),
              child: Icon(Icons.spa_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  Text(
                    widget.onOpenCapture == null
                        ? 'A little more\nroom to breathe.'
                        : 'Inbox',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.onOpenCapture == null
                        ? 'A place for your work, your ideas, and the life around them.'
                        : 'Capture now. Make sense of it when you have room.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Get it off your mind',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: draft,
                    readOnly: model.saving,
                    minLines: 3,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What’s on your mind?',
                      hintText:
                          'An idea, a commitment, or something just for you…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (assistant.suggest(draft.text) case final suggestion?)
                    Card(
                      elevation: 0,
                      color: theme.colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text('Quick suggestion · ${suggestion.kind}'),
                        subtitle: Text(suggestion.prompt),
                      ),
                    ),
                  if (assistant.suggest(draft.text) != null)
                    const SizedBox(height: 8),
                  if (model.saveError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          model.saveError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        model.saving ||
                            model.loading ||
                            model.loadError != null ||
                            draft.text.trim().isEmpty
                        ? null
                        : save,
                    icon: Icon(model.saving ? Icons.hourglass_top : Icons.add),
                    label: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(model.saving ? 'Saving…' : 'Save capture'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: model.saving || importingSchedule
                        ? null
                        : importScheduleImage,
                    icon: Icon(
                      importingSchedule
                          ? Icons.hourglass_top
                          : Icons.image_search_outlined,
                    ),
                    label: Text(
                      importingSchedule
                          ? 'Importing schedule…'
                          : 'Import a schedule image',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saved captures stay on this device. No account needed.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    widget.onOpenCapture == null ? 'Inbox' : 'Your captures',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Keep the thought. Decide what comes next later.'),
                  const SizedBox(height: 16),
                  if (model.loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (model.loadError != null) ...[
                    Text(
                      model.loadError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    TextButton.icon(
                      onPressed: model.load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ] else ...[
                    if (model.captures.isNotEmpty) ...[
                      TextField(
                        controller: search,
                        decoration: InputDecoration(
                          labelText: 'Search your captures',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: search.clear,
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECEFE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.inbox_outlined, size: 32),
                            const SizedBox(height: 12),
                            Text(
                              query.isEmpty
                                  ? 'Your mind doesn’t have to hold it all.'
                                  : 'No matching captures',
                              style: theme.textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              query.isEmpty
                                  ? 'Save your first thought above. A note can stay a note.'
                                  : 'Try another word from your original note.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    for (final capture in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          color: Colors.white,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            title: Text(
                              capture.originalText,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(dateLabel(capture)),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => openCapture(capture),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ScheduleImportProgressDialog extends StatefulWidget {
  const _ScheduleImportProgressDialog({required this.onCancel});
  final VoidCallback onCancel;

  @override
  State<_ScheduleImportProgressDialog> createState() =>
      _ScheduleImportProgressDialogState();
}

class _ScheduleImportProgressDialogState
    extends State<_ScheduleImportProgressDialog> {
  Timer? timer;
  int seconds = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => seconds++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = seconds < 4
        ? 'Preparing the image…'
        : seconds < 10
        ? 'Finding classes and times…'
        : seconds < 20
        ? 'Preparing your editable timetable…'
        : 'This is taking longer than usual. You can cancel and retry with a clearer image.';
    return AlertDialog(
      title: const Text('Reading your schedule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(message),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
