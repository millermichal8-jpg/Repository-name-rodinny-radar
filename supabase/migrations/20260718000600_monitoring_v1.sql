-- Rodinný radar — Monitoring V1
-- Source health, Cron health, incident history and notification-ready monitoring records.

begin;

create table if not exists private.monitoring_incidents (
  id uuid primary key default gen_random_uuid(),
  fingerprint text not null unique,
  category text not null check (category in ('source', 'cron', 'pipeline')),
  scope_code text,
  severity text not null check (severity in ('info', 'warning', 'critical')),
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolved')),
  title text not null,
  message text not null,
  details jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  occurrence_count integer not null default 1 check (occurrence_count >= 1),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  last_notified_at timestamptz,
  notification_count integer not null default 0 check (notification_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists monitoring_incidents_open_idx
  on private.monitoring_incidents (severity, last_seen_at desc)
  where status in ('open', 'acknowledged');

create index if not exists monitoring_incidents_scope_idx
  on private.monitoring_incidents (category, scope_code, status);

drop trigger if exists monitoring_incidents_set_updated_at on private.monitoring_incidents;
create trigger monitoring_incidents_set_updated_at
before update on private.monitoring_incidents
for each row execute function private.set_updated_at();

create table if not exists private.monitoring_check_runs (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('preview', 'check')),
  include_cron boolean not null default true,
  started_at timestamptz not null,
  finished_at timestamptz not null default now(),
  success boolean not null,
  summary jsonb not null default '{}'::jsonb,
  findings jsonb not null default '[]'::jsonb,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists monitoring_check_runs_created_idx
  on private.monitoring_check_runs (created_at desc);

create or replace function private.monitoring_severity_rank_v1(p_severity text)
returns integer
language sql
immutable
as $$
  select case p_severity
    when 'critical' then 3
    when 'warning' then 2
    else 1
  end;
$$;

create or replace function public.catalog_monitoring_evaluate_v1(
  p_record boolean default false,
  p_include_cron boolean default true,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, cron, extensions
as $function$
declare
  v_started_at timestamptz := clock_timestamp();
  v_findings jsonb := '[]'::jsonb;
  v_source record;
  v_last_sync_stats jsonb;
  v_accepted integer;
  v_discovered integer;
  v_expected_jobs text[] := array[
    'rr-data-expansion-v1-sk-ba',
    'rr-data-expansion-v1-sk-tt',
    'rr-data-expansion-v1-sk-tn',
    'rr-data-expansion-v1-sk-nr',
    'rr-data-expansion-v1-sk-za',
    'rr-data-expansion-v1-sk-bb',
    'rr-data-expansion-v1-sk-po',
    'rr-data-expansion-v1-sk-ke',
    'rr-data-expansion-v1-cz-a',
    'rr-data-expansion-v1-cz-b'
  ];
  v_job_name text;
  v_job_exists boolean;
  v_job_active boolean;
  v_cron_run record;
  v_sources_checked integer := 0;
  v_cron_jobs_checked integer := 0;
  v_total integer := 0;
  v_critical integer := 0;
  v_warning integer := 0;
  v_info integer := 0;
  v_open_incidents integer := 0;
  v_finding jsonb;
  v_existing private.monitoring_incidents%rowtype;
  v_incident_id uuid;
  v_check_id uuid;
  v_summary jsonb;
  v_mode text := case when p_record then 'check' else 'preview' end;
begin
  for v_source in
    select
      sp.id,
      sp.code,
      sp.display_name,
      sp.group_code,
      sp.enabled,
      sp.cron_enabled,
      sp.health_status,
      sp.consecutive_failures,
      sp.last_sync_at,
      sp.last_success_at,
      sp.last_error_at,
      sp.last_error_message,
      sp.created_at
    from private.source_pages sp
    order by sp.group_code, sp.priority, sp.code
  loop
    v_sources_checked := v_sources_checked + 1;

    if not v_source.enabled then
      continue;
    end if;

    if v_source.health_status = 'failing' or v_source.consecutive_failures >= 3 then
      v_findings := v_findings || jsonb_build_array(jsonb_build_object(
        'fingerprint', format('source:%s:failure', v_source.code),
        'category', 'source',
        'scopeCode', v_source.code,
        'severity', 'critical',
        'title', format('Zdroj %s opakovane zlyháva', v_source.display_name),
        'message', coalesce(v_source.last_error_message, 'Zdroj má tri alebo viac po sebe idúcich zlyhaní.'),
        'details', jsonb_build_object(
          'managedBy', 'monitoring-v1',
          'groupCode', v_source.group_code,
          'healthStatus', v_source.health_status,
          'consecutiveFailures', v_source.consecutive_failures,
          'lastErrorAt', v_source.last_error_at
        )
      ));
    elsif v_source.health_status = 'warning' or v_source.consecutive_failures > 0 then
      v_findings := v_findings || jsonb_build_array(jsonb_build_object(
        'fingerprint', format('source:%s:failure', v_source.code),
        'category', 'source',
        'scopeCode', v_source.code,
        'severity', 'warning',
        'title', format('Zdroj %s potrebuje pozornosť', v_source.display_name),
        'message', coalesce(v_source.last_error_message, 'Posledný beh zdroja nebol úplne čistý.'),
        'details', jsonb_build_object(
          'managedBy', 'monitoring-v1',
          'groupCode', v_source.group_code,
          'healthStatus', v_source.health_status,
          'consecutiveFailures', v_source.consecutive_failures,
          'lastErrorAt', v_source.last_error_at
        )
      ));
    end if;

    if v_source.cron_enabled then
      if v_source.last_sync_at is null and v_source.created_at < p_now - interval '48 hours' then
        v_findings := v_findings || jsonb_build_array(jsonb_build_object(
          'fingerprint', format('source:%s:no-sync', v_source.code),
          'category', 'source',
          'scopeCode', v_source.code,
          'severity', 'warning',
          'title', format('Zdroj %s ešte nemá automatický sync', v_source.display_name),
          'message', 'Zdroj je zaradený do Cronu, ale nemá zaznamenaný ostrý sync.',
          'details', jsonb_build_object(
            'managedBy', 'monitoring-v1',
            'groupCode', v_source.group_code,
            'cronEnabled', true
          )
        ));
      elsif v_source.last_sync_at is not null and v_source.last_sync_at < p_now - interval '36 hours' then
        v_findings := v_findings || jsonb_build_array(jsonb_build_object(
          'fingerprint', format('source:%s:stale-sync', v_source.code),
          'category', 'source',
          'scopeCode', v_source.code,
          'severity', 'critical',
          'title', format('Zdroj %s sa nesynchronizoval včas', v_source.display_name),
          'message', 'Posledný ostrý sync je starší než 36 hodín.',
          'details', jsonb_build_object(
            'managedBy', 'monitoring-v1',
            'groupCode', v_source.group_code,
            'lastSyncAt', v_source.last_sync_at,
            'lastSuccessAt', v_source.last_success_at
          )
        ));
      end if;
    end if;

    select ssr.stats
    into v_last_sync_stats
    from private.source_sync_runs ssr
    where ssr.source_page_id = v_source.id
      and ssr.action = 'sync'
      and ssr.success = true
    order by ssr.started_at desc
    limit 1;

    v_accepted := null;
    v_discovered := null;

    if v_last_sync_stats is not null then
      begin
        v_accepted := nullif(v_last_sync_stats->>'accepted', '')::integer;
      exception when others then
        v_accepted := null;
      end;

      begin
        v_discovered := nullif(v_last_sync_stats->>'discoveredLinks', '')::integer;
      exception when others then
        v_discovered := null;
      end;
    end if;

    if coalesce(v_discovered, 0) > 0 and coalesce(v_accepted, 0) = 0 then
      v_findings := v_findings || jsonb_build_array(jsonb_build_object(
        'fingerprint', format('source:%s:no-accepted-events', v_source.code),
        'category', 'source',
        'scopeCode', v_source.code,
        'severity', 'info',
        'title', format('Zdroj %s nenašiel použiteľné podujatie', v_source.display_name),
        'message', 'Posledný úspešný sync našiel odkazy, ale neprijal žiadne podujatie.',
        'details', jsonb_build_object(
          'managedBy', 'monitoring-v1',
          'groupCode', v_source.group_code,
          'discoveredLinks', v_discovered,
          'accepted', v_accepted
        )
      ));
    end if;
  end loop;

  if p_include_cron then
    if to_regclass('cron.job') is null then
      v_findings := v_findings || jsonb_build_array(jsonb_build_object(
        'fingerprint', 'cron:extension-or-jobs-missing',
        'category', 'cron',
        'scopeCode', 'rr-data-expansion-v1',
        'severity', 'critical',
        'title', 'Cron tabuľka nie je dostupná',
        'message', 'Monitoring nevie overiť automatické úlohy pg_cron.',
        'details', jsonb_build_object('managedBy', 'monitoring-v1')
      ));
    else
      foreach v_job_name in array v_expected_jobs
      loop
        v_cron_jobs_checked := v_cron_jobs_checked + 1;

        execute format(
          'select exists(select 1 from cron.job where jobname = %L), coalesce((select active from cron.job where jobname = %L limit 1), false)',
          v_job_name,
          v_job_name
        ) into v_job_exists, v_job_active;

        if not v_job_exists or not v_job_active then
          v_findings := v_findings || jsonb_build_array(jsonb_build_object(
            'fingerprint', format('cron:%s:missing-or-inactive', v_job_name),
            'category', 'cron',
            'scopeCode', v_job_name,
            'severity', 'critical',
            'title', format('Cron úloha %s nie je aktívna', v_job_name),
            'message', case when v_job_exists then 'Cron úloha existuje, ale je vypnutá.' else 'Očakávaná Cron úloha chýba.' end,
            'details', jsonb_build_object(
              'managedBy', 'monitoring-v1',
              'exists', v_job_exists,
              'active', v_job_active
            )
          ));
        end if;
      end loop;

      if to_regclass('cron.job_run_details') is not null then
        for v_cron_run in execute $sql$
          select
            j.jobname,
            d.status,
            d.return_message,
            d.start_time,
            d.end_time
          from cron.job j
          left join lateral (
            select
              details.status,
              details.return_message,
              details.start_time,
              details.end_time
            from cron.job_run_details details
            where details.jobid = j.jobid
            order by details.start_time desc nulls last
            limit 1
          ) d on true
          where j.jobname like 'rr-data-expansion-v1-%'
        $sql$
        loop
          if v_cron_run.status = 'failed'
             and v_cron_run.start_time >= p_now - interval '48 hours' then
            v_findings := v_findings || jsonb_build_array(jsonb_build_object(
              'fingerprint', format('cron:%s:last-run-failed', v_cron_run.jobname),
              'category', 'cron',
              'scopeCode', v_cron_run.jobname,
              'severity', 'critical',
              'title', format('Posledný beh Cron úlohy %s zlyhal', v_cron_run.jobname),
              'message', coalesce(v_cron_run.return_message, 'Cron úloha skončila stavom failed.'),
              'details', jsonb_build_object(
                'managedBy', 'monitoring-v1',
                'status', v_cron_run.status,
                'startTime', v_cron_run.start_time,
                'endTime', v_cron_run.end_time
              )
            ));
          elsif v_cron_run.status = 'succeeded'
                and v_cron_run.start_time < p_now - interval '36 hours' then
            v_findings := v_findings || jsonb_build_array(jsonb_build_object(
              'fingerprint', format('cron:%s:stale-run', v_cron_run.jobname),
              'category', 'cron',
              'scopeCode', v_cron_run.jobname,
              'severity', 'warning',
              'title', format('Cron úloha %s sa dlho nespustila', v_cron_run.jobname),
              'message', 'Posledný úspešný beh Cron úlohy je starší než 36 hodín.',
              'details', jsonb_build_object(
                'managedBy', 'monitoring-v1',
                'status', v_cron_run.status,
                'startTime', v_cron_run.start_time,
                'endTime', v_cron_run.end_time
              )
            ));
          end if;
        end loop;
      end if;
    end if;
  end if;

  select
    count(*)::integer,
    count(*) filter (where item->>'severity' = 'critical')::integer,
    count(*) filter (where item->>'severity' = 'warning')::integer,
    count(*) filter (where item->>'severity' = 'info')::integer
  into v_total, v_critical, v_warning, v_info
  from jsonb_array_elements(v_findings) item;

  if p_record then
    for v_finding in select value from jsonb_array_elements(v_findings)
    loop
      select *
      into v_existing
      from private.monitoring_incidents
      where fingerprint = v_finding->>'fingerprint';

      insert into private.monitoring_incidents (
        fingerprint,
        category,
        scope_code,
        severity,
        status,
        title,
        message,
        details,
        first_seen_at,
        last_seen_at,
        occurrence_count,
        resolved_at
      ) values (
        v_finding->>'fingerprint',
        v_finding->>'category',
        nullif(v_finding->>'scopeCode', ''),
        v_finding->>'severity',
        'open',
        v_finding->>'title',
        v_finding->>'message',
        coalesce(v_finding->'details', '{}'::jsonb),
        p_now,
        p_now,
        1,
        null
      )
      on conflict (fingerprint) do update
      set
        category = excluded.category,
        scope_code = excluded.scope_code,
        severity = excluded.severity,
        status = case
          when private.monitoring_incidents.status = 'resolved' then 'open'
          else private.monitoring_incidents.status
        end,
        title = excluded.title,
        message = excluded.message,
        details = excluded.details,
        last_seen_at = p_now,
        occurrence_count = private.monitoring_incidents.occurrence_count + 1,
        resolved_at = null,
        updated_at = p_now
      returning id into v_incident_id;
    end loop;

    update private.monitoring_incidents incident
    set
      status = 'resolved',
      resolved_at = p_now,
      updated_at = p_now
    where incident.status in ('open', 'acknowledged')
      and incident.details->>'managedBy' = 'monitoring-v1'
      and (
        incident.category = 'source'
        or (p_include_cron and incident.category = 'cron')
      )
      and not exists (
        select 1
        from jsonb_array_elements(v_findings) finding
        where finding->>'fingerprint' = incident.fingerprint
      );
  end if;

  select count(*)::integer
  into v_open_incidents
  from private.monitoring_incidents
  where status in ('open', 'acknowledged');

  v_summary := jsonb_build_object(
    'totalFindings', v_total,
    'critical', v_critical,
    'warnings', v_warning,
    'info', v_info,
    'sourcesChecked', v_sources_checked,
    'cronJobsChecked', v_cron_jobs_checked,
    'openIncidents', v_open_incidents
  );

  if p_record then
    insert into private.monitoring_check_runs (
      mode,
      include_cron,
      started_at,
      finished_at,
      success,
      summary,
      findings
    ) values (
      v_mode,
      p_include_cron,
      v_started_at,
      clock_timestamp(),
      true,
      v_summary,
      v_findings
    )
    returning id into v_check_id;
  end if;

  return jsonb_build_object(
    'version', 'monitoring-v1',
    'mode', v_mode,
    'recorded', p_record,
    'includeCron', p_include_cron,
    'generatedAt', p_now,
    'checkId', v_check_id,
    'summary', v_summary,
    'findings', v_findings,
    'note', case
      when p_record then 'Monitoring incidenty boli aktualizované. Externé e-mailové alebo webhook upozornenia ešte nie sú zapnuté.'
      else 'Preview nič nezapísal ani nezmenil.'
    end
  );
exception when others then
  if p_record then
    insert into private.monitoring_check_runs (
      mode,
      include_cron,
      started_at,
      finished_at,
      success,
      summary,
      findings,
      error_message
    ) values (
      v_mode,
      p_include_cron,
      v_started_at,
      clock_timestamp(),
      false,
      '{}'::jsonb,
      '[]'::jsonb,
      sqlerrm
    );
  end if;
  raise;
end;
$function$;

revoke all on function public.catalog_monitoring_evaluate_v1(boolean, boolean, timestamptz) from public;
grant execute on function public.catalog_monitoring_evaluate_v1(boolean, boolean, timestamptz) to service_role;

create or replace function public.catalog_monitoring_open_incidents_v1()
returns table (
  incident_id uuid,
  fingerprint text,
  category text,
  scope_code text,
  severity text,
  status text,
  title text,
  message text,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  occurrence_count integer,
  details jsonb
)
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select
    incident.id,
    incident.fingerprint,
    incident.category,
    incident.scope_code,
    incident.severity,
    incident.status,
    incident.title,
    incident.message,
    incident.first_seen_at,
    incident.last_seen_at,
    incident.occurrence_count,
    incident.details
  from private.monitoring_incidents incident
  where incident.status in ('open', 'acknowledged')
  order by
    private.monitoring_severity_rank_v1(incident.severity) desc,
    incident.last_seen_at desc;
$$;

revoke all on function public.catalog_monitoring_open_incidents_v1() from public;
grant execute on function public.catalog_monitoring_open_incidents_v1() to service_role;

create or replace function public.catalog_monitoring_acknowledge_incident_v1(
  p_incident_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_incident private.monitoring_incidents%rowtype;
begin
  update private.monitoring_incidents
  set
    status = 'acknowledged',
    acknowledged_at = now(),
    details = details || case
      when nullif(trim(coalesce(p_note, '')), '') is null then '{}'::jsonb
      else jsonb_build_object('acknowledgementNote', trim(p_note))
    end,
    updated_at = now()
  where id = p_incident_id
    and status <> 'resolved'
  returning * into v_incident;

  if not found then
    raise exception 'Incident sa nenašiel alebo je už vyriešený.';
  end if;

  return jsonb_build_object(
    'incidentId', v_incident.id,
    'status', v_incident.status,
    'acknowledgedAt', v_incident.acknowledged_at
  );
end;
$$;

revoke all on function public.catalog_monitoring_acknowledge_incident_v1(uuid, text) from public;
grant execute on function public.catalog_monitoring_acknowledge_incident_v1(uuid, text) to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-monitoring-v1',
  'Monitoring incidents, source and Cron health evaluation, preview/check reports and acknowledgement workflow'
)
on conflict (version) do nothing;

commit;
