-- Rodinný radar – Data Quality V1
-- Bezpečná detekcia a manuálne spájanie duplicitných podujatí naprieč zdrojmi.
begin;

alter table public.media_assets
  add column if not exists updated_at timestamp with time zone
  not null default now();
create table if not exists private.experience_merge_log (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid references private.dedupe_candidates(id) on delete set null,
  kept_experience_id uuid not null references public.experiences(id) on delete restrict,
  merged_experience_id uuid not null references public.experiences(id) on delete restrict,
  similarity_score numeric(5,4),
  reason text,
  snapshot jsonb not null default '{}'::jsonb,
  merged_at timestamptz not null default now(),
  merged_by uuid,
  check (kept_experience_id <> merged_experience_id)
);

create index if not exists experience_merge_log_kept_idx
  on private.experience_merge_log (kept_experience_id, merged_at desc);

create index if not exists source_records_canonical_experience_idx
  on private.source_records (canonical_experience_id, source_id, last_seen_at desc)
  where canonical_experience_id is not null
    and entity_kind = 'experience'
    and deleted_at is null;

create or replace view private.experience_dedupe_review_v1 as
select
  candidate.id as candidate_id,
  candidate.similarity_score,
  candidate.decision,
  candidate.reasons,
  candidate.created_at,
  left_record.id as left_source_record_id,
  left_source.code as left_source_code,
  left_source.display_name as left_source_name,
  left_experience.id as left_experience_id,
  left_experience.title as left_title,
  left_experience.publication_status as left_publication_status,
  left_experience.quality_score as left_quality_score,
  left_venue.city as left_city,
  left_venue.country_code as left_country_code,
  left_occurrence.starts_at as left_starts_at,
  right_record.id as right_source_record_id,
  right_source.code as right_source_code,
  right_source.display_name as right_source_name,
  right_experience.id as right_experience_id,
  right_experience.title as right_title,
  right_experience.publication_status as right_publication_status,
  right_experience.quality_score as right_quality_score,
  right_venue.city as right_city,
  right_venue.country_code as right_country_code,
  right_occurrence.starts_at as right_starts_at
from private.dedupe_candidates candidate
join private.source_records left_record
  on left_record.id = candidate.left_source_record_id
join private.source_records right_record
  on right_record.id = candidate.right_source_record_id
join public.sources left_source
  on left_source.id = left_record.source_id
join public.sources right_source
  on right_source.id = right_record.source_id
join public.experiences left_experience
  on left_experience.id = left_record.canonical_experience_id
join public.experiences right_experience
  on right_experience.id = right_record.canonical_experience_id
left join public.venues left_venue
  on left_venue.id = left_experience.venue_id
left join public.venues right_venue
  on right_venue.id = right_experience.venue_id
left join lateral (
  select occurrence.starts_at
  from public.experience_occurrences occurrence
  where occurrence.experience_id = left_experience.id
    and occurrence.active = true
  order by
    case when coalesce(occurrence.ends_at, occurrence.starts_at) >= now() - interval '30 days'
      then 0 else 1 end,
    occurrence.starts_at
  limit 1
) left_occurrence on true
left join lateral (
  select occurrence.starts_at
  from public.experience_occurrences occurrence
  where occurrence.experience_id = right_experience.id
    and occurrence.active = true
  order by
    case when coalesce(occurrence.ends_at, occurrence.starts_at) >= now() - interval '30 days'
      then 0 else 1 end,
    occurrence.starts_at
  limit 1
) right_occurrence on true
where candidate.entity_kind = 'experience';

