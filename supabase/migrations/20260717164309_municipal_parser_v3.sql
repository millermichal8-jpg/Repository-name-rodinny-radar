-- Rodinný radar — Municipal parser V3
-- Source-specific adapters. No generic heading/date parent crawler.

begin;

update private.source_pages
set
  adapter = 'citio_detail_v3',
  max_event_links = 24,
  config = jsonb_build_object(
    'allowedPathRegex', '^/podujatia/[^/]+/?$',
    'minimumQuality', 75,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'bb-events';

update private.source_pages
set
  adapter = 'webygroup_detail_v3',
  max_event_links = 30,
  config = jsonb_build_object(
    'allowedPathRegex', '^/akcia/[^/]+/mid/[0-9]+/[.]html$',
    'minimumQuality', 80,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code in ('bojnice-events', 'zvolen-events');

update private.source_pages
set
  adapter = 'ticketware_cards_v3',
  max_event_links = 30,
  config = jsonb_build_object(
    'allowedPathRegex', '^/event/[0-9]+/[^/?#]+/?$',
    'minimumQuality', 80,
    'maximumFutureDays', 730
  ),
  updated_at = now()
where code = 'bs-kultura';

insert into private.schema_versions(version, description)
values (
  '2026-07-17-municipal-parser-v3',
  'Deterministic CITIO, Webygroup and Ticketware adapters with structured dates and strict event URLs'
)
on conflict (version) do nothing;

commit;
