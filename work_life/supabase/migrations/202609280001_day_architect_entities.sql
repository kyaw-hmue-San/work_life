-- Extend the existing authenticated workspace mutation RPC for Day Architect
-- records. The workspace-record envelope keeps row ownership and RLS unchanged.
create or replace function public.apply_workspace_mutation(
  p_workspace_id uuid,
  p_mutation_id text,
  p_entity_type text,
  p_record_id text,
  p_deleted boolean,
  p_base_revision bigint,
  p_payload jsonb
) returns table(revision bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_existing public.workspace_records%rowtype;
  v_revision bigint;
  v_allowed constant text[] := array[
    'captures', 'life_areas', 'projects', 'project_entries', 'tasks', 'plans',
    'routines', 'routine_records', 'focus_sessions', 'reminders',
    'reminder_suppressions', 'quiet_hours', 'reminder_preferences',
    'workspace_setup', 'recurring_schedules', 'schedule_exceptions',
    'planning_preferences'
  ];
begin
  if v_user is null or p_workspace_id <> v_user then
    raise exception 'workspace_access_denied' using errcode = '42501';
  end if;
  if p_mutation_id is null or length(p_mutation_id) > 128
     or p_record_id is null or length(p_record_id) > 512
     or not (p_entity_type = any(v_allowed))
     or (p_deleted and p_payload is not null)
     or (not p_deleted and p_payload is null) then
    raise exception 'invalid_workspace_mutation' using errcode = '22023';
  end if;

  insert into public.workspaces(id, owner_id)
  values (p_workspace_id, v_user) on conflict (id) do nothing;
  if not exists (select 1 from public.workspaces where id = p_workspace_id and owner_id = v_user) then
    raise exception 'workspace_access_denied' using errcode = '42501';
  end if;

  select m.revision into v_revision from public.workspace_mutations m
  where m.workspace_id = p_workspace_id and m.mutation_id = p_mutation_id;
  if found then return query select v_revision; return; end if;

  select * into v_existing from public.workspace_records
  where workspace_id = p_workspace_id and entity_type = p_entity_type and record_id = p_record_id
  for update;
  if found and v_existing.deleted and not p_deleted and p_base_revision < v_existing.revision then
    v_revision := v_existing.revision;
  else
    v_revision := nextval('public.workspace_revision_seq');
    insert into public.workspace_records(workspace_id,entity_type,record_id,payload,deleted,revision,updated_at)
    values (p_workspace_id,p_entity_type,p_record_id,case when p_deleted then null else p_payload end,p_deleted,v_revision,now())
    on conflict (workspace_id,entity_type,record_id) do update set
      payload=case when p_entity_type='planning_preferences'
        then coalesce(public.workspace_records.payload,'{}'::jsonb) || excluded.payload
        else excluded.payload end,
      deleted=excluded.deleted,revision=excluded.revision,updated_at=excluded.updated_at;
  end if;
  insert into public.workspace_mutations(workspace_id,mutation_id,revision)
  values (p_workspace_id,p_mutation_id,v_revision);
  return query select v_revision;
end;
$$;

revoke all on function public.apply_workspace_mutation(uuid,text,text,text,boolean,bigint,jsonb) from public;
grant execute on function public.apply_workspace_mutation(uuid,text,text,text,boolean,bigint,jsonb) to authenticated;
