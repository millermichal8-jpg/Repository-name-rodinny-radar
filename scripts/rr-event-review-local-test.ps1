param()

$ErrorActionPreference = "Stop"

$dbContainer = docker ps --filter "name=supabase_db_" --format "{{.Names}}" |
    Select-Object -First 1

if (-not $dbContainer) {
    throw "Lokalny Supabase databazovy kontajner nebezi."
}

$sql = @'
\set ON_ERROR_STOP on
begin;

do $test$
declare
  v_ingest jsonb;
  v_experience_id uuid;
  v_queue jsonb;
  v_item jsonb;
  v_result jsonb;
  v_status text;
  v_active boolean;
  v_audit_count integer;
begin
  v_ingest := public.catalog_ingest_web_event_v1(jsonb_build_object(
    'sourceCode', 'zvolen_events',
    'externalId', 'event-review-v1-fixture',
    'sourceUrl', 'https://example.test/event-review-v1',
    'title', 'Rodinny festival Event Review V1',
    'summary', 'Synteticky lokalny test bez trvalych dat.',
    'countryCode', 'SK',
    'city', 'Testov',
    'region', 'Banskobystricky kraj',
    'venueName', 'Testovacie kulturne centrum',
    'startDate', '2027-12-05T12:00:00+01:00',
    'endDate', '2027-12-05T18:00:00+01:00',
    'freeEntry', true,
    'qualityScore', 95,
    'raw', jsonb_build_object('fixture', true)
  ));

  v_experience_id := (v_ingest->>'experienceId')::uuid;


  -- Force synthetic fixture into the review queue.

   update public.experiences

   set

     publication_status = 'review',

     active = true,

     updated_at = now()

   where id = v_experience_id;

  v_queue := public.catalog_event_review_bridge_v1(
    'queue',
    jsonb_build_object(
      'status', 'review',
      'minQuality', 80,
      'limit', 100,
      'sourceCodes', jsonb_build_array('zvolen_events')
    )
  );

  select item
  into v_item
  from jsonb_array_elements(v_queue->'items') item
  where item->>'id' = v_experience_id::text;

  if v_item is null then
    raise exception 'Fixture sa nenachadza v review fronte. Queue: %', v_queue;
  end if;

  if coalesce((v_item->>'readyToPublish')::boolean, false) is not true then
    raise exception 'Fixture nie je pripravena na publikovanie. Item: %', v_item;
  end if;

  v_result := public.catalog_event_review_bridge_v1(
    'approve',
    jsonb_build_object(
      'experienceId', v_experience_id,
      'confirmWrite', true,
      'actor', 'local-test',
      'note', 'Synthetic approve'
    )
  );

  select publication_status
  into v_status
  from public.experiences
  where id = v_experience_id;

  if v_status <> 'review' then
    raise exception 'Approve nema publikovat. Stav: %, result: %', v_status, v_result;
  end if;

  if not exists (
    select 1
    from private.event_review_state
    where experience_id = v_experience_id
      and review_status = 'approved'
  ) then
    raise exception 'Approve nevytvoril stav approved.';
  end if;

  v_result := public.catalog_event_review_bridge_v1(
    'publish',
    jsonb_build_object(
      'experienceId', v_experience_id,
      'confirmWrite', true,
      'actor', 'local-test',
      'minQuality', 80,
      'note', 'Synthetic publish'
    )
  );

  select publication_status, active
  into v_status, v_active
  from public.experiences
  where id = v_experience_id;

  if v_status <> 'published' or v_active is not true then
    raise exception 'Publish zlyhal. Stav: %, active: %, result: %', v_status, v_active, v_result;
  end if;

  if not exists (
    select 1
    from public.experience_feed
    where id = v_experience_id
  ) then
    raise exception 'Publikovane podujatie sa nenachadza v experience_feed.';
  end if;

  if not exists (
    select 1
    from private.source_records
    where canonical_experience_id = v_experience_id
      and processing_status = 'published'
  ) then
    raise exception 'Source record nebol oznaceny ako published.';
  end if;

  perform public.catalog_event_review_bridge_v1(
    'reject',
    jsonb_build_object(
      'experienceId', v_experience_id,
      'confirmWrite', true,
      'actor', 'local-test',
      'note', 'Synthetic reject'
    )
  );

  select publication_status, active
  into v_status, v_active
  from public.experiences
  where id = v_experience_id;

  if v_status <> 'archived' or v_active is not false then
    raise exception 'Reject zlyhal. Stav: %, active: %', v_status, v_active;
  end if;

  perform public.catalog_event_review_bridge_v1(
    'restore',
    jsonb_build_object(
      'experienceId', v_experience_id,
      'confirmWrite', true,
      'actor', 'local-test',
      'note', 'Synthetic restore'
    )
  );

  select publication_status, active
  into v_status, v_active
  from public.experiences
  where id = v_experience_id;

  if v_status <> 'review' or v_active is not true then
    raise exception 'Restore zlyhal. Stav: %, active: %', v_status, v_active;
  end if;

  select count(*)
  into v_audit_count
  from private.event_review_actions
  where experience_id = v_experience_id;

  if v_audit_count <> 4 then
    raise exception 'Ocakavane 4 audit zaznamy, naslo sa: %', v_audit_count;
  end if;

  raise notice 'EVENT REVIEW V1 TEST OK';
  raise notice 'Experience: %', v_experience_id;
  raise notice 'Queue item: %', v_item;
end;
$test$;

rollback;
'@

Write-Host "`n--- EVENT REVIEW V1: SYNTETICKY LOKALNY TEST ---" -ForegroundColor Cyan

$sql | docker exec -i $dbContainer psql -U postgres -d postgres

if ($LASTEXITCODE -ne 0) {
    throw "Synteticky Event Review V1 test zlyhal."
}

Write-Host "`nEVENT REVIEW V1 LOKALNY TEST PRESIEL." -ForegroundColor Green
Write-Host "Overene: fronta, approve, publish, experience_feed, reject, restore a audit." -ForegroundColor Green
Write-Host "Test bol v transakcii s ROLLBACK, preto nezanechal testovacie data." -ForegroundColor Green
