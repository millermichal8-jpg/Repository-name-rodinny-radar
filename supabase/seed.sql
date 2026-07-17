-- Rodinný radar — referenčné seed dáta
-- Bez API kľúčov, používateľov a produkčných udalostí.

begin;

insert into public.sources (
  code, display_name, source_type, website_url, trust_level,
  is_official, attribution_required, default_cache_ttl_seconds, active
)
values
  ('google_places', 'Google Places', 'api', 'https://maps.google.com', 80, false, true, 604800, true),
  ('ticketmaster', 'Ticketmaster', 'api', 'https://www.ticketmaster.com', 95, true, true, 21600, true),
  ('ticketportal', 'Ticketportal', 'partner', 'https://www.ticketportal.sk', 95, true, true, 21600, true),
  ('predpredaj', 'Predpredaj.sk', 'partner', 'https://www.predpredaj.sk', 95, true, true, 21600, true),
  ('goout', 'GoOut', 'partner', 'https://goout.net', 90, true, true, 21600, true),
  ('ticketlive', 'TicketLIVE', 'partner', 'https://www.ticketlive.sk', 90, true, true, 21600, true),
  ('eventim', 'Eventim', 'partner', 'https://www.eventim.sk', 95, true, true, 21600, true),
  ('official_website', 'Oficiálny web organizátora', 'html', null, 100, true, false, 21600, true),
  ('municipal_calendar', 'Mestský alebo obecný kalendár', 'html', null, 90, true, false, 21600, true),
  ('schema_org', 'Schema.org Event / Offer', 'jsonld', 'https://schema.org', 85, false, false, 21600, true),
  ('tavily_search', 'Tavily Search', 'search', 'https://tavily.com', 55, false, false, 86400, true),
  ('firecrawl', 'Firecrawl', 'html', 'https://firecrawl.dev', 60, false, false, 86400, true),
  ('manual', 'Ručne overené', 'manual', null, 100, true, false, 0, true)
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

insert into public.categories (
  code, name_sk, name_cs, emoji, parent_code,
  family_relevance, sort_order, active
)
values
  ('animals', 'Zvieratá', 'Zvířata', '🦁', null, 95, 10, true),
  ('amusement', 'Zábava a atrakcie', 'Zábava a atrakce', '🎡', null, 95, 20, true),
  ('water', 'Vodné atrakcie', 'Vodní atrakce', '🌊', null, 90, 30, true),
  ('museum', 'Múzeá a poznanie', 'Muzea a poznání', '🏛️', null, 90, 40, true),
  ('history', 'Hrady, zámky a história', 'Hrady, zámky a historie', '🏰', null, 90, 50, true),
  ('nature', 'Príroda a turistika', 'Příroda a turistika', '🌳', null, 90, 60, true),
  ('theatre', 'Divadlo a predstavenia', 'Divadlo a představení', '🎭', null, 90, 70, true),
  ('music', 'Hudba a koncerty', 'Hudba a koncerty', '🎵', null, 75, 80, true),
  ('festival', 'Festivaly a slávnosti', 'Festivaly a slavnosti', '🎪', null, 95, 90, true),
  ('workshop', 'Tvorivé dielne', 'Tvořivé dílny', '🎨', null, 95, 100, true),
  ('science', 'Veda a technika', 'Věda a technika', '🔬', null, 90, 110, true),
  ('sport', 'Šport a pohyb', 'Sport a pohyb', '⚽', null, 90, 120, true),
  ('cinema', 'Kino', 'Kino', '🎬', null, 70, 130, true),
  ('fair', 'Jarmok a trhy', 'Jarmark a trhy', '🛍️', null, 80, 140, true),
  ('education', 'Vzdelávanie', 'Vzdělávání', '📚', null, 85, 150, true),
  ('community', 'Komunitné akcie', 'Komunitní akce', '👨‍👩‍👧‍👦', null, 85, 160, true),
  ('free_event', 'Akcie zdarma', 'Akce zdarma', '🆓', null, 100, 170, true),
  ('indoor', 'Program v interiéri', 'Program v interiéru', '☔', null, 90, 180, true),
  ('outdoor', 'Program vonku', 'Program venku', '☀️', null, 90, 190, true),
  ('other', 'Iné rodinné zážitky', 'Jiné rodinné zážitky', '🧭', null, 50, 999, true)
