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
  v_result jsonb;
  v_monitoring jsonb;
  v_health text;
  v_failures integer;
begin
  v_result := public.catalog_record_source_run_v1(
    'bb-events',
    'sync',
    now(),
    100,
    true,
    '{"discoveredLinks":3,"parsedCandidates":3,"accepted":0,"rejected":3,"rejectedReasons":{"past_event":3},"errors":[]}'::jsonb,
    null
  );

  select health_status, consecutive_failures
  into v_health, v_failures
  from private.source_pages
  where code = 'bb-events';

  if v_health <> 'empty' or v_failures <> 0 then
    raise exception 'Úspešný prázdny zdroj musí byť empty/0, dostal %/%; result=%', v_health, v_failures, v_result;
  end if;

  v_monitoring := public.catalog_monitoring_evaluate_v1(false, false, now());

  if exists (
    select 1
    from jsonb_array_elements(v_monitoring->'findings') finding
    where finding->>'fingerprint' = 'source:bb-events:failure'
  ) then
    raise exception 'Prázdny úspešný zdroj nesmie vytvoriť warning incident.';
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v_monitoring->'findings') finding
    where finding->>'fingerprint' = 'source:bb-events:no-accepted-events'
      and finding->>'severity' = 'info'
  ) then
    raise exception 'Zdroj s odkazmi bez prijatej udalosti má vytvoriť iba info nález.';
  end if;

  v_result := public.catalog_record_source_run_v1(
    'bb-events',
    'sync',
    now(),
    100,
    true,
    '{"discoveredLinks":3,"parsedCandidates":2,"accepted":1,"rejected":1,"rejectedReasons":{"low_quality":1},"errors":[{"url":"https://example.invalid/detail","message":"Synthetic detail error"}]}'::jsonb,
    null
  );

  select health_status, consecutive_failures
  into v_health, v_failures
  from private.source_pages
  where code = 'bb-events';

  if v_health <> 'warning' or v_failures <> 1 then
    raise exception 'Parser error musí vytvoriť warning/1, dostal %/%; result=%', v_health, v_failures, v_result;
  end if;

  v_result := public.catalog_record_source_run_v1(
    'bb-events',
    'sync',
    now(),
    100,
    true,
    '{"discoveredLinks":4,"parsedCandidates":4,"accepted":3,"rejected":1,"rejectedReasons":{"low_quality":1},"errors":[]}'::jsonb,
    null
  );

  select health_status, consecutive_failures
  into v_health, v_failures
  from private.source_pages
  where code = 'bb-events';

  if v_health <> 'healthy' or v_failures <> 0 then
    raise exception 'Čistý zdroj s udalosťami musí byť healthy/0, dostal %/%; result=%', v_health, v_failures, v_result;
  end if;

  if not exists (
    select 1
    from public.catalog_source_reliability_report_v1()
    where source_page_code = 'bb-events'
      and health_status = 'healthy'
      and accepted = 3
      and parser_errors = 0
  ) then
    raise exception 'Reliability report nevrátil očakávaný stav.';
  end if;

  raise notice 'SOURCE RELIABILITY V1 TEST OK';
end;
$test$;

rollback;
'@

Write-Host "`n--- SOURCE RELIABILITY V1: SYNTHETICKÝ LOKÁLNY TEST ---" -ForegroundColor Cyan

$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Syntetický Source Reliability V1 test zlyhal."
}

Write-Host "`nSOURCE RELIABILITY V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
Write-Host "Empty zdroj už nie je falošné varovanie; parser error ostáva warning." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, takže nezanechal testovacie dáta." -ForegroundColor Green
