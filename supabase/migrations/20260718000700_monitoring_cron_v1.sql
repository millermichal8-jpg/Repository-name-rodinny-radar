-- Rodinný radar – denná automatická kontrola zdrojov a Cronu

begin;

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function private.run_monitoring_v1()
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
    url := 'https://xvqzpbfcxhrxgovkkajt.supabase.co/functions/v1/monitoring-report',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Sync-Token', v_sync_token
    ),
    body := jsonb_build_object(
      'action', 'check',
      'confirmWrite', true,
      'includeCron', true
    ),
    timeout_milliseconds := 120000
  )
  into v_request_id;

  return v_request_id;
end;
$function$;

revoke all
on function private.run_monitoring_v1()
from public;

do $block$
declare
  v_existing_job_id bigint;
  v_has_secret boolean := false;
begin
  begin
    select exists (
      select 1
      from vault.decrypted_secrets
      where name = 'rr_catalog_sync_token'
    )
    into v_has_secret;
  exception when others then
    v_has_secret := false;
  end;

  if v_has_secret then
    select jobid
    into v_existing_job_id
    from cron.job
    where jobname = 'rr-monitoring-v1-daily'
    limit 1;

    if v_existing_job_id is not null then
      perform cron.unschedule(v_existing_job_id);
    end if;

    perform cron.schedule(
      'rr-monitoring-v1-daily',
      '10 3 * * *',
      $cron$select private.run_monitoring_v1();$cron$
    );
  else
    raise notice 'Vault token sa lokálne nenašiel – monitoring Cron nebol vytvorený.';
  end if;
end;
$block$;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-monitoring-cron-v1',
  'Daily automatic source, pipeline and Cron health evaluation'
)
on conflict (version) do nothing;

commit;