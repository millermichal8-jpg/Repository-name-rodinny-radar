-- Rodinný radar – Event Review V1
-- Bezpečné administratívne schvaľovanie, publikovanie, zamietanie a audit podujatí.
begin;

create table if not exists private.event_review_state (
  experience_id uuid primary key references public.experiences(id) on delete cascade,
  review_status text not null default 'pending'
    check (review_status in ('pending', 'approved', 'published', 'rejected')),
  review_note text,
  reviewed_by text,
  reviewed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.event_review_actions (
  id uuid primary key default gen_random_uuid(),
  experience_id uuid not null references public.experiences(id) on delete cascade,
  action text not null
    check (action in ('approve', 'publish', 'reject', 'restore', 'batch_publish')),
  from_publication_status text,
  to_publication_status text,
  from_active boolean,
  to_active boolean,
  note text,
  actor text,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists event_review_state_status_idx
  on private.event_review_state (review_status, updated_at desc);

create index if not exists event_review_actions_experience_idx
  on private.event_review_actions (experience_id, created_at desc);

create index if not exists event_review_actions_created_idx
  on private.event_review_actions (created_at desc);

create or replace view private.event_review_queue_base_v1 as
select
  experience.id,
  experience.title,
  experience.summary,
  experience.description,
  experience.publication_status,
  experience.lifecycle_status,
  experience.active,
  experience.quality_score,
  experience.family_score,
  experience.free_entry,
  experience.official_url,
  experience.primary_ticket_url,
  experience.hero_image_url,
  experience.first_seen_at,
  experience.last_seen_at,
  experience.last_verified_at,
  experience.updated_at,
  coalesce(review_state.review_status,
    case
      when experience.publication_status = 'published' then 'published'
      when experience.publication_status = 'archived' then 'rejected'
      else 'pending'
    end
  ) as review_status,
  review_state.review_note,
  review_state.reviewed_by,
  review_state.reviewed_at,
  venue.name as venue_name,
  venue.formatted_address,
  venue.city,
  venue.region,
  venue.country_code,
  next_occurrence.id as next_occurrence_id,
  next_occurrence.starts_at as next_starts_at,
  next_occurrence.ends_at as next_ends_at,
  next_occurrence.all_day as next_all_day,
  best_offer.price_min,
  best_offer.price_max,
  best_offer.currency,
  best_offer.offer_name,
  best_offer.purchase_url,
  coalesce(source_info.source_count, 0) as source_count,
  coalesce(source_info.source_codes, '[]'::jsonb) as source_codes,
  coalesce(source_info.sources, '[]'::jsonb) as sources,
  coalesce(duplicate_info.unresolved_duplicate_count, 0) as unresolved_duplicate_count
from public.experiences experience
left join private.event_review_state review_state
  on review_state.experience_id = experience.id
left join public.venues venue
  on venue.id = experience.venue_id
left join lateral (
  select occurrence.id, occurrence.starts_at, occurrence.ends_at, occurrence.all_day
  from public.experience_occurrences occurrence
  where occurrence.experience_id = experience.id
    and occurrence.active = true
    and occurrence.status in ('scheduled', 'rescheduled')
    and coalesce(occurrence.ends_at, occurrence.starts_at) >= now()
  order by occurrence.starts_at
  limit 1
) next_occurrence on true
left join lateral (
  select offer.price_min, offer.price_max, offer.currency, offer.offer_name, offer.purchase_url
  from public.ticket_offers offer
  where offer.experience_id = experience.id
    and offer.active = true
    and offer.availability not in ('sold_out', 'unavailable')
    and (offer.valid_until is null or offer.valid_until >= now())
  order by
    offer.free_entry desc,
    offer.price_min asc nulls last,
    offer.confidence desc,
    offer.checked_at desc
  limit 1
) best_offer on true
left join lateral (
  select
    count(*)::integer as source_count,
    jsonb_agg(source.code order by source.code) as source_codes,
    jsonb_agg(
      jsonb_build_object(
        'code', source.code,
        'name', source.display_name,
        'url', experience_source.source_url,
        'official', experience_source.is_official,
        'primary', experience_source.is_primary,
        'lastSeenAt', experience_source.last_seen_at
      )
      order by experience_source.is_primary desc, source.code
    ) as sources
  from public.experience_sources experience_source
  join public.sources source
    on source.id = experience_source.source_id
  where experience_source.experience_id = experience.id
) source_info on true
left join lateral (
  select count(*)::integer as unresolved_duplicate_count
  from private.experience_dedupe_review_v1 duplicate
  where duplicate.decision in ('pending', 'needs_review')
    and duplicate.similarity_score >= 0.84
    and experience.id in (duplicate.left_experience_id, duplicate.right_experience_id)
) duplicate_info on true
where experience.kind = 'event';

create or replace function private.event_review_readiness_v1(
  p_experience_id uuid,
  p_min_quality integer default 80
)
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select jsonb_build_object(
    'experienceId', queue.id,
    'readyToPublish', cardinality(array_remove(array[
      case when nullif(btrim(queue.title), '') is null then 'missing_title' end,
      case when nullif(btrim(queue.city), '') is null then 'missing_city' end,
      case when queue.next_starts_at is null then 'missing_future_occurrence' end,
      case when nullif(btrim(queue.official_url), '') is null then 'missing_official_url' end,
      case when queue.quality_score < greatest(0, least(coalesce(p_min_quality, 80), 100))
        then 'quality_below_threshold' end,
      case when queue.unresolved_duplicate_count > 0 then 'unresolved_duplicate' end
    ], null)) = 0,
    'issues', to_jsonb(array_remove(array[
      case when nullif(btrim(queue.title), '') is null then 'missing_title' end,
      case when nullif(btrim(queue.city), '') is null then 'missing_city' end,
      case when queue.next_starts_at is null then 'missing_future_occurrence' end,
      case when nullif(btrim(queue.official_url), '') is null then 'missing_official_url' end,
      case when queue.quality_score < greatest(0, least(coalesce(p_min_quality, 80), 100))
        then 'quality_below_threshold' end,
      case when queue.unresolved_duplicate_count > 0 then 'unresolved_duplicate' end
    ], null)),
    'qualityScore', queue.quality_score,
    'minimumQuality', greatest(0, least(coalesce(p_min_quality, 80), 100)),
    'unresolvedDuplicateCount', queue.unresolved_duplicate_count
  )
  from private.event_review_queue_base_v1 queue
  where queue.id = p_experience_id;
$$;

create or replace function private.event_review_queue_json_v1(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(nullif(p_payload->>'limit', '')::integer, 50), 250));
  v_offset integer := greatest(0, coalesce(nullif(p_payload->>'offset', '')::integer, 0));
  v_min_quality integer := greatest(0, least(coalesce(nullif(p_payload->>'minQuality', '')::integer, 80), 100));
  v_status text := lower(coalesce(nullif(p_payload->>'status', ''), 'review'));
  v_source_codes text[];
  v_total integer;
  v_items jsonb;
begin
  if jsonb_typeof(p_payload->'sourceCodes') = 'array' then
    select array_agg(value)
    into v_source_codes
    from jsonb_array_elements_text(p_payload->'sourceCodes') item(value);
  end if;

  with filtered as (
    select queue.*,
      private.event_review_readiness_v1(queue.id, v_min_quality) as readiness
    from private.event_review_queue_base_v1 queue
    where (
      v_status = 'all'
      or (v_status = 'review' and queue.publication_status = 'review')
      or (v_status = 'pending' and queue.publication_status = 'review' and queue.review_status = 'pending')
      or (v_status = 'approved' and queue.publication_status = 'review' and queue.review_status = 'approved')
      or (v_status = 'published' and queue.publication_status = 'published')
      or (v_status = 'rejected' and queue.publication_status = 'archived' and queue.review_status = 'rejected')
    )
    and (
      v_source_codes is null
      or exists (
        select 1
        from jsonb_array_elements_text(queue.source_codes) source_code(value)
        where source_code.value = any(v_source_codes)
      )
    )
  ),
  counted as (
    select count(*)::integer as total from filtered
  ),
  paged as (
    select *
    from filtered
    order by
      case when publication_status = 'review' then 0 else 1 end,
      (readiness->>'readyToPublish')::boolean desc,
      next_starts_at asc nulls last,
      quality_score desc,
      title
    limit v_limit offset v_offset
  )
  select
    counted.total,
    coalesce(jsonb_agg(
      jsonb_build_object(
        'id', paged.id,
        'title', paged.title,
        'summary', paged.summary,
        'publicationStatus', paged.publication_status,
        'reviewStatus', paged.review_status,
        'qualityScore', paged.quality_score,
        'familyScore', paged.family_score,
        'freeEntry', paged.free_entry,
        'officialUrl', paged.official_url,
        'ticketUrl', paged.primary_ticket_url,
        'imageUrl', paged.hero_image_url,
        'venueName', paged.venue_name,
        'address', paged.formatted_address,
        'city', paged.city,
        'region', paged.region,
        'countryCode', paged.country_code,
        'nextStartsAt', paged.next_starts_at,
        'nextEndsAt', paged.next_ends_at,
        'allDay', paged.next_all_day,
        'priceMin', paged.price_min,
        'priceMax', paged.price_max,
        'currency', paged.currency,
        'offerName', paged.offer_name,
        'purchaseUrl', paged.purchase_url,
        'sourceCount', paged.source_count,
        'sourceCodes', paged.source_codes,
        'sources', paged.sources,
        'unresolvedDuplicateCount', paged.unresolved_duplicate_count,
        'readyToPublish', (paged.readiness->>'readyToPublish')::boolean,
        'issues', paged.readiness->'issues',
        'reviewNote', paged.review_note,
        'reviewedBy', paged.reviewed_by,
        'reviewedAt', paged.reviewed_at,
        'lastVerifiedAt', paged.last_verified_at,
        'updatedAt', paged.updated_at
      )
      order by
        case when paged.publication_status = 'review' then 0 else 1 end,
        (paged.readiness->>'readyToPublish')::boolean desc,
        paged.next_starts_at asc nulls last,
        paged.quality_score desc,
        paged.title
    ) filter (where paged.id is not null), '[]'::jsonb)
  into v_total, v_items
  from counted
  left join paged on true
  group by counted.total;

  return jsonb_build_object(
    'status', v_status,
    'minimumQuality', v_min_quality,
    'limit', v_limit,
    'offset', v_offset,
    'total', coalesce(v_total, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

create or replace function private.apply_event_review_v1(
  p_experience_id uuid,
  p_action text,
  p_note text default null,
  p_actor text default 'event-review-v1',
  p_min_quality integer default 80,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_action text := lower(coalesce(p_action, ''));
  v_event public.experiences%rowtype;
  v_readiness jsonb;
  v_to_publication_status text;
  v_to_active boolean;
  v_review_status text;
begin
  if v_action not in ('approve', 'publish', 'reject', 'restore') then
    raise exception 'Nepodporovaná review akcia: %', p_action;
  end if;

  select *
  into v_event
  from public.experiences
  where id = p_experience_id
    and kind = 'event'
  for update;

  if not found then
    raise exception 'Podujatie % sa nenašlo.', p_experience_id;
  end if;

  v_readiness := private.event_review_readiness_v1(
    p_experience_id,
    greatest(0, least(coalesce(p_min_quality, 80), 100))
  );

  if v_action = 'publish'
     and coalesce((v_readiness->>'readyToPublish')::boolean, false) = false
     and not coalesce(p_force, false) then
    raise exception 'Podujatie nie je pripravené na publikovanie. Problémy: %', v_readiness->'issues';
  end if;

  if v_action = 'approve' then
    v_to_publication_status := v_event.publication_status;
    v_to_active := v_event.active;
    v_review_status := 'approved';
  elsif v_action = 'publish' then
    v_to_publication_status := 'published';
    v_to_active := true;
    v_review_status := 'published';
  elsif v_action = 'reject' then
    v_to_publication_status := 'archived';
    v_to_active := false;
    v_review_status := 'rejected';
  else
    v_to_publication_status := 'review';
    v_to_active := true;
    v_review_status := 'pending';
  end if;

  update public.experiences
  set
    publication_status = v_to_publication_status,
    active = v_to_active,
    last_verified_at = case when v_action in ('approve', 'publish') then now() else last_verified_at end,
    updated_at = now()
  where id = p_experience_id;

  insert into private.event_review_state (
    experience_id,
    review_status,
    review_note,
    reviewed_by,
    reviewed_at,
    updated_at
  )
  values (
    p_experience_id,
    v_review_status,
    nullif(p_note, ''),
    nullif(p_actor, ''),
    now(),
    now()
  )
  on conflict (experience_id) do update
  set
    review_status = excluded.review_status,
    review_note = excluded.review_note,
    reviewed_by = excluded.reviewed_by,
    reviewed_at = excluded.reviewed_at,
    updated_at = now();

  if v_action = 'publish' then
    update private.source_records
    set processing_status = 'published', updated_at = now()
    where canonical_experience_id = p_experience_id
      and entity_kind = 'experience'
      and deleted_at is null;
  elsif v_action = 'reject' then
    update private.source_records
    set processing_status = 'ignored', updated_at = now()
    where canonical_experience_id = p_experience_id
      and entity_kind = 'experience'
      and deleted_at is null;
  elsif v_action = 'restore' then
    update private.source_records
    set processing_status = 'matched', updated_at = now()
    where canonical_experience_id = p_experience_id
      and entity_kind = 'experience'
      and deleted_at is null;
  end if;

  insert into private.event_review_actions (
    experience_id,
    action,
    from_publication_status,
    to_publication_status,
    from_active,
    to_active,
    note,
    actor,
    snapshot
  )
  values (
    p_experience_id,
    v_action,
    v_event.publication_status,
    v_to_publication_status,
    v_event.active,
    v_to_active,
    nullif(p_note, ''),
    nullif(p_actor, ''),
    jsonb_build_object(
      'title', v_event.title,
      'qualityScore', v_event.quality_score,
      'readiness', v_readiness
    )
  );

  return jsonb_build_object(
    'experienceId', p_experience_id,
    'title', v_event.title,
    'action', v_action,
    'fromPublicationStatus', v_event.publication_status,
    'publicationStatus', v_to_publication_status,
    'active', v_to_active,
    'reviewStatus', v_review_status,
    'readiness', v_readiness
  );
end;
$$;

create or replace function private.batch_publish_event_review_v1(
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_limit integer := greatest(1, least(coalesce(nullif(p_payload->>'limit', '')::integer, 100), 250));
  v_min_quality integer := greatest(0, least(coalesce(nullif(p_payload->>'minQuality', '')::integer, 80), 100));
  v_actor text := coalesce(nullif(p_payload->>'actor', ''), 'event-review-v1-batch');
  v_note text := coalesce(nullif(p_payload->>'note', ''), 'Bezpečné hromadné publikovanie pripravených podujatí.');
  v_source_codes text[];
  v_row record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_published integer := 0;
begin
  if jsonb_typeof(p_payload->'sourceCodes') = 'array' then
    select array_agg(value)
    into v_source_codes
    from jsonb_array_elements_text(p_payload->'sourceCodes') item(value);
  end if;

  for v_row in
    select experience.id, experience.title
    from public.experiences experience
    join private.event_review_queue_base_v1 queue on queue.id = experience.id
    where queue.publication_status = 'review'
      and queue.active = true
      and (
        v_source_codes is null
        or exists (
          select 1
          from jsonb_array_elements_text(queue.source_codes) source_code(value)
          where source_code.value = any(v_source_codes)
        )
      )
      and coalesce((private.event_review_readiness_v1(queue.id, v_min_quality)->>'readyToPublish')::boolean, false)
    order by queue.next_starts_at asc nulls last, queue.quality_score desc, queue.title
    limit v_limit
    for update of experience skip locked
  loop
    v_result := private.apply_event_review_v1(
      v_row.id,
      'publish',
      v_note,
      v_actor,
      v_min_quality,
      false
    );

    update private.event_review_actions
    set action = 'batch_publish'
    where id = (
      select action_log.id
      from private.event_review_actions action_log
      where action_log.experience_id = v_row.id
        and action_log.action = 'publish'
      order by action_log.created_at desc
      limit 1
    );

    v_results := v_results || jsonb_build_array(v_result);
    v_published := v_published + 1;
  end loop;

  return jsonb_build_object(
    'published', v_published,
    'minimumQuality', v_min_quality,
    'limit', v_limit,
    'sourceCodes', coalesce(to_jsonb(v_source_codes), '[]'::jsonb),
    'results', v_results
  );
end;
$$;

create or replace function private.event_review_stats_v1()
returns jsonb
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select jsonb_build_object(
    'review', count(*) filter (where queue.publication_status = 'review'),
    'pending', count(*) filter (where queue.publication_status = 'review' and queue.review_status = 'pending'),
    'approved', count(*) filter (where queue.publication_status = 'review' and queue.review_status = 'approved'),
    'readyToPublish', count(*) filter (
      where queue.publication_status = 'review'
        and coalesce((private.event_review_readiness_v1(queue.id, 80)->>'readyToPublish')::boolean, false)
    ),
    'blocked', count(*) filter (
      where queue.publication_status = 'review'
        and not coalesce((private.event_review_readiness_v1(queue.id, 80)->>'readyToPublish')::boolean, false)
    ),
    'published', count(*) filter (where queue.publication_status = 'published'),
    'rejected', count(*) filter (where queue.publication_status = 'archived' and queue.review_status = 'rejected'),
    'futurePublished', count(*) filter (
      where queue.publication_status = 'published' and queue.next_starts_at is not null
    )
  )
  from private.event_review_queue_base_v1 queue;
$$;

create or replace function public.catalog_event_review_bridge_v1(
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_action text := lower(coalesce(p_action, 'queue'));
  v_experience_id uuid;
  v_confirm_write boolean := coalesce((p_payload->>'confirmWrite')::boolean, false);
  v_limit integer := greatest(1, least(coalesce(nullif(p_payload->>'limit', '')::integer, 50), 250));
  v_result jsonb;
begin
  if v_action = 'queue' then
    return private.event_review_queue_json_v1(p_payload);
  end if;

  if v_action = 'stats' then
    return private.event_review_stats_v1();
  end if;

  if v_action = 'audit' then
    select coalesce(jsonb_agg(to_jsonb(audit_row) order by audit_row.created_at desc), '[]'::jsonb)
    into v_result
    from (
      select
        action_log.id,
        action_log.experience_id as "experienceId",
        experience.title,
        action_log.action,
        action_log.from_publication_status as "fromPublicationStatus",
        action_log.to_publication_status as "toPublicationStatus",
        action_log.note,
        action_log.actor,
        action_log.snapshot,
        action_log.created_at as "createdAt"
      from private.event_review_actions action_log
      join public.experiences experience on experience.id = action_log.experience_id
      order by action_log.created_at desc
      limit v_limit
    ) audit_row;

    return jsonb_build_object('items', coalesce(v_result, '[]'::jsonb), 'limit', v_limit);
  end if;

  if v_action in ('approve', 'publish', 'reject', 'restore') then
    if not v_confirm_write then
      raise exception 'Review zápis vyžaduje confirmWrite: true.';
    end if;

    begin
      v_experience_id := nullif(p_payload->>'experienceId', '')::uuid;
    exception when others then
      v_experience_id := null;
    end;

    if v_experience_id is null then
      raise exception 'Chýba platné experienceId.';
    end if;

    return private.apply_event_review_v1(
      v_experience_id,
      v_action,
      nullif(p_payload->>'note', ''),
      coalesce(nullif(p_payload->>'actor', ''), 'event-review-v1'),
      greatest(0, least(coalesce(nullif(p_payload->>'minQuality', '')::integer, 80), 100)),
      coalesce((p_payload->>'force')::boolean, false)
    );
  end if;

  if v_action = 'batch_publish' then
    if not v_confirm_write then
      raise exception 'Hromadné publikovanie vyžaduje confirmWrite: true.';
    end if;

    return private.batch_publish_event_review_v1(p_payload);
  end if;

  raise exception 'action musí byť queue, stats, audit, approve, publish, reject, restore alebo batch_publish.';
end;
$$;

revoke all on table private.event_review_state from public;
revoke all on table private.event_review_actions from public;
revoke all on table private.event_review_queue_base_v1 from public;

revoke all on function private.event_review_readiness_v1(uuid, integer) from public;
revoke all on function private.event_review_queue_json_v1(jsonb) from public;
revoke all on function private.apply_event_review_v1(uuid, text, text, text, integer, boolean) from public;
revoke all on function private.batch_publish_event_review_v1(jsonb) from public;
revoke all on function private.event_review_stats_v1() from public;
revoke all on function public.catalog_event_review_bridge_v1(text, jsonb) from public;

grant select on table private.event_review_state to service_role;
grant select on table private.event_review_actions to service_role;
grant select on table private.event_review_queue_base_v1 to service_role;
grant execute on function public.catalog_event_review_bridge_v1(text, jsonb) to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-event-review-v1',
  'Secure event review queue, readiness checks, publishing decisions and audit log'
)
on conflict (version) do nothing;

commit;
