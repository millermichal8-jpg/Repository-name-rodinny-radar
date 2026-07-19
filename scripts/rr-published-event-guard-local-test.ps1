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
  v_ingest jsonb;
  v_experience_id uuid;
  v_readiness jsonb;
  v_config jsonb;
begin
  select config
  into v_config
  from private.source_pages
  where code = 'praha12-events';

  if v_config->>'allowedUrlRegex' not like '%/a-[0-9]+%' then
    raise exception 'Praha 12 nemá prísny detailný URL filter: %', v_config;
  end if;

  if v_config->>'linkSelector' <> 'a[href*="/a-"]' then
    raise exception 'Praha 12 nemá prísny linkSelector: %', v_config;
  end if;

  v_ingest := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'zvolen_events',
    'externalId', 'published-event-guard-generic-title',
    'sourceUrl', 'https://example.test/guard/generic-title',
    'title', 'Ostatni akce',
    'summary', 'Syntetický lokálny test generického názvu.',
    'countryCode', 'CZ',
    'city', 'Testov',
    'region', 'Testovací kraj',
    'venueName', 'Testovacie centrum',
    'startDate', '2027-01-15T12:00:00+01:00',
    'qualityScore', 95,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_experience_id := (v_ingest->>'experienceId')::uuid;

  update public.experiences
  set publication_status = 'review', active = true, updated_at = now()
  where id = v_experience_id;

  v_readiness := private.event_review_readiness_v1(v_experience_id, 80);

  if coalesce((v_readiness->>'readyToPublish')::boolean, true) then
    raise exception 'Generický titul nesmie byť pripravený: %', v_readiness;
  end if;

  if not (v_readiness->'issues' ? 'generic_title') then
    raise exception 'Chýba problém generic_title: %', v_readiness;
  end if;

  v_ingest := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'praha12_events',
    'externalId', 'published-event-guard-invalid-praha12-url',
    'sourceUrl', 'https://www.praha12.cz/ap?typ_akce=1003',
    'title', 'Rodinný deň Guard neplatná URL',
    'summary', 'Syntetický test neplatnej zdrojovej URL.',
    'countryCode', 'CZ',
    'city', 'Praha',
    'region', 'Hlavní město Praha',
    'venueName', 'Testovacie centrum',
    'startDate', '2027-01-16T12:00:00+01:00',
    'qualityScore', 95,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_experience_id := (v_ingest->>'experienceId')::uuid;

  update public.experiences
  set publication_status = 'review', active = true, updated_at = now()
  where id = v_experience_id;

  v_readiness := private.event_review_readiness_v1(v_experience_id, 80);

  if not (v_readiness->'issues' ? 'invalid_source_detail_url') then
    raise exception 'Neplatná Praha 12 URL nebola zablokovaná: %', v_readiness;
  end if;

  v_ingest := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'praha12_events',
    'externalId', 'published-event-guard-valid-praha12-url',
    'sourceUrl', 'https://www.praha12.cz/rodinny-den-guard/a-99999',
    'title', 'Rodinný deň Guard platná URL',
    'summary', 'Syntetický test platnej detailnej URL.',
    'countryCode', 'CZ',
    'city', 'Praha',
    'region', 'Hlavní město Praha',
    'venueName', 'Testovacie centrum',
    'startDate', '2027-01-17T12:00:00+01:00',
    'qualityScore', 95,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_experience_id := (v_ingest->>'experienceId')::uuid;

  update public.experiences
  set publication_status = 'review', active = true, updated_at = now()
  where id = v_experience_id;

  v_readiness := private.event_review_readiness_v1(v_experience_id, 80);

  if not coalesce((v_readiness->>'readyToPublish')::boolean, false) then
    raise exception 'Platná Praha 12 položka má byť pripravená: %', v_readiness;
  end if;

  raise notice 'PUBLISHED EVENT GUARD V1 TEST OK';
end;
$test$;

rollback;
'@

Write-Host "`n--- PUBLISHED EVENT GUARD V1: LOKÁLNY TEST ---" -ForegroundColor Cyan

$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Published Event Guard V1 lokálny test zlyhal."
}

Write-Host "`nPUBLISHED EVENT GUARD V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
Write-Host "Overené: generické tituly, Praha 12 detailné URL a bezpečná review pripravenosť." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, takže nezanechal testovacie dáta." -ForegroundColor Green
