import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_models.dart';

class SupabaseWorkspaceRemote implements WorkspaceRemoteStore {
  const SupabaseWorkspaceRemote(this.client);
  final SupabaseClient client;

  @override
  Future<SyncPushResult> push(SyncMutation mutation) async {
    final value = await client.rpc(
      'apply_workspace_mutation',
      params: {
        'p_workspace_id': mutation.workspaceId,
        'p_mutation_id': mutation.mutationId,
        'p_entity_type': mutation.entityType,
        'p_record_id': mutation.recordId,
        'p_deleted': mutation.deleted,
        'p_base_revision': mutation.baseRevision,
        'p_payload': mutation.payload,
      },
    );
    final row = value is List ? value.single : value;
    return SyncPushResult(
      revision: (row as Map<String, dynamic>)['revision'] as int,
    );
  }

  @override
  Future<List<SyncRecord>> pull(
    String workspaceId, {
    required int after,
  }) async {
    final rows = await client
        .from('workspace_records')
        .select('workspace_id,entity_type,record_id,revision,deleted,payload')
        .eq('workspace_id', workspaceId)
        .gt('revision', after)
        .order('revision')
        .limit(1000);
    return rows
        .map(
          (row) => SyncRecord(
            workspaceId: row['workspace_id'] as String,
            entityType: row['entity_type'] as String,
            recordId: row['record_id'] as String,
            revision: row['revision'] as int,
            deleted: row['deleted'] as bool,
            payload: row['payload'] == null
                ? null
                : Map<String, Object?>.from(row['payload'] as Map),
          ),
        )
        .toList();
  }
}
