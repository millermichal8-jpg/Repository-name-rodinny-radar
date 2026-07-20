-- Rodinny radar - Trnava + Visit Trencin Adapter V1
-- Switches the three audited municipal sources from listing-card parsing
-- to exact detail-page parsing. Cron remains disabled.

begin;

update private.source_pages
set
  adapter = 'generic_detail_v4',
  max_event_links = 60,
  cron_enabled = false,
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'allowedUrlRegex', '^https://www\.trnava\.sk/podujatia/[0-9]+/[^/?#]+/?$',
    'excludeUrlRegex', '/(?:stranka|tagy|aktuality|uradna-tabula)/',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR',
    'detailParser', 'trnava-city-detail-v1'
  ),
  updated_at = now()
where code = 'trnava-city-events';

update private.source_pages
set
  adapter = 'generic_detail_v4',
  max_event_links = 40,
  cron_enabled = false,
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'allowedUrlRegex', '^https://kultura\.trnava\.sk/podujatie/[^/?#]+/?$',
    'excludeUrlRegex', '/(?:kontakt|o-nas|organizacie|kalendar/?$)/',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR',
    'detailParser', 'trnava-kultura-detail-v1'
  ),
  updated_at = now()
where code = 'trnava-kultura-events';

update private.source_pages
set
  adapter = 'generic_detail_v4',
  max_event_links = 50,
  cron_enabled = false,
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'allowedUrlRegex', '^https://visit\.trencin\.sk/podujatia/\?id=[0-9]+$',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR',
    'detailParser', 'visit-trencin-query-detail-v1'
  ),
  updated_at = now()
where code = 'visit-trencin-events';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-20-trnava-trencin-adapter-v1',
  'Exact detail adapters for Trnava city, Kultura Trnava and Visit Trencin query-ID events'
)
on conflict (version) do nothing;

commit;
