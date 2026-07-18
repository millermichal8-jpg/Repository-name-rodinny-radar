-- Rodinný radar — Source Reliability V1
-- Distinguishes technically broken sources from valid sources with no usable events.

begin;

alter table private.source_pages
  drop constraint if exists source_pages_health_status_check;

alter table private.source_pages
  add constraint source_pages_health_status_check
  check (health_status in ('unknown', 'healthy', 'empty', 'warning', 'failing', 'disabled'));

create or replace function public.catalog_record_source_run_v1(
  p_source_page_code text,
  p_action text,
  p_started_at timestamptz,
  p_duration_ms integer,
  p_success boolean,
  p_stats jsonb default '{}'::jsonb,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $function$
declare
  v_source private.source_pages%rowtype;
  v_accepted integer := 0;
  v_discovered integer := 0;
  v_parser_errors integer := 0;
  v_effective_success boolean;
  v_effective_error text;
  v_new_failures integer;
  v_health text;
begin
  if p_action not in ('preview', 'sync') then
    raise exception 'Unsupported source run action: %', p_action;
  end if;

  select * into v_source
  from private.source_pages
  where code = p_source_page_code
  for update;

  if not found then
    raise exception 'Unknown source page: %', p_source_page_code;
  end if;

  begin
    v_accepted := greatest(0, coalesce((p_stats->>'accepted')::integer, 0));
  exception when others then
    v_accepted := 0;
  end;

  begin
    v_discovered := greatest(0, coalesce((p_stats->>'discoveredLinks')::integer, 0));
  exception when others then
    v_discovered := 0;
  end;

  begin
    v_parser_errors := case
      when jsonb_typeof(p_stats->'errors') = 'array'
        then jsonb_array_length(p_stats->'errors')
      else 0
    end;
  exception when others then
    v_parser_errors := 0;
  end;

  v_effective_success := p_success and v_parser_errors = 0;
  v_effective_error := nullif(p_error_message, '');

  if not v_effective_success and v_effective_error is null and v_parser_errors > 0 then
    v_effective_error := format('Parser zaznamenal %s chýb detailov.', v_parser_errors);
  end if;

  v_new_failures := case
    when v_effective_success then 0
    else v_source.consecutive_failures + 1
  end;

  v_health := case
    when not v_source.enabled then 'disabled'
    when not v_effective_success and v_new_failures >= 3 then 'failing'
    when not v_effective_success then 'warning'
    when v_accepted > 0 then 'healthy'
    else 'empty'
  end;

  insert into private.source_sync_runs (
    source_page_id,
    action,
    started_at,
    finished_at,
    duration_ms,
    success,
    stats,
    error_message
  ) values (
    v_source.id,
    p_action,
    p_started_at,
    now(),
    greatest(0, p_duration_ms),
    v_effective_success,
    coalesce(p_stats, '{}'::jsonb),
    v_effective_error
  );

  update private.source_pages
  set
    last_preview_at = case when p_action = 'preview' then now() else last_preview_at end,
    last_sync_at = case when p_action = 'sync' then now() else last_sync_at end,
    last_success_at = case when v_effective_success then now() else last_success_at end,
    last_error_at = case when v_effective_success then last_error_at else now() end,
    last_error_message = case when v_effective_success then null else v_effective_error end,
    health_status = v_health,
    consecutive_failures = v_new_failures,
    last_duration_ms = greatest(0, p_duration_ms),
    last_result = coalesce(p_stats, '{}'::jsonb),
    updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'sourcePageCode', p_source_page_code,
    'healthStatus', v_health,
    'contentStatus', case when v_accepted > 0 then 'events' when v_discovered > 0 then 'links-only' else 'empty' end,
    'accepted', v_accepted,
    'discoveredLinks', v_discovered,
    'parserErrors', v_parser_errors,
    'consecutiveFailures', v_new_failures
  );
end;
$function$;

revoke all on function public.catalog_record_source_run_v1(text, text, timestamptz, integer, boolean, jsonb, text) from public;
grant execute on function public.catalog_record_source_run_v1(text, text, timestamptz, integer, boolean, jsonb, text) to service_role;

-- Repair historical false warnings: a successful run with zero accepted events is empty, not broken.
update private.source_pages
set
  health_status = case
    when coalesce(last_result->>'accepted', '') ~ '^[0-9]+$'
      and (last_result->>'accepted')::integer > 0 then 'healthy'
    else 'empty'
  end,
  updated_at = now()
where health_status = 'warning'
  and consecutive_failures = 0
  and last_error_message is null;

create or replace function public.catalog_source_reliability_report_v1()
returns table (
  source_page_code text,
  display_name text,
  group_code text,
  country_code text,
  health_status text,
  consecutive_failures integer,
  discovered_links integer,
  parsed_candidates integer,
  accepted integer,
  rejected integer,
  parser_errors integer,
  rejected_reasons jsonb,
  content_status text,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error_message text
)
language sql
security definer
set search_path = public, private
as $function$
  select
    sp.code,
    sp.display_name,
    sp.group_code,
    sp.country_code,
    sp.health_status,
    sp.consecutive_failures,
    case when coalesce(sp.last_result->>'discoveredLinks', '') ~ '^[0-9]+$'
      then (sp.last_result->>'discoveredLinks')::integer else 0 end,
    case when coalesce(sp.last_result->>'parsedCandidates', '') ~ '^[0-9]+$'
      then (sp.last_result->>'parsedCandidates')::integer else 0 end,
    case when coalesce(sp.last_result->>'accepted', '') ~ '^[0-9]+$'
      then (sp.last_result->>'accepted')::integer else 0 end,
    case when coalesce(sp.last_result->>'rejected', '') ~ '^[0-9]+$'
      then (sp.last_result->>'rejected')::integer else 0 end,
    case when jsonb_typeof(sp.last_result->'errors') = 'array'
      then jsonb_array_length(sp.last_result->'errors') else 0 end,
    case when jsonb_typeof(sp.last_result->'rejectedReasons') = 'object'
      then sp.last_result->'rejectedReasons' else '{}'::jsonb end,
    case
      when sp.health_status in ('warning', 'failing') then 'technical-problem'
      when coalesce(sp.last_result->>'accepted', '') ~ '^[0-9]+$'
        and (sp.last_result->>'accepted')::integer > 0 then 'events'
      when coalesce(sp.last_result->>'discoveredLinks', '') ~ '^[0-9]+$'
        and (sp.last_result->>'discoveredLinks')::integer > 0 then 'links-only'
      else 'empty'
    end,
    sp.last_sync_at,
    sp.last_success_at,
    sp.last_error_at,
    sp.last_error_message
  from private.source_pages sp
  where sp.enabled = true
  order by
    case sp.health_status
      when 'failing' then 1
      when 'warning' then 2
      when 'empty' then 3
      when 'unknown' then 4
      else 5
    end,
    sp.group_code,
    sp.priority,
    sp.code;
$function$;

revoke all on function public.catalog_source_reliability_report_v1() from public;
grant execute on function public.catalog_source_reliability_report_v1() to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-source-reliability-v1',
  'Reliable source health semantics, parser diagnostics and empty-source classification'
)
on conflict (version) do nothing;

commit;
