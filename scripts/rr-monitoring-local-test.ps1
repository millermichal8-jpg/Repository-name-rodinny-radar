param()

$ErrorActionPreference = "Stop"

$dbContainer = docker ps --filter "name=supabase_db_" --format "{{.Names}}" |
    Select-Object -First 1

if (-not $dbContainer) {
    throw "Lokálny Supabase databázový kontajner nebeží."
}

$sql = @'
\set ON_ERROR_STOP on
begin;

do $test$
declare
  v_preview jsonb;
  v_check jsonb;
  v_resolve jsonb;
  v_incident_id uuid;
  v_status text;
begin
  update private.source_pages
  set
    health_status = 'failing',
    consecutive_failures = 4,
    last_error_at = now(),
    last_error_message = 'Synthetic Monitoring V1 failure',
    last_sync_at = now(),
    last_success_at = now(),
    updated_at = now()
  where code = 'bb-events';

  if not found then
    raise exception 'Testovací zdroj bb-events sa nenašiel.';
  end if;

  v_preview := public.catalog_monitoring_evaluate_v1(false, false, now());

  if not exists (
    select 1
    from jsonb_array_elements(v_preview->'findings') finding
    where finding->>'fingerprint' = 'source:bb-events:failure'
      and finding->>'severity' = 'critical'
  ) then
    raise exception 'Preview nenašiel syntetický critical incident. Výsledok: %', v_preview;
  end if;

  if exists (
    select 1
    from private.monitoring_incidents
    where fingerprint = 'source:bb-events:failure'
  ) then
    raise exception 'Preview nesmie zapisovať incidenty.';
  end if;

  v_check := public.catalog_monitoring_evaluate_v1(true, false, now());

  select id, status
  into v_incident_id, v_status
  from private.monitoring_incidents
  where fingerprint = 'source:bb-events:failure';

  if v_incident_id is null or v_status <> 'open' then
    raise exception 'Check nevytvoril otvorený incident. Výsledok: %', v_check;
  end if;

  if not exists (
    select 1
    from private.monitoring_check_runs
    where id = (v_check->>'checkId')::uuid
      and success = true
  ) then
    raise exception 'Chýba auditný monitoring check run.';
  end if;

  update private.source_pages
  set
    health_status = 'healthy',
    consecutive_failures = 0,
    last_error_message = null,
    last_success_at = now(),
    last_sync_at = now(),
    updated_at = now()
  where code = 'bb-events';

  v_resolve := public.catalog_monitoring_evaluate_v1(true, false, now() + interval '1 minute');

  select status
  into v_status
  from private.monitoring_incidents
  where id = v_incident_id;

  if v_status <> 'resolved' then
    raise exception 'Vyriešený problém neuzavrel incident. Stav: %, výsledok: %', v_status, v_resolve;
  end if;

  raise notice 'MONITORING V1 TEST OK';
  raise notice 'Preview: %', v_preview->'summary';
  raise notice 'Check: %', v_check->'summary';
  raise notice 'Resolve: %', v_resolve->'summary';
end;
$test$;

rollback;
'@

Write-Host "`n--- MONITORING V1: SYNTHETICKÝ LOKÁLNY TEST ---" -ForegroundColor Cyan

$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Syntetický Monitoring V1 test zlyhal."
}

Write-Host "`nMONITORING V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
Write-Host "Preview nič nezapísal; check vytvoril a po oprave uzavrel incident." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, takže nezanechal testovacie dáta." -ForegroundColor Green