create or replace function private.refresh_experience_dedupe_candidates_v1(
  p_days_back integer default 180,
  p_limit integer default 2000
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions, pg_temp
as $$
declare
  v_row record;
  v_existing_id uuid;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_considered integer := 0;
  v_limit integer := greatest(1, least(coalesce(p_limit, 2000), 10000));
  v_days_back integer := greatest(1, least(coalesce(p_days_back, 180), 730));
begin
  create temporary table if not exists pg_temp.rr_dedupe_refresh_candidates (
    left_source_record_id uuid not null,
    right_source_record_id uuid not null,
    similarity_score numeric(5,4) not null,
    reasons jsonb not null,
    primary key (left_source_record_id, right_source_record_id)
  ) on commit drop;

  truncate table pg_temp.rr_dedupe_refresh_candidates;

  insert into pg_temp.rr_dedupe_refresh_candidates (
    left_source_record_id,
    right_source_record_id,
    similarity_score,
    reasons
  )
  with representative_records as (
    select distinct on (record.canonical_experience_id, record.source_id)
      record.id as source_record_id,
      record.source_id,
      record.canonical_experience_id,
      record.last_seen_at
    from private.source_records record
    where record.entity_kind = 'experience'
      and record.canonical_experience_id is not null
      and record.deleted_at is null
      and record.processing_status in ('matched', 'published')
      and record.last_seen_at >= now() - make_interval(days => v_days_back)
    order by
      record.canonical_experience_id,
      record.source_id,
      record.last_seen_at desc,
      record.id
  ),
  event_rows as (
    select
      representative.source_record_id,
      representative.source_id,
      source.code as source_code,
      source.trust_level,
      experience.id as experience_id,
      experience.title,
      experience.normalized_title,
      experience.quality_score,
      experience.publication_status,
      venue.city,
      venue.country_code,
      venue.normalized_name as normalized_venue_name,
      occurrence.starts_at
    from representative_records representative
    join public.sources source
      on source.id = representative.source_id
     and source.active = true
    join public.experiences experience
      on experience.id = representative.canonical_experience_id
     and experience.kind = 'event'
     and experience.active = true
    left join public.venues venue
      on venue.id = experience.venue_id
    left join lateral (
      select item.starts_at
      from public.experience_occurrences item
      where item.experience_id = experience.id
        and item.active = true
        and coalesce(item.ends_at, item.starts_at) >= now() - interval '30 days'
      order by item.starts_at
      limit 1
    ) occurrence on true
    where occurrence.starts_at is not null
  ),
  raw_pairs as (
    select
      least(left_event.source_record_id, right_event.source_record_id) as left_source_record_id,
      greatest(left_event.source_record_id, right_event.source_record_id) as right_source_record_id,
      left_event.experience_id as left_experience_id,
      right_event.experience_id as right_experience_id,
      left_event.source_code as left_source_code,
      right_event.source_code as right_source_code,
      left_event.title as left_title,
      right_event.title as right_title,
      left_event.city as left_city,
      right_event.city as right_city,
      left_event.starts_at as left_starts_at,
      right_event.starts_at as right_starts_at,
      metrics.title_similarity,
      metrics.venue_similarity,
      metrics.same_city,
      metrics.start_delta_minutes,
      metrics.time_similarity,
      round((
        metrics.title_similarity * 0.58
        + metrics.time_similarity * 0.22
        + metrics.same_city * 0.15
        + metrics.venue_similarity * 0.05
      )::numeric, 4) as similarity_score
    from event_rows left_event
    join event_rows right_event
      on left_event.source_record_id < right_event.source_record_id
     and left_event.source_id <> right_event.source_id
     and left_event.experience_id <> right_event.experience_id
     and coalesce(left_event.country_code, '') = coalesce(right_event.country_code, '')
    cross join lateral (
      select
        extensions.similarity(
          coalesce(left_event.normalized_title, ''),
          coalesce(right_event.normalized_title, '')
        )::numeric as title_similarity,
        case
          when coalesce(left_event.normalized_venue_name, '') = ''
            or coalesce(right_event.normalized_venue_name, '') = '' then 0.30::numeric
          else extensions.similarity(
            left_event.normalized_venue_name,
            right_event.normalized_venue_name
          )::numeric
        end as venue_similarity,
        case
          when private.normalize_text(left_event.city) <> ''
           and private.normalize_text(left_event.city) = private.normalize_text(right_event.city)
            then 1.00::numeric
          when coalesce(left_event.city, '') = '' or coalesce(right_event.city, '') = ''
            then 0.35::numeric
          else 0.00::numeric
        end as same_city,
        abs(extract(epoch from (left_event.starts_at - right_event.starts_at))) / 60.0
          as start_delta_minutes,
        case
          when abs(extract(epoch from (left_event.starts_at - right_event.starts_at))) <= 3600
            then 1.00::numeric
          when abs(extract(epoch from (left_event.starts_at - right_event.starts_at))) <= 21600
            then 0.90::numeric
          when (left_event.starts_at at time zone 'Europe/Bratislava')::date
             = (right_event.starts_at at time zone 'Europe/Bratislava')::date
            then 0.80::numeric
          when abs(extract(epoch from (left_event.starts_at - right_event.starts_at))) <= 86400
            then 0.55::numeric
          else 0.00::numeric
        end as time_similarity
    ) metrics
    where metrics.title_similarity >= 0.55
      and metrics.start_delta_minutes <= 1440
      and (
        metrics.same_city = 1.00
        or metrics.title_similarity >= 0.85
      )
  ),
  filtered_pairs as (
    select
      pair.left_source_record_id,
      pair.right_source_record_id,
      pair.similarity_score,
      jsonb_build_object(
        'leftExperienceId', pair.left_experience_id,
        'rightExperienceId', pair.right_experience_id,
        'leftSourceCode', pair.left_source_code,
        'rightSourceCode', pair.right_source_code,
        'leftTitle', pair.left_title,
        'rightTitle', pair.right_title,
        'leftCity', pair.left_city,
        'rightCity', pair.right_city,
        'leftStartsAt', pair.left_starts_at,
        'rightStartsAt', pair.right_starts_at,
        'titleSimilarity', round(pair.title_similarity, 4),
        'venueSimilarity', round(pair.venue_similarity, 4),
        'sameCity', pair.same_city = 1.00,
        'startDeltaMinutes', round(pair.start_delta_minutes::numeric, 2),
        'autoMergeEligible',
          pair.similarity_score >= 0.94
          and pair.title_similarity >= 0.92
          and pair.same_city = 1.00
          and pair.start_delta_minutes <= 120
      ) as reasons
    from raw_pairs pair
    where pair.similarity_score >= 0.72
    order by pair.similarity_score desc
    limit v_limit
  )
  select
    candidate.left_source_record_id,
    candidate.right_source_record_id,
    candidate.similarity_score,
    candidate.reasons
  from filtered_pairs candidate;

  select count(*) into v_considered
  from pg_temp.rr_dedupe_refresh_candidates;

  for v_row in
    select *
    from pg_temp.rr_dedupe_refresh_candidates
    order by similarity_score desc
  loop
    select candidate.id
    into v_existing_id
    from private.dedupe_candidates candidate
    where candidate.entity_kind = 'experience'
      and least(candidate.left_source_record_id, candidate.right_source_record_id)
        = v_row.left_source_record_id
      and greatest(candidate.left_source_record_id, candidate.right_source_record_id)
        = v_row.right_source_record_id
    limit 1;

    if v_existing_id is null then
      insert into private.dedupe_candidates (
        entity_kind,
        left_source_record_id,
        right_source_record_id,
        similarity_score,
        reasons,
        decision
      )
      values (
        'experience',
        v_row.left_source_record_id,
        v_row.right_source_record_id,
        v_row.similarity_score,
        v_row.reasons,
        'pending'
      );
      v_inserted := v_inserted + 1;
    else
      update private.dedupe_candidates
      set
        similarity_score = v_row.similarity_score,
        reasons = v_row.reasons
          || jsonb_build_object('refreshedAt', now()),
        decision = case
          when decision = 'needs_review' then 'needs_review'
          else decision
        end
      where id = v_existing_id
        and decision in ('pending', 'needs_review');

      if found then
        v_updated := v_updated + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'version', 'data-quality-v1',
    'considered', v_considered,
    'inserted', v_inserted,
    'updated', v_updated,
    'pendingTotal', (
      select count(*)
      from private.dedupe_candidates
      where entity_kind = 'experience'
        and decision in ('pending', 'needs_review')
    )
  );
