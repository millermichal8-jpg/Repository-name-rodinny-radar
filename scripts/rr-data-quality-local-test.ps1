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
  v_left jsonb;
  v_right jsonb;
  v_left_id uuid;
  v_right_id uuid;
  v_candidate_id uuid;
  v_refresh jsonb;
  v_merge jsonb;
  v_keep_id uuid;
  v_active_count integer;
  v_source_count integer;
  v_record_count integer;
begin
  v_left := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'zvolen_events',
    'externalId', 'dq-v1-left',
    'sourceUrl', 'https://example.test/city-event',
    'purchaseUrl', null,
    'title', 'Rodinny festival 2026',
    'summary', 'Synthetic Data Quality test.',
    'countryCode', 'SK',
    'city', 'Testov',
    'region', 'Test region',
    'venueName', 'Test arena',
    'startDate', '2026-12-05T12:00:00+01:00',
    'endDate', '2026-12-05T18:00:00+01:00',
    'freeEntry', true,
    'qualityScore', 93,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_right := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'ticketmaster',
    'externalId', 'dq-v1-right',
    'sourceUrl', 'https://example.test/ticket-event',
    'purchaseUrl', 'https://example.test/buy',
    'title', 'Velky rodinny festival 2026',
    'summary', 'Synthetic Data Quality test from ticket source.',
    'countryCode', 'SK',
    'city', 'Testov',
    'region', 'Test region',
    'venueName', 'Test arena',
    'startDate', '2026-12-05T12:30:00+01:00',
    'endDate', '2026-12-05T18:00:00+01:00',
    'priceMin', 8,
    'priceMax', 15,
    'currency', 'EUR',
    'freeEntry', false,
    'qualityScore', 96,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_left_id := (v_left->>'experienceId')::uuid;
  v_right_id := (v_right->>'experienceId')::uuid;

  if v_left_id = v_right_id then
    raise exception 'Fixture sa zlúčil už počas ingestu; test potrebuje dve rozdielne experiences.';
  end if;

  v_refresh := private.refresh_experience_dedupe_candidates_v1(365, 100);

  select review.candidate_id
  into v_candidate_id
  from private.experience_dedupe_review_v1 review
  where review.decision in ('pending', 'needs_review')
    and review.left_experience_id in (v_left_id, v_right_id)
    and review.right_experience_id in (v_left_id, v_right_id)
  order by review.similarity_score desc
  limit 1;

  if v_candidate_id is null then
    raise exception 'Data Quality V1 nevytvoril kandidáta pre syntetickú duplicitu. Refresh: %', v_refresh;
  end if;

  v_merge := private.merge_experience_duplicate_v1(
    v_candidate_id,
    null,
    'Synthetic local test',
    null
  );

  v_keep_id := (v_merge->>'keptExperienceId')::uuid;

  select count(*)
  into v_active_count
  from public.experiences
  where id in (v_left_id, v_right_id)
    and active = true
    and publication_status <> 'archived';

  if v_active_count <> 1 then
    raise exception 'Po merge musí zostať presne jedno aktívne podujatie, zostalo: %', v_active_count;
  end if;

  select count(*)
  into v_source_count
  from public.experience_sources
  where experience_id = v_keep_id;

  if v_source_count <> 2 then
    raise exception 'Zlúčené podujatie musí mať dva zdroje, má: %', v_source_count;
  end if;

  select count(*)
  into v_record_count
  from private.source_records
  where canonical_experience_id = v_keep_id
    and external_id in ('dq-v1-left', 'dq-v1-right');

  if v_record_count <> 2 then
    raise exception 'Oba source records musia smerovať na survivor, počet: %', v_record_count;
  end if;

  if not exists (
    select 1
    from private.experience_merge_log
    where candidate_id = v_candidate_id
      and kept_experience_id = v_keep_id
  ) then
    raise exception 'Chýba auditný merge log.';
  end if;

  raise notice 'DATA QUALITY V1 TEST OK';
  raise notice 'Candidate: %', v_candidate_id;
  raise notice 'Merge result: %', v_merge;
end;
$test$;

rollback;
'@

Write-Host "`n--- DATA QUALITY V1: SYNTHETICKÝ LOKÁLNY TEST ---" -ForegroundColor Cyan

$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Syntetický Data Quality test zlyhal."
}

Write-Host "`nDATA QUALITY V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, takže po sebe nezanechal testovacie dáta." -ForegroundColor Green