on conflict (code) do update
set
  name_sk = excluded.name_sk,
  name_cs = excluded.name_cs,
  emoji = excluded.emoji,
  parent_code = excluded.parent_code,
  family_relevance = excluded.family_relevance,
  sort_order = excluded.sort_order,
  active = excluded.active;

insert into private.source_connectors (
  source_id, connector_key, connector_mode, endpoint_base_url,
  enabled, schedule_cron, config, secret_names,
  rate_limit_per_minute, cache_ttl_seconds, retention_days
)
select
  s.id,
  c.connector_key,
  c.connector_mode,
  c.endpoint_base_url,
  c.enabled,
  c.schedule_cron,
  c.config,
  c.secret_names,
  c.rate_limit_per_minute,
  c.cache_ttl_seconds,
  c.retention_days
from public.sources s
join (
  values
    ('google_places','google_places','api','https://places.googleapis.com/v1',true,'0 3 * * 1','{}'::jsonb,array['GOOGLE_MAPS_API_KEY']::text[],60,604800,90),
    ('ticketmaster','ticketmaster_discovery','api','https://app.ticketmaster.com/discovery/v2',false,'0 */6 * * *','{"countryCodes":["SK","CZ"]}'::jsonb,array['TICKETMASTER_API_KEY']::text[],300,21600,90),
    ('ticketportal','ticketportal_partner','partner','https://www.ticketportal.sk',false,null,'{"requiresPartnerAgreement":true}'::jsonb,'{}'::text[],null,21600,30),
    ('predpredaj','predpredaj_partner','partner','https://www.predpredaj.sk',false,null,'{"requiresPartnerAgreement":true}'::jsonb,'{}'::text[],null,21600,30),
    ('goout','goout_partner','partner','https://goout.net',false,null,'{"requiresPartnerAgreement":true}'::jsonb,'{}'::text[],null,21600,30),
    ('ticketlive','ticketlive_partner','partner','https://www.ticketlive.sk',false,null,'{"requiresPartnerAgreement":true}'::jsonb,'{}'::text[],null,21600,30),
    ('eventim','eventim_partner','partner','https://www.eventim.sk',false,null,'{"requiresPartnerAgreement":true}'::jsonb,'{}'::text[],null,21600,30),
    ('tavily_search','tavily_event_discovery','search','https://api.tavily.com',false,'30 */6 * * *','{"searchDepth":"advanced"}'::jsonb,array['TAVILY_API_KEY']::text[],60,86400,30),
    ('firecrawl','firecrawl_extractor','html','https://api.firecrawl.dev',false,null,'{"formats":["json","markdown"]}'::jsonb,array['FIRECRAWL_API_KEY']::text[],30,86400,30)
) as c(
  source_code, connector_key, connector_mode, endpoint_base_url,
  enabled, schedule_cron, config, secret_names,
  rate_limit_per_minute, cache_ttl_seconds, retention_days
)
on s.code = c.source_code
on conflict (source_id) do update
set
  connector_key = excluded.connector_key,
  connector_mode = excluded.connector_mode,
  endpoint_base_url = excluded.endpoint_base_url,
  enabled = excluded.enabled,
  schedule_cron = excluded.schedule_cron,
  config = excluded.config,
  secret_names = excluded.secret_names,
  rate_limit_per_minute = excluded.rate_limit_per_minute,
  cache_ttl_seconds = excluded.cache_ttl_seconds,
  retention_days = excluded.retention_days,
  updated_at = now();

insert into private.schema_versions (version, description)
values (
  '2026-07-15-catalog-v2',
  'Jednotný katalóg atrakcií, akcií, termínov, cien a zdrojov'
)
on conflict (version) do nothing;

commit;