end;
$$;

create or replace function private.merge_experience_duplicate_v1(
  p_candidate_id uuid,
  p_keep_experience_id uuid default null,
  p_reason text default null,
  p_merged_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_candidate private.dedupe_candidates%rowtype;
  v_left_experience_id uuid;
  v_right_experience_id uuid;
  v_keep_experience_id uuid;
  v_merge_experience_id uuid;
  v_keep public.experiences%rowtype;
  v_merge public.experiences%rowtype;
  v_snapshot jsonb;
  v_occurrence record;
  v_existing_occurrence_id uuid;
  v_primary_source_id uuid;
  v_primary_external_id text;
  v_sources_moved integer := 0;
  v_occurrences_moved integer := 0;
  v_offers_moved integer := 0;
  v_media_moved integer := 0;
begin
  select *
  into v_candidate
  from private.dedupe_candidates
  where id = p_candidate_id
    and entity_kind = 'experience'
  for update;

  if not found then
    raise exception 'Deduplikačný kandidát neexistuje.';
  end if;

  if v_candidate.decision not in ('pending', 'needs_review') then
    raise exception 'Kandidát už bol rozhodnutý: %', v_candidate.decision;
  end if;

  select canonical_experience_id
  into v_left_experience_id
  from private.source_records
  where id = v_candidate.left_source_record_id;

  select canonical_experience_id
  into v_right_experience_id
  from private.source_records
  where id = v_candidate.right_source_record_id;

  if v_left_experience_id is null
     or v_right_experience_id is null
     or v_left_experience_id = v_right_experience_id then
    raise exception 'Kandidát už neodkazuje na dve rozdielne podujatia.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    least(v_left_experience_id::text, v_right_experience_id::text),
    0
  ));

  if p_keep_experience_id is not null then
    if p_keep_experience_id not in (v_left_experience_id, v_right_experience_id) then
      raise exception 'keepExperienceId nepatrí do zvoleného kandidáta.';
    end if;
    v_keep_experience_id := p_keep_experience_id;
  else
    select candidate_experience.id
    into v_keep_experience_id
    from public.experiences candidate_experience
    where candidate_experience.id in (v_left_experience_id, v_right_experience_id)
    order by
      case candidate_experience.publication_status
        when 'published' then 4
        when 'review' then 3
        when 'draft' then 2
        else 1
      end desc,
      candidate_experience.quality_score desc,
      (
        select count(*)
        from public.experience_sources source_link
        where source_link.experience_id = candidate_experience.id
      ) desc,
      candidate_experience.created_at asc
    limit 1;
  end if;

  v_merge_experience_id := case
    when v_keep_experience_id = v_left_experience_id then v_right_experience_id
    else v_left_experience_id
  end;

  select * into v_keep
  from public.experiences
  where id = v_keep_experience_id
  for update;

  select * into v_merge
  from public.experiences
  where id = v_merge_experience_id
  for update;

  if v_keep.kind <> 'event' or v_merge.kind <> 'event' then
    raise exception 'Data Quality V1 spája iba podujatia.';
  end if;

  select jsonb_build_object(
    'candidateId', p_candidate_id,
    'keep', to_jsonb(v_keep),
    'merge', to_jsonb(v_merge),
    'keepSourceCount', (
      select count(*) from public.experience_sources where experience_id = v_keep_experience_id
    ),
    'mergeSourceCount', (
      select count(*) from public.experience_sources where experience_id = v_merge_experience_id
    ),
    'keepOccurrenceCount', (
      select count(*) from public.experience_occurrences where experience_id = v_keep_experience_id
    ),
    'mergeOccurrenceCount', (
      select count(*) from public.experience_occurrences where experience_id = v_merge_experience_id
    )
  ) into v_snapshot;

  update public.experiences kept
  set
    summary = coalesce(kept.summary, v_merge.summary),
    description = case
      when length(coalesce(v_merge.description, '')) > length(coalesce(kept.description, ''))
        then v_merge.description
      else kept.description
    end,
    venue_id = coalesce(kept.venue_id, v_merge.venue_id),
    organizer_id = coalesce(kept.organizer_id, v_merge.organizer_id),
    official_url = coalesce(kept.official_url, v_merge.official_url),
    primary_ticket_url = coalesce(kept.primary_ticket_url, v_merge.primary_ticket_url),
    hero_image_url = coalesce(kept.hero_image_url, v_merge.hero_image_url),
    age_min = coalesce(kept.age_min, v_merge.age_min),
    age_max = coalesce(kept.age_max, v_merge.age_max),
    indoor = coalesce(kept.indoor, v_merge.indoor),
    outdoor = coalesce(kept.outdoor, v_merge.outdoor),
    stroller_friendly = coalesce(kept.stroller_friendly, v_merge.stroller_friendly),
    wheelchair_accessible = coalesce(kept.wheelchair_accessible, v_merge.wheelchair_accessible),
    pet_friendly = coalesce(kept.pet_friendly, v_merge.pet_friendly),
    free_entry = coalesce(kept.free_entry, false) or coalesce(v_merge.free_entry, false),
    family_score = greatest(kept.family_score, v_merge.family_score),
    quality_score = greatest(kept.quality_score, v_merge.quality_score),
    publication_status = case
      when kept.publication_status = 'published' or v_merge.publication_status = 'published' then 'published'
      when kept.publication_status = 'review' or v_merge.publication_status = 'review' then 'review'
      when kept.publication_status = 'draft' or v_merge.publication_status = 'draft' then 'draft'
      else 'archived'
    end,
    lifecycle_status = case
      when kept.lifecycle_status = 'active' or v_merge.lifecycle_status = 'active' then 'active'
      else kept.lifecycle_status
    end,
    source_freshness_at = greatest(kept.source_freshness_at, v_merge.source_freshness_at),
    last_verified_at = greatest(kept.last_verified_at, v_merge.last_verified_at),
    first_seen_at = least(kept.first_seen_at, v_merge.first_seen_at),
    last_seen_at = greatest(kept.last_seen_at, v_merge.last_seen_at),
    active = kept.active or v_merge.active,
    updated_at = now()
  where kept.id = v_keep_experience_id;

  insert into public.experience_categories (
    experience_id,
    category_code,
    is_primary,
    confidence
  )
  select
    v_keep_experience_id,
    category.category_code,
    category.is_primary,
    category.confidence
  from public.experience_categories category
  where category.experience_id = v_merge_experience_id
  on conflict (experience_id, category_code) do update
  set
    is_primary = public.experience_categories.is_primary or excluded.is_primary,
    confidence = greatest(public.experience_categories.confidence, excluded.confidence);

  delete from public.experience_categories
  where experience_id = v_merge_experience_id;

  for v_occurrence in
    select *
    from public.experience_occurrences
    where experience_id = v_merge_experience_id
    order by starts_at, id
  loop
    select occurrence.id
    into v_existing_occurrence_id
    from public.experience_occurrences occurrence
    where occurrence.experience_id = v_keep_experience_id
      and occurrence.occurrence_key = v_occurrence.occurrence_key
    limit 1;

    if v_existing_occurrence_id is null then
      update public.experience_occurrences
      set experience_id = v_keep_experience_id
      where id = v_occurrence.id;
      v_occurrences_moved := v_occurrences_moved + 1;
    else
      update public.ticket_offers
      set occurrence_id = v_existing_occurrence_id
      where occurrence_id = v_occurrence.id;

      update private.source_records
      set canonical_occurrence_id = v_existing_occurrence_id,
          updated_at = now()
      where canonical_occurrence_id = v_occurrence.id;

      delete from public.experience_occurrences
      where id = v_occurrence.id;
    end if;
  end loop;

  update public.ticket_offers
  set experience_id = v_keep_experience_id,
      updated_at = now()
  where experience_id = v_merge_experience_id;
  get diagnostics v_offers_moved = row_count;

  update public.media_assets
  set experience_id = v_keep_experience_id,
      updated_at = now()
  where experience_id = v_merge_experience_id;
  get diagnostics v_media_moved = row_count;

  update public.experience_sources
  set experience_id = v_keep_experience_id,
      is_primary = false,
      last_verified_at = coalesce(last_verified_at, now())
  where experience_id = v_merge_experience_id;
  get diagnostics v_sources_moved = row_count;

  update private.source_records
  set canonical_experience_id = v_keep_experience_id,
      updated_at = now()
  where canonical_experience_id = v_merge_experience_id;

  update private.quality_issues
  set entity_id = v_keep_experience_id
  where entity_kind = 'experience'
    and entity_id = v_merge_experience_id;

  update public.experience_sources
  set is_primary = false
  where experience_id = v_keep_experience_id;

  select source_link.source_id, source_link.external_id
  into v_primary_source_id, v_primary_external_id
  from public.experience_sources source_link
  join public.sources source
    on source.id = source_link.source_id
  where source_link.experience_id = v_keep_experience_id
  order by
    source_link.is_official desc,
    source.trust_level desc,
    source_link.last_verified_at desc nulls last,
    source_link.first_seen_at asc
  limit 1;

  if v_primary_source_id is not null then
    update public.experience_sources
    set is_primary = true
    where experience_id = v_keep_experience_id
      and source_id = v_primary_source_id
      and external_id = v_primary_external_id;
  end if;

  update public.experiences
  set
    publication_status = 'archived',
    lifecycle_status = 'completed',
    active = false,
    updated_at = now()
  where id = v_merge_experience_id;

  update private.dedupe_candidates candidate
  set
    decision = 'merged',
    decided_at = now(),
    decided_by = p_merged_by,
    reasons = candidate.reasons || jsonb_build_object(
      'keptExperienceId', v_keep_experience_id,
      'mergedExperienceId', v_merge_experience_id,
      'mergeReason', p_reason,
      'mergedAt', now()
    )
  where candidate.id = p_candidate_id;

  update private.dedupe_candidates candidate
  set
    decision = 'merged',
    decided_at = coalesce(candidate.decided_at, now()),
    reasons = candidate.reasons || jsonb_build_object(
      'resolvedByCanonicalMerge', true,
      'keptExperienceId', v_keep_experience_id
    )
  where candidate.entity_kind = 'experience'
    and candidate.decision in ('pending', 'needs_review')
    and exists (
      select 1
      from private.source_records left_record
      join private.source_records right_record
        on right_record.id = candidate.right_source_record_id
      where left_record.id = candidate.left_source_record_id
        and left_record.canonical_experience_id = right_record.canonical_experience_id
        and left_record.canonical_experience_id = v_keep_experience_id
    );

  insert into private.experience_merge_log (
    candidate_id,
    kept_experience_id,
    merged_experience_id,
    similarity_score,
    reason,
    snapshot,
    merged_by
  )
  values (
    p_candidate_id,
    v_keep_experience_id,
    v_merge_experience_id,
    v_candidate.similarity_score,
    p_reason,
    v_snapshot,
    p_merged_by
  );

  return jsonb_build_object(
    'version', 'data-quality-v1',
    'candidateId', p_candidate_id,
    'keptExperienceId', v_keep_experience_id,
    'mergedExperienceId', v_merge_experience_id,
    'sourcesMoved', v_sources_moved,
    'occurrencesMoved', v_occurrences_moved,
    'offersMoved', v_offers_moved,
    'mediaMoved', v_media_moved,
    'decision', 'merged'
  );
