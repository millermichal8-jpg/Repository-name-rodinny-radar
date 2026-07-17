-- Rodinný radar — Data Expansion V1
-- Source registry for all 8 Slovak regions + Czech wave 1, source health and batch reporting.
-- New sources are available for manual preview, but Cron remains disabled until they pass review.

begin;

alter table private.source_pages
  add column if not exists group_code text not null default 'legacy',
  add column if not exists priority integer not null default 100,
  add column if not exists cron_enabled boolean not null default false,
  add column if not exists health_status text not null default 'unknown',
  add column if not exists consecutive_failures integer not null default 0,
  add column if not exists last_duration_ms integer,
  add column if not exists last_result jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_pages_priority_check'
      and conrelid = 'private.source_pages'::regclass
  ) then
    alter table private.source_pages
      add constraint source_pages_priority_check check (priority between 1 and 1000);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_pages_consecutive_failures_check'
      and conrelid = 'private.source_pages'::regclass
  ) then
    alter table private.source_pages
      add constraint source_pages_consecutive_failures_check check (consecutive_failures >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'source_pages_health_status_check'
      and conrelid = 'private.source_pages'::regclass
  ) then
    alter table private.source_pages
      add constraint source_pages_health_status_check
      check (health_status in ('unknown', 'healthy', 'warning', 'failing', 'disabled'));
  end if;
end;
$$;

create index if not exists source_pages_group_priority_idx
  on private.source_pages (group_code, enabled, priority, code);

create index if not exists source_pages_health_idx
  on private.source_pages (health_status, consecutive_failures desc, updated_at desc);

