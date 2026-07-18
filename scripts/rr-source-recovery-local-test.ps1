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
  v_count integer;
begin
  select count(*)
  into v_count
  from private.source_pages
  where code in (
    'ostrava-events',
    'olomouc-region-events',
    'bkis-events',
    'senec-events',
    'bb-events'
  )
    and adapter = 'generic_cards_v4'
    and coalesce(config->>'linkSelector', '') <> ''
    and coalesce(config->>'allowedUrlRegex', '') <> '';

  if v_count <> 5 then
    raise exception 'Očakávalo sa 5 obnovených zdrojov, našlo sa %.', v_count;
  end if;

  if not exists (
    select 1
    from private.source_pages
    where code = 'bkis-events'
      and config->>'allowedUrlRegex' like '%/udalost/%'
  ) then
    raise exception 'BKIS stále nepoužíva cestu /udalost/.';
  end if;

  if not exists (
    select 1
    from private.schema_versions
    where version = '2026-07-18-source-recovery-v1'
  ) then
    raise exception 'Chýba schema version Source Recovery V1.';
  end if;

  raise notice 'SOURCE RECOVERY V1 TEST OK';
end;
$test$;

rollback;
'@

Write-Host "`n--- SOURCE RECOVERY V1: LOKÁLNY TEST KONFIGURÁCIE ---" -ForegroundColor Cyan
$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Source Recovery V1 lokálny test zlyhal."
}

Write-Host "`nSOURCE RECOVERY V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
Write-Host "Všetkých päť zdrojov používa card-seeded parser a správne URL pravidlá." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, takže nezanechal testovacie dáta." -ForegroundColor Green