end;
$$;

create or replace function public.catalog_data_quality_bridge_v1(
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_limit integer := greatest(1, least(coalesce((p_payload->>'limit')::integer, 50), 500));
  v_candidate_id uuid;
  v_keep_experience_id uuid;
  v_result jsonb;
begin
  if p_action = 'refresh_candidates' then
    return private.refresh_experience_dedupe_candidates_v1(
      greatest(1, least(coalesce((p_payload->>'daysBack')::integer, 180), 730)),
      greatest(1, least(coalesce((p_payload->>'scanLimit')::integer, 2000), 10000))
    );
  end if;

  if p_action = 'list_candidates' then
    select coalesce(jsonb_agg(to_jsonb(review_row) order by review_row.similarity_score desc), '[]'::jsonb)
    into v_result
    from (
      select *
      from private.experience_dedupe_review_v1
      where decision in ('pending', 'needs_review')
      order by similarity_score desc, created_at
      limit v_limit
    ) review_row;
    return v_result;
  end if;

  if p_action = 'stats' then
    return jsonb_build_object(
      'pending', (
        select count(*) from private.dedupe_candidates
        where entity_kind = 'experience' and decision = 'pending'
      ),
      'needsReview', (
        select count(*) from private.dedupe_candidates
        where entity_kind = 'experience' and decision = 'needs_review'
      ),
      'merged', (
        select count(*) from private.dedupe_candidates
        where entity_kind = 'experience' and decision = 'merged'
      ),
      'autoMergeEligible', (
        select count(*) from private.dedupe_candidates
        where entity_kind = 'experience'
          and decision in ('pending', 'needs_review')
          and coalesce((reasons->>'autoMergeEligible')::boolean, false) = true
      )
    );
  end if;

  if p_action = 'merge_candidate' then
    if coalesce((p_payload->>'confirmWrite')::boolean, false) is not true then
      raise exception 'Spájanie vyžaduje confirmWrite: true.';
    end if;

    v_candidate_id := nullif(p_payload->>'candidateId', '')::uuid;
    v_keep_experience_id := nullif(p_payload->>'keepExperienceId', '')::uuid;

    if v_candidate_id is null then
      raise exception 'Chýba candidateId.';
    end if;

    return private.merge_experience_duplicate_v1(
      v_candidate_id,
      v_keep_experience_id,
      nullif(p_payload->>'reason', ''),
      nullif(p_payload->>'mergedBy', '')::uuid
    );
  end if;

  raise exception 'Neznáma Data Quality akcia: %', p_action;
end;
$$;

revoke all on table private.experience_merge_log from public;
revoke all on table private.experience_dedupe_review_v1 from public;
revoke all on function private.refresh_experience_dedupe_candidates_v1(integer, integer) from public;
revoke all on function private.merge_experience_duplicate_v1(uuid, uuid, text, uuid) from public;
revoke all on function public.catalog_data_quality_bridge_v1(text, jsonb) from public;

grant select on table private.experience_merge_log to service_role;
grant select on table private.experience_dedupe_review_v1 to service_role;
grant execute on function private.refresh_experience_dedupe_candidates_v1(integer, integer) to service_role;
grant execute on function private.merge_experience_duplicate_v1(uuid, uuid, text, uuid) to service_role;
grant execute on function public.catalog_data_quality_bridge_v1(text, jsonb) to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-data-quality-v1',
  'Cross-source event duplicate candidates, review view and safe manual merge with audit log'
)
on conflict (version) do nothing;

commit;
