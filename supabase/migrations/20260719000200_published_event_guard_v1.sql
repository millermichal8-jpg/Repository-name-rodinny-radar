-- Rodinný radar – Published Event Guard V1
-- Trvalá ochrana pred generickými titulmi, neplatnými Praha 12 URL a chybným publikovaním.

begin;

-- Praha 12: parser smie sledovať iba skutočné detailné stránky udalostí.
-- Aktuálny tvar detailu je /nazov-podujatia/a-12345.
update private.source_pages
set
  config = config || jsonb_build_object(
    'allowedUrlRegex', '^https://www\.praha12\.cz/[^/?#]+/a-[0-9]+/?(?:[?#].*)?$',
    'linkSelector', 'a[href*="/a-"]',
    'excludeUrlRegex', '/(?:urad|kontakt|mapa)(?:/|$)'
  ),
  updated_at = now()
where code = 'praha12-events';

create or replace function private.is_generic_event_title_v1(
  p_title text
)
returns boolean
language sql
stable
security definer
set search_path = public, private, extensions, pg_temp
as $$
  select private.normalize_text(coalesce(p_title, '')) = any(array[
    'podujatia',
    'aktualne podujatia',
    'program',
    'vsetky akcie',
    'vsetky podujatia',
    'dalsie akcie',
    'dalsie podujatia',
    'kalendar akci',
    'kalendar podujati',
    'kulturni akce zabava',
    'ostatni akce',
    'kulturni akce',
    'sportovni akce',
    'akce pro deti',
    'akce pro seniory',
    'osvetova akce vystava',
    'verejna sprava',
    'typ akce',
    'jednodenni akce',
    'vicedenni akce',
    'kulturne akcie zabava',
    'ostatne akcie',
    'kulturne akcie',
    'sportove akcie',
    'akcie pre deti',
    'akcie pre seniorov',
    'osvetove akcie vystava'
  ]::text[]);
$$;

create or replace function private.event_review_readiness_v1(
  p_experience_id uuid,
  p_min_quality integer default 80
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, extensions, pg_temp
as $$
declare
  v_queue private.event_review_queue_base_v1%rowtype;
  v_min_quality integer := greatest(0, least(coalesce(p_min_quality, 80), 100));
  v_issues text[] := array[]::text[];
begin
  select *
  into v_queue
  from private.event_review_queue_base_v1 queue
  where queue.id = p_experience_id;

  if not found then
    return null;
  end if;

  if nullif(btrim(v_queue.title), '') is null then
    v_issues := array_append(v_issues, 'missing_title');
  elsif private.is_generic_event_title_v1(v_queue.title) then
    v_issues := array_append(v_issues, 'generic_title');
  end if;

  if nullif(btrim(v_queue.city), '') is null then
    v_issues := array_append(v_issues, 'missing_city');
  end if;

  if v_queue.next_starts_at is null then
    v_issues := array_append(v_issues, 'missing_future_occurrence');
  end if;

  if nullif(btrim(v_queue.official_url), '') is null then
    v_issues := array_append(v_issues, 'missing_official_url');
  end if;

  if v_queue.quality_score < v_min_quality then
    v_issues := array_append(v_issues, 'quality_below_threshold');
  end if;

  if v_queue.unresolved_duplicate_count > 0 then
    v_issues := array_append(v_issues, 'unresolved_duplicate');
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_queue.sources) source_item
    where source_item->>'code' = 'praha12_events'
  ) and not exists (
    select 1
    from jsonb_array_elements(v_queue.sources) source_item
    where source_item->>'code' = 'praha12_events'
      and coalesce(source_item->>'url', '') ~
        '^https://www[.]praha12[.]cz/[^/?#]+/a-[0-9]+/?([?#].*)?$'
  ) then
    v_issues := array_append(v_issues, 'invalid_source_detail_url');
  end if;

  return jsonb_build_object(
    'experienceId', v_queue.id,
    'readyToPublish', cardinality(v_issues) = 0,
    'issues', to_jsonb(v_issues),
    'qualityScore', v_queue.quality_score,
    'minimumQuality', v_min_quality,
    'unresolvedDuplicateCount', v_queue.unresolved_duplicate_count
  );
end;
$$;

-- Staré štyri chybné výstupy sa už nemajú vracať do review fronty.
-- Dve kategórie sú neplatné a dve kiná sa po oprave parsera vytvoria s presným termínom.
do $guard$
declare
  v_bad_ids uuid[];
begin
  select array_agg(distinct experience.id)
  into v_bad_ids
  from public.experiences experience
  where exists (
    select 1
    from public.experience_sources source_link
    join public.sources source on source.id = source_link.source_id
    where source_link.experience_id = experience.id
      and source.code = 'praha12_events'
  )
  and (
    private.is_generic_event_title_v1(experience.title)
    or private.normalize_text(experience.title) in (
      'letni kino prani k narozeninam krtiny',
      'letni kino svihaci'
    )
  );

  if coalesce(cardinality(v_bad_ids), 0) > 0 then
    update public.experiences
    set
      publication_status = 'archived',
      active = false,
      updated_at = now()
    where id = any(v_bad_ids);

    insert into private.event_review_state (
      experience_id,
      review_status,
      review_note,
      reviewed_by,
      reviewed_at,
      updated_at
    )
    select
      bad_id,
      'rejected',
      'Published Event Guard V1: neplatný generický titul alebo historický chybný termín parsera Praha 12.',
      'published-event-guard-v1',
      now(),
      now()
    from unnest(v_bad_ids) bad_id
    on conflict (experience_id) do update
    set
      review_status = excluded.review_status,
      review_note = excluded.review_note,
      reviewed_by = excluded.reviewed_by,
      reviewed_at = excluded.reviewed_at,
      updated_at = now();

    update private.source_records
    set
      processing_status = 'ignored',
      updated_at = now()
    where canonical_experience_id = any(v_bad_ids)
      and entity_kind = 'experience'
      and deleted_at is null;
  end if;
end;
$guard$;

revoke all on function private.is_generic_event_title_v1(text) from public;
revoke all on function private.event_review_readiness_v1(uuid, integer) from public;

grant execute on function private.is_generic_event_title_v1(text) to service_role;
grant execute on function private.event_review_readiness_v1(uuid, integer) to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-19-published-event-guard-v1',
  'Strict Praha 12 event URLs, explicit date precedence and permanent review publishing guards'
)
on conflict (version) do nothing;

commit;
