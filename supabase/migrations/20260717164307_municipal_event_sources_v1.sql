-- Rodinný radar — Municipal event sources V1
-- Official municipal/cultural calendars + controlled ingestion to catalog V2.

begin;

create table if not exists private.source_pages (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  source_code text not null references public.sources(code),
  list_url text not null,
  adapter text not null default 'generic',
  country_code text not null default 'SK' check (country_code ~ '^[A-Z]{2}$'),
  default_city text,
  default_region text,
  enabled boolean not null default true,
  max_event_links integer not null default 15 check (max_event_links between 1 and 100),
  config jsonb not null default '{}'::jsonb,
  last_preview_at timestamptz,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists source_pages_set_updated_at on private.source_pages;
create trigger source_pages_set_updated_at
before update on private.source_pages
for each row execute function private.set_updated_at();

insert into public.sources (
  code,
  display_name,
  source_type,
  website_url,
  trust_level,
  is_official,
  attribution_required,
  default_cache_ttl_seconds,
  active
)
values
  (
    'banska_bystrica_events',
    'Mesto Banská Bystrica – podujatia',
    'html',
    'https://www.banskabystrica.sk/podujatia/',
    95,
    true,
    false,
    21600,
    true
  ),
  (
    'bojnice_events',
    'Mesto Bojnice – kultúrne a športové akcie',
    'html',
    'https://www.bojnice.sk/kulturne-a-sportove-akcie-0.html',
    95,
    true,
    false,
    21600,
    true
  ),
  (
    'zvolen_events',
    'Mesto Zvolen – aktuálne podujatia',
    'html',
    'https://www.zvolen.sk/aktualne-podujatia.html',
    95,
    true,
    false,
    21600,
    true
  ),
  (
    'banska_stiavnica_kultura',
    'Kultúrne centrum Banská Štiavnica',
    'html',
    'https://www.kultura.banskastiavnica.sk/',
    100,
    true,
    false,
    21600,
    true
  )
on conflict (code) do update
set
  display_name = excluded.display_name,
  source_type = excluded.source_type,
  website_url = excluded.website_url,
  trust_level = excluded.trust_level,
  is_official = excluded.is_official,
  attribution_required = excluded.attribution_required,
  default_cache_ttl_seconds = excluded.default_cache_ttl_seconds,
  active = excluded.active,
  updated_at = now();

insert into private.source_pages (
  code,
  display_name,
  source_code,
  list_url,
  adapter,
  country_code,
  default_city,
  default_region,
  max_event_links,
  enabled,
  config
)
values
  (
    'bb-events',
    'Banská Bystrica – podujatia',
    'banska_bystrica_events',
    'https://www.banskabystrica.sk/podujatia/',
    'citio',
    'SK',
    'Banská Bystrica',
    'Banskobystrický kraj',
    18,
    true,
    '{"pathHints":["/podujatia/"],"excludePathHints":["/kategorie-podujati/","/rocny-prehlad/","/page/"]}'::jsonb
  ),
  (
    'bojnice-events',
    'Bojnice – kultúrne a športové akcie',
    'bojnice_events',
    'https://www.bojnice.sk/kulturne-a-sportove-akcie-0.html',
    'webygroup',
    'SK',
    'Bojnice',
    'Trenčiansky kraj',
    15,
    true,
    '{"pathHints":["/kalendar-podujati/","/oznamy/"],"excludePathHints":["/ma0/"]}'::jsonb
  ),
  (
    'zvolen-events',
    'Zvolen – aktuálne podujatia',
    'zvolen_events',
    'https://www.zvolen.sk/aktualne-podujatia.html',
    'webygroup',
    'SK',
    'Zvolen',
    'Banskobystrický kraj',
    15,
    true,
    '{"pathHints":["/akcia/","/mid/492551/"],"excludePathHints":["/ma0/all/"]}'::jsonb
  ),
  (
    'bs-kultura',
    'Kultúrne centrum Banská Štiavnica',
    'banska_stiavnica_kultura',
    'https://www.kultura.banskastiavnica.sk/',
    'ticketware',
    'SK',
    'Banská Štiavnica',
    'Banskobystrický kraj',
    15,
    true,
    '{"pathHints":["/event/","/podujatie/","/page/"],"excludePathHints":["/registracia","/kontakty","/obchodne-podmienky"]}'::jsonb
  )
on conflict (code) do update
set
  display_name = excluded.display_name,
  source_code = excluded.source_code,
  list_url = excluded.list_url,
  adapter = excluded.adapter,
  country_code = excluded.country_code,
  default_city = excluded.default_city,
  default_region = excluded.default_region,
  max_event_links = excluded.max_event_links,
  enabled = excluded.enabled,
  config = excluded.config,
  updated_at = now();

create or replace function public.catalog_list_source_pages_v1(
  p_codes text[] default null
)
returns table (
  code text,
  display_name text,
  source_code text,
  list_url text,
  adapter text,
  country_code text,
  default_city text,
  default_region text,
  max_event_links integer,
  config jsonb
)
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select
    sp.code,
    sp.display_name,
    sp.source_code,
    sp.list_url,
    sp.adapter,
    sp.country_code,
    sp.default_city,
    sp.default_region,
    sp.max_event_links,
    sp.config
  from private.source_pages sp
  where sp.enabled = true
    and (p_codes is null or sp.code = any(p_codes))
  order by sp.code;
$$;

revoke all on function public.catalog_list_source_pages_v1(text[]) from public;
grant execute on function public.catalog_list_source_pages_v1(text[]) to service_role;

create or replace function public.catalog_ingest_web_event_v1(
  p_event jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_source_id uuid;
  v_source_code text := nullif(p_event->>'sourceCode', '');
  v_external_id text := nullif(p_event->>'externalId', '');
  v_source_url text := nullif(p_event->>'sourceUrl', '');
  v_title text := nullif(p_event->>'title', '');
  v_summary text := nullif(p_event->>'summary', '');
  v_description text := nullif(p_event->>'description', '');
  v_city text := nullif(p_event->>'city', '');
  v_region text := nullif(p_event->>'region', '');
  v_country_code text := upper(coalesce(nullif(p_event->>'countryCode', ''), 'SK'));
  v_venue_name text := nullif(p_event->>'venueName', '');
  v_address text := nullif(p_event->>'address', '');
  v_image_url text := nullif(p_event->>'imageUrl', '');
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_all_day boolean := coalesce((p_event->>'allDay')::boolean, false);
  v_free_entry boolean := coalesce((p_event->>'freeEntry')::boolean, false);
  v_price_min numeric;
  v_price_max numeric;
  v_currency char(3) := upper(coalesce(nullif(p_event->>'currency', ''), 'EUR'))::char(3);
  v_quality_score smallint := greatest(0, least(100, coalesce((p_event->>'qualityScore')::smallint, 0)));
  v_venue_id uuid;
  v_experience_id uuid;
  v_occurrence_id uuid;
  v_offer_id uuid;
  v_occurrence_key text;
  v_normalized_title text;
  v_candidate_experience uuid;
begin
  if v_source_code is null or v_external_id is null or v_source_url is null or v_title is null then
    raise exception 'Missing required event fields';
  end if;

  begin
    v_start_at := nullif(p_event->>'startDate', '')::timestamptz;
  exception when others then
    v_start_at := null;
  end;

  begin
    v_end_at := nullif(p_event->>'endDate', '')::timestamptz;
  exception when others then
    v_end_at := null;
  end;

  begin
    v_price_min := nullif(p_event->>'priceMin', '')::numeric;
  exception when others then
    v_price_min := null;
  end;

  begin
    v_price_max := nullif(p_event->>'priceMax', '')::numeric;
  exception when others then
    v_price_max := null;
  end;

  select id into v_source_id
  from public.sources
  where code = v_source_code
    and active = true;

  if v_source_id is null then
    raise exception 'Unknown source code: %', v_source_code;
  end if;

  if v_venue_name is not null or v_city is not null then
    select id into v_venue_id
    from public.venues
    where active = true
      and country_code = v_country_code
      and coalesce(city, '') = coalesce(v_city, '')
      and normalized_name = private.normalize_text(coalesce(v_venue_name, v_city))
    limit 1;

    if v_venue_id is null then
      insert into public.venues (
        name,
        formatted_address,
        city,
        region,
        country_code,
        website_url,
        active,
        last_verified_at
      )
      values (
        coalesce(v_venue_name, v_city, 'Neznáme miesto'),
        v_address,
        v_city,
        v_region,
        v_country_code,
        v_source_url,
        true,
        now()
      )
      returning id into v_venue_id;
    end if;
  end if;

  select es.experience_id into v_experience_id
  from public.experience_sources es
  where es.source_id = v_source_id
    and es.external_id = v_external_id;

  v_normalized_title := private.normalize_text(v_title);

  if v_experience_id is null and v_start_at is not null then
    select e.id into v_candidate_experience
    from public.experiences e
    join public.experience_occurrences o on o.experience_id = e.id
    left join public.venues ven on ven.id = e.venue_id
    where e.kind = 'event'
      and e.active = true
      and e.normalized_title = v_normalized_title
      and abs(extract(epoch from (o.starts_at - v_start_at))) <= 43200
      and coalesce(ven.city, '') = coalesce(v_city, '')
    order by e.quality_score desc
    limit 1;

    v_experience_id := v_candidate_experience;
  end if;

  if v_experience_id is null then
    insert into public.experiences (
      kind,
      title,
      summary,
      description,
      venue_id,
      official_url,
      primary_ticket_url,
      hero_image_url,
      free_entry,
      family_score,
      quality_score,
      publication_status,
      lifecycle_status,
      source_freshness_at,
      last_verified_at,
      active
    )
    values (
      'event',
      v_title,
      v_summary,
      v_description,
      v_venue_id,
      v_source_url,
      nullif(p_event->>'purchaseUrl', ''),
      v_image_url,
      v_free_entry,
      greatest(40, least(100, v_quality_score)),
      v_quality_score,
      'review',
      'scheduled',
      now(),
      now(),
      true
    )
    returning id into v_experience_id;
  else
    update public.experiences
    set
      title = v_title,
      summary = coalesce(v_summary, summary),
      description = coalesce(v_description, description),
      venue_id = coalesce(v_venue_id, venue_id),
      official_url = coalesce(v_source_url, official_url),
      primary_ticket_url = coalesce(nullif(p_event->>'purchaseUrl', ''), primary_ticket_url),
      hero_image_url = coalesce(v_image_url, hero_image_url),
      free_entry = v_free_entry or free_entry,
      quality_score = greatest(quality_score, v_quality_score),
      source_freshness_at = now(),
      last_verified_at = now(),
      last_seen_at = now(),
      active = true
    where id = v_experience_id;
  end if;

  insert into public.experience_sources (
    experience_id,
    source_id,
    external_id,
    source_url,
    is_primary,
    is_official,
    last_seen_at,
    last_verified_at
  )
  values (
    v_experience_id,
    v_source_id,
    v_external_id,
    v_source_url,
    true,
    true,
    now(),
    now()
  )
  on conflict (source_id, external_id) do update
  set
    experience_id = excluded.experience_id,
    source_url = excluded.source_url,
    is_official = true,
    last_seen_at = now(),
    last_verified_at = now();

  if v_start_at is not null then
    v_occurrence_key := encode(
      digest(v_source_code || '|' || v_external_id || '|' || v_start_at::text, 'sha256'),
      'hex'
    );

    insert into public.experience_occurrences (
      experience_id,
      starts_at,
      ends_at,
      timezone,
      all_day,
      status,
      occurrence_key,
      active
    )
    values (
      v_experience_id,
      v_start_at,
      v_end_at,
      'Europe/Bratislava',
      v_all_day,
      'scheduled',
      v_occurrence_key,
      true
    )
    on conflict (experience_id, occurrence_key) do update
    set
      starts_at = excluded.starts_at,
      ends_at = excluded.ends_at,
      all_day = excluded.all_day,
      status = 'scheduled',
      active = true,
      updated_at = now()
    returning id into v_occurrence_id;
  end if;

  if v_free_entry or v_price_min is not null or v_price_max is not null then
    select id into v_offer_id
    from public.ticket_offers
    where source_id = v_source_id
      and external_offer_id = v_external_id || ':default'
    limit 1;

    if v_offer_id is null then
      insert into public.ticket_offers (
        experience_id,
        occurrence_id,
        source_id,
        external_offer_id,
        offer_name,
        audience_type,
        price_min,
        price_max,
        currency,
        free_entry,
        availability,
        purchase_url,
        source_url,
        is_official,
        confidence,
        checked_at,
        active
      )
      values (
        v_experience_id,
        v_occurrence_id,
        v_source_id,
        v_external_id || ':default',
        case when v_free_entry then 'Vstup zdarma' else 'Základné vstupné' end,
        'general',
        case when v_free_entry then 0 else v_price_min end,
        case when v_free_entry then 0 else coalesce(v_price_max, v_price_min) end,
        v_currency,
        v_free_entry,
        'available',
        nullif(p_event->>'purchaseUrl', ''),
        v_source_url,
        true,
        greatest(0.5, least(1.0, v_quality_score / 100.0)),
        now(),
        true
      )
      returning id into v_offer_id;
    else
      update public.ticket_offers
      set
        experience_id = v_experience_id,
        occurrence_id = v_occurrence_id,
        price_min = case when v_free_entry then 0 else v_price_min end,
        price_max = case when v_free_entry then 0 else coalesce(v_price_max, v_price_min) end,
        currency = v_currency,
        free_entry = v_free_entry,
        availability = 'available',
        purchase_url = coalesce(nullif(p_event->>'purchaseUrl', ''), purchase_url),
        source_url = v_source_url,
        confidence = greatest(confidence, least(1.0, v_quality_score / 100.0)),
        checked_at = now(),
        active = true
      where id = v_offer_id;
    end if;
  end if;

  if v_image_url is not null and not exists (
    select 1
    from public.media_assets
    where experience_id = v_experience_id
      and url = v_image_url
  ) then
    insert into public.media_assets (
      experience_id,
      source_id,
      media_type,
      url,
      alt_text,
      sort_order,
      active
    )
    values (
      v_experience_id,
      v_source_id,
      'image',
      v_image_url,
      v_title,
      10,
      true
    );
  end if;

  insert into private.source_records (
    source_id,
    entity_kind,
    external_id,
    source_url,
    payload_hash,
    raw_payload,
    parsed_payload,
    processing_status,
    canonical_venue_id,
    canonical_experience_id,
    canonical_occurrence_id,
    canonical_offer_id,
    last_seen_at,
    fetched_at,
    updated_at
  )
  values (
    v_source_id,
    'experience',
    v_external_id,
    v_source_url,
    encode(digest(p_event::text, 'sha256'), 'hex'),
    coalesce(p_event->'raw', '{}'::jsonb),
    p_event,
    'matched',
    v_venue_id,
    v_experience_id,
    v_occurrence_id,
    v_offer_id,
    now(),
    now(),
    now()
  )
  on conflict (source_id, entity_kind, external_id) do update
  set
    source_url = excluded.source_url,
    payload_hash = excluded.payload_hash,
    raw_payload = excluded.raw_payload,
    parsed_payload = excluded.parsed_payload,
    processing_status = 'matched',
    canonical_venue_id = excluded.canonical_venue_id,
    canonical_experience_id = excluded.canonical_experience_id,
    canonical_occurrence_id = excluded.canonical_occurrence_id,
    canonical_offer_id = excluded.canonical_offer_id,
    last_seen_at = now(),
    fetched_at = now(),
    updated_at = now();

  return jsonb_build_object(
    'experienceId', v_experience_id,
    'venueId', v_venue_id,
    'occurrenceId', v_occurrence_id,
    'offerId', v_offer_id,
    'publicationStatus', 'review'
  );
end;
$$;

revoke all on function public.catalog_ingest_web_event_v1(jsonb) from public;
grant execute on function public.catalog_ingest_web_event_v1(jsonb) to service_role;

commit;
