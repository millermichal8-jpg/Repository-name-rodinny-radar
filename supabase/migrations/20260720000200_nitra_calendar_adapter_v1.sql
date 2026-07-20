-- Rodinny radar - Nitra Calendar Adapter V1
-- Switches the Nitra source to the official NITRA.EU event calendar.
-- Cron remains disabled until local and online previews pass.

begin;

update private.source_pages
set
  display_name = 'Nitra - kalendar udalosti',
  list_url = 'https://www.nitra.eu/kalendar',
  adapter = 'generic_cards_v4',
  max_event_links = 50,
  cron_enabled = false,
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'allowedUrlRegex', '^https://www\.nitra\.eu/kalendar/[0-9]+/[^/?#]+/?$',
    'excludeUrlRegex', '/kalendar/(?:iCalFeed|archiv|[0-9]+)$',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR',
    'detailParser', 'nitra-calendar-card-v1'
  ),
  updated_at = now()
where code = 'nitra-city-events';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-20-nitra-calendar-adapter-v1',
  'Nitra source switched to official NITRA.EU calendar cards'
)
on conflict (version) do nothing;

commit;
