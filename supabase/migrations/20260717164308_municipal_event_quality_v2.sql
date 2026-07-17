-- Rodinný radar — Municipal event quality V2
-- Stricter source adapters and quality filters for official SK calendars.

begin;

update private.source_pages
set
  adapter = 'citio_detail',
  max_event_links = 24,
  config = jsonb_build_object(
    'allowedPathRegex', '^/podujatia/[^/]+/?$',
    'excludePathHints', jsonb_build_array(
      '/kategorie-podujati/',
      '/rocny-prehlad/',
      '/page/'
    ),
    'minimumQuality', 65,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'bb-events';

update private.source_pages
set
  adapter = 'webygroup_listing',
  max_event_links = 30,
  config = jsonb_build_object(
    'detailPathRegex', '^/kalendar-podujati/',
    'minimumQuality', 65,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'bojnice-events';

update private.source_pages
set
  adapter = 'webygroup_listing',
  max_event_links = 30,
  config = jsonb_build_object(
    'detailPathRegex', '^/akcia/',
    'minimumQuality', 65,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'zvolen-events';

update private.source_pages
set
  adapter = 'ticketware_detail',
  max_event_links = 28,
  config = jsonb_build_object(
    'allowedPathRegex', '^/event/[0-9]+/[^/]+/?$',
    'excludePathHints', jsonb_build_array(
      '/page/',
      '/registracia',
      '/kontakty',
      '/obchodne-podmienky',
      '/klient-',
      '/kino-',
      '/film-'
    ),
    'minimumQuality', 65,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'bs-kultura';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-17-municipal-quality-v2',
  'Strict event link adapters, future-date filtering, navigation rejection and quality gates'
)
on conflict (version) do nothing;

commit;
