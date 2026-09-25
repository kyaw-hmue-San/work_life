import 'package:flutter/foundation.dart';

import 'capture.dart';
import 'capture_repository.dart';

class InboxModel extends ChangeNotifier {
  InboxModel(this.repository);
  final CaptureRepository repository;
  List<Capture> captures = [];
  bool loading = true;
  bool saving = false;
  String? loadError;
  String? saveError;
  Capture? _pending;
  bool _disposed = false;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    loadError = null;
    _changed();
    try {
      captures = await repository.load();
    } catch (_) {
      loadError = 'Couldn’t open your inbox. Please try again.';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<bool> save(String text) async {
    if (saving || loading || loadError != null || text.trim().isEmpty) {
      return false;
    }
    saving = true;
    saveError = null;
    _changed();
    // Reuse the operation identity on retry after a failed save.
    final capture = _pending?.originalText == text
        ? _pending!
        : Capture.create(text);
    _pending = capture;
    try {
      await repository.save(capture);
      captures = [capture, ...captures.where((item) => item.id != capture.id)];
      _pending = null;
      return true;
    } catch (_) {
      saveError = 'Couldn’t save yet. Your text is still here—try again.';
      return false;
    } finally {
      saving = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
