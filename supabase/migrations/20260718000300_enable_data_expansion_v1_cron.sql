-- Rodinný radar – automatický denný sync Data Expansion V1

begin;

create extension if not exists pg_cron;
create extension if not exists pg_net;

update private.source_pages
set
  cron_enabled = true,
  updated_at = now()
where enabled = true
  and group_code in (
    'sk-ba',
    'sk-tt',
    'sk-tn',
    'sk-nr',
    'sk-za',
    'sk-bb',
    'sk-po',
    'sk-ke',
    'cz-wave1'
  );

create or replace function private.run_data_expansion_group_v2(
  p_group_code text,
  p_source_offset integer default 0,
  p_max_sources integer default 4
)
returns bigint
language plpgsql
security definer
set search_path = public, private, vault, net
as $function$
declare
  v_sync_token text;
  v_request_id bigint;
begin
  select decrypted_secret
  into v_sync_token
  from vault.decrypted_secrets
  where name = 'rr_catalog_sync_token'
  limit 1;

  if v_sync_token is null then
    raise exception 'Vo Vaulte chýba rr_catalog_sync_token.';
  end if;

  select net.http_post(
    url := 'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/data-expansion-orchestrator',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Sync-Token', v_sync_token
    ),
    body := jsonb_build_object(
      'action', 'sync',
      'confirmWrite', true,
      'sourceGroup', p_group_code,
      'sourceOffset', greatest(0, p_source_offset),
      'maxSources', least(8, greatest(1, p_max_sources)),
      'maxEventsPerSource', 100,
      'retries', 1,
      'cronEnabledOnly', true
    ),
    timeout_milliseconds := 120000
  )
  into v_request_id;

  return v_request_id;
end;
$function$;

revoke all
on function private.run_data_expansion_group_v2(text, integer, integer)
from public;

do $block$
declare
  v_job record;
  v_has_secret boolean := false;
begin
  begin
    execute
      'select exists (
         select 1
         from vault.decrypted_secrets
         where name = ''rr_catalog_sync_token''
       )'
    into v_has_secret;
  exception when others then
    v_has_secret := false;
  end;

  -- Pri lokálnom db reset Vault token nie je, preto sa úlohy nevytvoria.
  -- V produkcii token existuje a úlohy sa automaticky naplánujú.
  if v_has_secret then
    for v_job in
      select jobid
      from cron.job
      where jobname like 'rr-data-expansion-v1-%'
    loop
      perform cron.unschedule(v_job.jobid);
    end loop;

    perform cron.schedule(
      'rr-data-expansion-v1-sk-ba',
      '10 1 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-ba', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-tt',
      '20 1 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-tt', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-tn',
      '30 1 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-tn', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-nr',
      '40 1 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-nr', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-za',
      '50 1 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-za', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-bb',
      '0 2 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-bb', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-po',
      '10 2 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-po', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-sk-ke',
      '20 2 * * *',
      $cron$select private.run_data_expansion_group_v2('sk-ke', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-cz-a',
      '30 2 * * *',
      $cron$select private.run_data_expansion_group_v2('cz-wave1', 0, 4);$cron$
    );

    perform cron.schedule(
      'rr-data-expansion-v1-cz-b',
      '40 2 * * *',
      $cron$select private.run_data_expansion_group_v2('cz-wave1', 4, 4);$cron$
    );
  else
    raise notice 'Vault token sa nenašiel – Cron úlohy sa v lokálnej databáze nevytvorili.';
  end if;
end;
$block$;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-data-expansion-v1-cron',
  'Daily automatic synchronization for verified Slovak and Czech municipal sources'
)
on conflict (version) do nothing;

commit;