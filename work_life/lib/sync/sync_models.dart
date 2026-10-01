enum SyncPhase { idle, syncing, synced, offline, problem }

class SyncStatus {
  const SyncStatus(this.phase, {this.pending = 0, this.message});
  final SyncPhase phase;
  final int pending;
  final String? message;
}

class SyncMutation {
  const SyncMutation({
    required this.mutationId,
    required this.workspaceId,
    required this.entityType,
    required this.recordId,
    required this.deleted,
    required this.baseRevision,
    required this.payload,
  });
  final String mutationId, workspaceId, entityType, recordId;
  final bool deleted;
  final int baseRevision;
  final Map<String, Object?>? payload;
}

class SyncRecord {
  const SyncRecord({
    required this.workspaceId,
    required this.entityType,
    required this.recordId,
    required this.revision,
    required this.deleted,
    required this.payload,
  });
  final String workspaceId, entityType, recordId;
  final int revision;
  final bool deleted;
  final Map<String, Object?>? payload;
}

class SyncPushResult {
  const SyncPushResult({required this.revision});
  final int revision;
}

abstract interface class WorkspaceRemoteStore {
  Future<SyncPushResult> push(SyncMutation mutation);
  Future<List<SyncRecord>> pull(String workspaceId, {required int after});
}