create table if not exists private.source_sync_runs (
  id uuid primary key default gen_random_uuid(),
  source_page_id uuid not null references private.source_pages(id) on delete cascade,
  action text not null check (action in ('preview', 'sync')),
  started_at timestamptz not null,
  finished_at timestamptz not null default now(),
  duration_ms integer not null check (duration_ms >= 0),
  success boolean not null,
  stats jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists source_sync_runs_source_started_idx
  on private.source_sync_runs (source_page_id, started_at desc);

create index if not exists source_sync_runs_failed_idx
  on private.source_sync_runs (started_at desc)
  where success = false;

-- Preserve the verified V3 adapters and classify the existing sources by region.
update private.source_pages
set
  group_code = case
    when code = 'bojnice-events' then 'sk-tn'
    else 'sk-bb'
  end,
  priority = case
    when code = 'bs-kultura' then 10
    when code = 'zvolen-events' then 20
    when code = 'bojnice-events' then 20
    else 30
  end,
  cron_enabled = false,
  updated_at = now()
where code in ('bb-events', 'bojnice-events', 'zvolen-events', 'bs-kultura');

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
  ('bkis_events', 'Bratislavské kultúrne a informačné stredisko – podujatia', 'html', 'https://www.bkis.sk/podujatia/', 100, true, false, 21600, true),
  ('senec_events', 'Mesto Senec – podujatia', 'html', 'https://www.senec.sk/podujatia/', 95, true, false, 21600, true),
  ('trnava_city_events', 'Mesto Trnava – podujatia', 'html', 'https://www.trnava.sk/podujatia', 95, true, false, 21600, true),
  ('trnava_kultura_events', 'Kultúra Trnava – kalendár', 'html', 'https://kultura.trnava.sk/kalendar', 95, true, false, 21600, true),
  ('visit_trencin_events', 'Visit Trenčín – podujatia', 'html', 'https://visit.trencin.sk/podujatia/', 95, true, false, 21600, true),
  ('nitra_city_events', 'Mesto Nitra – kultúrna ponuka', 'html', 'https://nitra.sk/kulturna-ponuka/', 95, true, false, 21600, true),
  ('zilina_city_events', 'Mesto Žilina – podujatia', 'html', 'https://zilina.sk/podujatia/', 95, true, false, 21600, true),
  ('tvrdosin_events', 'Mesto Tvrdošín – podujatia', 'html', 'https://www.tvrdosin.sk/', 95, true, false, 21600, true),
  ('pko_presov_events', 'PKO Prešov – podujatia', 'html', 'https://podujatia.pkopresov.sk/', 95, true, false, 21600, true),
  ('velky_saris_events', 'Mesto Veľký Šariš – podujatia', 'html', 'https://www.velkysaris.sk/', 95, true, false, 21600, true),
  ('visit_kosice_events', 'Visit Košice – aktuálne podujatia', 'html', 'https://visitkosice.org/podujatia/kategorie/aktualne-podujatia', 95, true, false, 21600, true),
  ('praha12_events', 'Praha 12 – kalendár akcií', 'html', 'https://www.praha12.cz/ap', 95, true, false, 21600, true),
  ('brno_events', 'Go To Brno – kalendár akcií', 'html', 'https://www.gotobrno.cz/kalendar-akci/', 90, true, false, 21600, true),
  ('ostrava_events', 'OstravaInfo – akcie', 'html', 'https://www.ostravainfo.cz/cz/akce/', 90, true, false, 21600, true),
  ('olomouc_region_events', 'Olomoucký kraj – kalendár', 'html', 'https://www.olkraj.cz/kalendar', 95, true, false, 21600, true),
  ('usti_events', 'Mesto Ústí nad Labem – kalendár akcií', 'html', 'https://www.usti.cz/cz/volny-cas/kalendar-akci.html', 95, true, false, 21600, true),
  ('liberec_events', 'Visit Liberec – kalendár akcií', 'html', 'https://www.visitliberec.eu/kalendar-akci/', 90, true, false, 21600, true),
  ('plzen_events', 'Akce Plzeň – kalendár', 'html', 'https://akce.plzen.eu/', 90, true, false, 21600, true)
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
  group_code,
  priority,
  cron_enabled,
  config
)
values
  (
    'bkis-events', 'Bratislava – BKIS', 'bkis_events', 'https://www.bkis.sk/podujatia/',
    'generic_detail_v4', 'SK', 'Bratislava', 'Bratislavský kraj', 30, true, 'sk-ba', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.bkis\.sk/podujatia/[^/?#]+/?$',
      'excludeUrlRegex', '/(?:kategoria|tag|page)/',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'senec-events', 'Senec – podujatia', 'senec_events', 'https://www.senec.sk/podujatia/',
    'generic_detail_v4', 'SK', 'Senec', 'Bratislavský kraj', 30, true, 'sk-ba', 20, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.senec\.sk/podujatia/[^/?#]+/?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'trnava-city-events', 'Trnava – mestské podujatia', 'trnava_city_events', 'https://www.trnava.sk/podujatia',
    'generic_cards_v4', 'SK', 'Trnava', 'Trnavský kraj', 30, true, 'sk-tt', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.trnava\.sk/(?:podujatie|podujatia)/',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'trnava-kultura-events', 'Kultúra Trnava – kalendár', 'trnava_kultura_events', 'https://kultura.trnava.sk/kalendar',
    'generic_cards_v4', 'SK', 'Trnava', 'Trnavský kraj', 30, true, 'sk-tt', 20, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://kultura\.trnava\.sk/',
      'excludeUrlRegex', '/(?:kontakt|o-nas|organizacie|kalendar/?$)',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'visit-trencin-events', 'Trenčín – podujatia', 'visit_trencin_events', 'https://visit.trencin.sk/podujatia/',
    'generic_detail_v4', 'SK', 'Trenčín', 'Trenčiansky kraj', 35, true, 'sk-tn', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://visit\.trencin\.sk/podujatia/\?id=[0-9]+$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'nitra-city-events', 'Nitra – kultúrna ponuka', 'nitra_city_events', 'https://nitra.sk/kulturna-ponuka/',
    'generic_cards_v4', 'SK', 'Nitra', 'Nitriansky kraj', 30, true, 'sk-nr', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://nitra\.sk/',
      'excludeUrlRegex', '/(?:kontakt|urad|samosprava|kategoria|tag|page)/',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'zilina-events', 'Žilina – podujatia', 'zilina_city_events', 'https://zilina.sk/podujatia/',
    'generic_detail_v4', 'SK', 'Žilina', 'Žilinský kraj', 35, true, 'sk-za', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://zilina\.sk/podujatie/[^/?#]+/?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'tvrdosin-events', 'Tvrdošín – podujatia', 'tvrdosin_events', 'https://www.tvrdosin.sk/',
    'generic_detail_v4', 'SK', 'Tvrdošín', 'Žilinský kraj', 25, true, 'sk-za', 20, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.tvrdosin\.sk/mid/[0-9]+/akcia/[^?#]+\.html$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'pko-presov-events', 'Prešov – PKO podujatia', 'pko_presov_events', 'https://podujatia.pkopresov.sk/',
    'generic_detail_v4', 'SK', 'Prešov', 'Prešovský kraj', 35, true, 'sk-po', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://podujatia\.pkopresov\.sk/event-detail/[a-fA-F0-9]+/?(?:\?[^#]*)?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'velky-saris-events', 'Veľký Šariš – podujatia', 'velky_saris_events', 'https://www.velkysaris.sk/',
    'generic_detail_v4', 'SK', 'Veľký Šariš', 'Prešovský kraj', 25, true, 'sk-po', 20, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.velkysaris\.sk/mid/[0-9]+/akcia/[^?#]+\.html$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'visit-kosice-events', 'Košice – aktuálne podujatia', 'visit_kosice_events', 'https://visitkosice.org/podujatia/kategorie/aktualne-podujatia',
    'generic_cards_v4', 'SK', 'Košice', 'Košický kraj', 40, true, 'sk-ke', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://visitkosice\.org/podujatia/',
      'excludeUrlRegex', '/kategorie/[^/?#]+/?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'EUR'
    )
  ),
  (
    'praha12-events', 'Praha 12 – kalendár akcií', 'praha12_events', 'https://www.praha12.cz/ap',
    'generic_cards_v4', 'CZ', 'Praha', 'Hlavní město Praha', 30, true, 'cz-wave1', 10, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.praha12\.cz/',
      'excludeUrlRegex', '/(?:urad|kontakt|mapa|ap$)',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'brno-events', 'Brno – kalendár akcií', 'brno_events', 'https://www.gotobrno.cz/kalendar-akci/',
    'generic_cards_v4', 'CZ', 'Brno', 'Jihomoravský kraj', 35, true, 'cz-wave1', 20, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.gotobrno\.cz/akce/',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'ostrava-events', 'Ostrava – akcie', 'ostrava_events', 'https://www.ostravainfo.cz/cz/akce/',
    'generic_detail_v4', 'CZ', 'Ostrava', 'Moravskoslezský kraj', 35, true, 'cz-wave1', 30, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.ostravainfo\.cz/cz/akce/[^?#]+/[0-9]+-[^/?#]+\.html$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'olomouc-region-events', 'Olomoucký kraj – kalendár', 'olomouc_region_events', 'https://www.olkraj.cz/kalendar',
    'generic_detail_v4', 'CZ', 'Olomouc', 'Olomoucký kraj', 30, true, 'cz-wave1', 40, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.olkraj\.cz/kalendar/[^/?#]+/?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'usti-events', 'Ústí nad Labem – kalendár akcií', 'usti_events', 'https://www.usti.cz/cz/volny-cas/kalendar-akci.html',
    'generic_cards_v4', 'CZ', 'Ústí nad Labem', 'Ústecký kraj', 30, true, 'cz-wave1', 50, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.usti\.cz/',
      'excludeUrlRegex', '/(?:kontakt|urad|mapa|kalendar-akci\.html$)',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'liberec-events', 'Liberec – kalendár akcií', 'liberec_events', 'https://www.visitliberec.eu/kalendar-akci/',
    'generic_cards_v4', 'CZ', 'Liberec', 'Liberecký kraj', 30, true, 'cz-wave1', 60, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://www\.visitliberec\.eu/',
      'excludeUrlRegex', '/(?:kontakt|o-nas|kalendar-akci/?$)',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
  ),
  (
    'plzen-events', 'Plzeň – kalendár akcií', 'plzen_events', 'https://akce.plzen.eu/',
    'generic_cards_v4', 'CZ', 'Plzeň', 'Plzeňský kraj', 30, true, 'cz-wave1', 70, false,
    jsonb_build_object(
      'allowedUrlRegex', '^https://akce\.plzen\.eu/',
      'excludeUrlRegex', '^https://akce\.plzen\.eu/?(?:\?[^#]*)?$',
      'minimumQuality', 72,
      'maximumFutureDays', 730,
      'defaultCurrency', 'CZK'
    )
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
  group_code = excluded.group_code,
  priority = excluded.priority,
  cron_enabled = excluded.cron_enabled,
  config = excluded.config,
  updated_at = now();

create or replace function public.catalog_list_source_pages_v2(
  p_codes text[] default null,
  p_group_code text default null,
  p_include_disabled boolean default false
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
  config jsonb,
  group_code text,
  priority integer,
  cron_enabled boolean
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
    sp.config,
    sp.group_code,
    sp.priority,
    sp.cron_enabled
  from private.source_pages sp
  where (p_include_disabled or sp.enabled = true)
    and (p_codes is null or sp.code = any(p_codes))
    and (p_group_code is null or sp.group_code = p_group_code)
  order by sp.priority, sp.code;
$$;

revoke all on function public.catalog_list_source_pages_v2(text[], text, boolean) from public;
grant execute on function public.catalog_list_source_pages_v2(text[], text, boolean) to service_role;

create or replace function public.catalog_record_source_run_v1(
  p_source_page_code text,
  p_action text,
  p_started_at timestamptz,
  p_duration_ms integer,
  p_success boolean,
  p_stats jsonb default '{}'::jsonb,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_source private.source_pages%rowtype;
  v_accepted integer := 0;
  v_new_failures integer;
  v_health text;
begin
  if p_action not in ('preview', 'sync') then
    raise exception 'Unsupported source run action: %', p_action;
  end if;

  select * into v_source
  from private.source_pages
  where code = p_source_page_code
  for update;

  if not found then
    raise exception 'Unknown source page: %', p_source_page_code;
  end if;

  begin
    v_accepted := greatest(0, coalesce((p_stats->>'accepted')::integer, 0));
  exception when others then
    v_accepted := 0;
  end;

  v_new_failures := case when p_success then 0 else v_source.consecutive_failures + 1 end;
  v_health := case
    when not v_source.enabled then 'disabled'
    when not p_success and v_new_failures >= 3 then 'failing'
    when not p_success then 'warning'
    when v_accepted > 0 then 'healthy'
    else 'warning'
  end;

  insert into private.source_sync_runs (
    source_page_id,
    action,
    started_at,
    finished_at,
    duration_ms,
    success,
    stats,
    error_message
  ) values (
    v_source.id,
    p_action,
    p_started_at,
    now(),
    greatest(0, p_duration_ms),
    p_success,
    coalesce(p_stats, '{}'::jsonb),
    nullif(p_error_message, '')
  );

  update private.source_pages
  set
    last_preview_at = case when p_action = 'preview' then now() else last_preview_at end,
    last_sync_at = case when p_action = 'sync' then now() else last_sync_at end,
    last_success_at = case when p_success then now() else last_success_at end,
    last_error_at = case when p_success then last_error_at else now() end,
    last_error_message = case when p_success then null else nullif(p_error_message, '') end,
    health_status = v_health,
    consecutive_failures = v_new_failures,
    last_duration_ms = greatest(0, p_duration_ms),
    last_result = coalesce(p_stats, '{}'::jsonb),
    updated_at = now()
  where id = v_source.id;

  return jsonb_build_object(
    'sourcePageCode', p_source_page_code,
    'healthStatus', v_health,
    'consecutiveFailures', v_new_failures
  );
end;
$$;

revoke all on function public.catalog_record_source_run_v1(text, text, timestamptz, integer, boolean, jsonb, text) from public;
grant execute on function public.catalog_record_source_run_v1(text, text, timestamptz, integer, boolean, jsonb, text) to service_role;

create or replace function public.catalog_source_health_report_v1()
returns table (
  source_page_code text,
  display_name text,
  group_code text,
  country_code text,
  default_region text,
  enabled boolean,
  cron_enabled boolean,
  health_status text,
  consecutive_failures integer,
  last_preview_at timestamptz,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error_message text,
  last_duration_ms integer,
  last_result jsonb
)
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select
    sp.code,
    sp.display_name,
    sp.group_code,
    sp.country_code,
    sp.default_region,
    sp.enabled,
    sp.cron_enabled,
    sp.health_status,
    sp.consecutive_failures,
    sp.last_preview_at,
    sp.last_sync_at,
    sp.last_success_at,
    sp.last_error_at,
    sp.last_error_message,
    sp.last_duration_ms,
    sp.last_result
  from private.source_pages sp
  order by sp.group_code, sp.priority, sp.code;
$$;

revoke all on function public.catalog_source_health_report_v1() from public;
grant execute on function public.catalog_source_health_report_v1() to service_role;

insert into private.schema_versions(version, description)
values (
  '2026-07-18-data-expansion-v1',
  'All 8 Slovak regions and Czech wave 1 source registry, V4 generic adapters, source health and batch reporting'
)
on conflict (version) do nothing;

commit;
