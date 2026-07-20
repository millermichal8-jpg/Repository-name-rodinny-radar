-- Rodinny radar - Zilina WordPress API Adapter V1
-- Uses the official public event endpoint used by zilina.sk.
-- Cron remains disabled until local and online previews pass.

begin;

update private.source_pages
set
  display_name = 'Zilina - mestske podujatia API',
  list_url = 'https://zilina.sk/wp-json/iq/v1/event/list',
  adapter = 'zilina_wordpress_api_v1',
  max_event_links = 100,
  cron_enabled = false,
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'allowedUrlRegex', '^https://zilina\.sk/podujatie/[^/?#]+/?$',
    'minimumQuality', 78,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR',
    'adminCategories', jsonb_build_array('100', '102', '101', '99', '103'),
    'apiLimit', 100,
    'detailParser', 'zilina-wordpress-api-v1'
  ),
  updated_at = now()
where code = 'zilina-events';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-20-zilina-wordpress-api-adapter-v1',
  'Zilina source switched to official WordPress event API'
)
on conflict (version) do nothing;

commit;
