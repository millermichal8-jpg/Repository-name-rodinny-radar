-- Rodinný radar — Data Expansion V1 Cron TEMPLATE
-- NESPUSTAJ, kym manualny preview a maly produkcny sync nepotvrdia zdroje.
-- Funkcie musia byt nasadene s --no-verify-jwt a hodnoty musia byt ulozene v Supabase Vault.

-- 1. Jednorazovo vytvor tajomstva vo Vault cez SQL editor.
--    Hodnoty vloz priamo v SQL editore a potom prikazy z historie odstran.
-- select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'rr_project_url');
-- select vault.create_secret('YOUR_SUPABASE_ANON_KEY', 'rr_anon_key');
-- select vault.create_secret('YOUR_CATALOG_SYNC_TOKEN', 'rr_catalog_sync_token');

-- 2. Az po overeni nastav cron_enabled iba pre preskusane zdroje.
-- update private.source_pages
-- set cron_enabled = true, updated_at = now()
-- where code in ('bs-kultura', 'zvolen-events', 'bojnice-events');

-- 3. Pomocna funkcia pre bezpecne volanie orchestratora z pg_cron.
create or replace function private.run_data_expansion_group_v1(
  p_group_code text,
  p_source_offset integer default 0,
  p_max_sources integer default 4
)
returns bigint
language plpgsql
security definer
set search_path = public, private, vault, net
as $$
declare
  v_project_url text;
  v_anon_key text;
  v_sync_token text;
  v_request_id bigint;
begin
  select decrypted_secret into v_project_url
  from vault.decrypted_secrets where name = 'rr_project_url' limit 1;
  select decrypted_secret into v_anon_key
  from vault.decrypted_secrets where name = 'rr_anon_key' limit 1;
  select decrypted_secret into v_sync_token
  from vault.decrypted_secrets where name = 'rr_catalog_sync_token' limit 1;

  if v_project_url is null or v_anon_key is null or v_sync_token is null then
    raise exception 'Chybaju rr_project_url, rr_anon_key alebo rr_catalog_sync_token vo Vault.';
  end if;

  select net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/data-expansion-orchestrator',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key,
      'apikey', v_anon_key,
      'X-Sync-Token', v_sync_token
    ),
    body := jsonb_build_object(
      'action', 'sync',
      'confirmWrite', true,
      'sourceGroup', p_group_code,
      'sourceOffset', greatest(0, p_source_offset),
      'maxSources', least(8, greatest(1, p_max_sources)),
      'maxEventsPerSource', 80,
      'retries', 1,
      'cronEnabledOnly', true
    ),
    timeout_milliseconds := 120000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.run_data_expansion_group_v1(text, integer, integer) from public;

-- 4. Vzor nocnych behov. Najprv odkomentuj iba jednu overenu skupinu.
-- select cron.schedule('rr-sk-bb', '10 1 * * *', $$select private.run_data_expansion_group_v1('sk-bb', 0, 4);$$);
-- select cron.schedule('rr-sk-ba', '20 1 * * *', $$select private.run_data_expansion_group_v1('sk-ba', 0, 4);$$);
-- select cron.schedule('rr-sk-tt', '30 1 * * *', $$select private.run_data_expansion_group_v1('sk-tt', 0, 4);$$);
-- select cron.schedule('rr-sk-tn', '40 1 * * *', $$select private.run_data_expansion_group_v1('sk-tn', 0, 4);$$);
-- select cron.schedule('rr-sk-nr', '50 1 * * *', $$select private.run_data_expansion_group_v1('sk-nr', 0, 4);$$);
-- select cron.schedule('rr-sk-za', '00 2 * * *', $$select private.run_data_expansion_group_v1('sk-za', 0, 4);$$);
-- select cron.schedule('rr-sk-po', '10 2 * * *', $$select private.run_data_expansion_group_v1('sk-po', 0, 4);$$);
-- select cron.schedule('rr-sk-ke', '20 2 * * *', $$select private.run_data_expansion_group_v1('sk-ke', 0, 4);$$);
-- select cron.schedule('rr-cz-wave1-a', '30 2 * * *', $$select private.run_data_expansion_group_v1('cz-wave1', 0, 4);$$);
-- select cron.schedule('rr-cz-wave1-b', '40 2 * * *', $$select private.run_data_expansion_group_v1('cz-wave1', 4, 4);$$);

-- Kontrola naplanovanych uloh:
-- select jobid, jobname, schedule, active from cron.job order by jobname;

-- Zrusenie konkretnej ulohy:
-- select cron.unschedule('rr-sk-bb');
