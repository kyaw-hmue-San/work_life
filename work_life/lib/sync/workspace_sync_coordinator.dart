import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_sync_store.dart';
import 'sync_models.dart';

class WorkspaceSyncCoordinator extends ChangeNotifier {
  WorkspaceSyncCoordinator({
    required this.workspaceId,
    required this.local,
    required this.remote,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final String workspaceId;
  final LocalSyncStore local;
  final WorkspaceRemoteStore remote;
  final DateTime Function() now;
  SyncStatus status = const SyncStatus(SyncPhase.idle);
  Future<void>? _active;
  bool _disposed = false;

  Future<void> sync() async {
    if (_disposed) return;
    final active = _active;
    if (active != null) return active;
    final operation = _run();
    _active = operation;
    try {
      await operation;
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  Future<void> retryNow() async {
    await local.makeRetriesDue();
    await sync();
  }

  Future<void> _run() async {
    status = SyncStatus(SyncPhase.syncing, pending: await local.pendingCount());
    _changed();
    try {
      await local.initialize(workspaceId);
      if (!await local.seeded) {
        await _pull();
        await local.seedLocalOnly();
      }
      for (final mutation in await local.pending(workspaceId, now: now())) {
        if (_disposed) return;
        try {
          final result = await remote.push(mutation);
          await local.acknowledge(mutation, result.revision);
        } catch (_) {
          await local.retryLater(mutation, now: now());
          rethrow;
        }
      }
      await _pull();
      final remaining = await local.pendingCount();
      status = remaining == 0
          ? const SyncStatus(SyncPhase.synced)
          : SyncStatus(
              SyncPhase.offline,
              pending: remaining,
              message: 'Changes are saved on this device and waiting for the next safe retry.',
            );
    } catch (_) {
      status = SyncStatus(
        SyncPhase.offline,
        pending: await local.pendingCount(),
        message: 'You’re offline. Your changes are saved and will sync when you’re back online.',
      );
    }
    _changed();
  }

  Future<void> _pull() async {
    while (true) {
      if (_disposed) return;
      final records = await remote.pull(
        workspaceId,
        after: await local.checkpoint,
      );
      if (records.any((record) => record.workspaceId != workspaceId)) {
        throw StateError('Remote returned another workspace');
      }
      if (records.isEmpty) return;
      await local.applyRemote(records);
      if (records.length < 1000) return;
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
