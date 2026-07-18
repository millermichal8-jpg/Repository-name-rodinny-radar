-- Rodinný radar — Source Recovery V1
-- Recover event data from five sources that exposed links but no parsed candidates.

begin;

update private.source_pages
set
  adapter = 'generic_cards_v4',
  max_event_links = 35,
  config = jsonb_build_object(
    'allowedUrlRegex', '^https://www\.ostravainfo\.cz/cz/akce/[^?#]+/[0-9]+-[^/?#]+\.html$',
    'linkSelector', 'a[href*="/cz/akce/"]',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'CZK'
  ),
  updated_at = now()
where code = 'ostrava-events';

update private.source_pages
set
  adapter = 'generic_cards_v4',
  max_event_links = 30,
  config = jsonb_build_object(
    'allowedUrlRegex', '^https://www\.olkraj\.cz/kalendar/[^/?#]+/?$',
    'linkSelector', 'a[href*="/kalendar/"]',
    'excludeUrlRegex', '/kalendar/?(?:\?|$)',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'CZK'
  ),
  updated_at = now()
where code = 'olomouc-region-events';

update private.source_pages
set
  adapter = 'generic_cards_v4',
  max_event_links = 35,
  config = jsonb_build_object(
    'allowedUrlRegex', '^https://www\.bkis\.sk/udalost/[^/?#]+/[A-Za-z0-9]+/[0-9]+/?$',
    'linkSelector', 'a[href*="/udalost/"]',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR'
  ),
  updated_at = now()
where code = 'bkis-events';

update private.source_pages
set
  adapter = 'generic_cards_v4',
  max_event_links = 35,
  config = jsonb_build_object(
    'allowedUrlRegex', '^https://www\.senec\.sk/podujatia/[^/?#]+/?$',
    'linkSelector', 'a[href*="/podujatia/"]',
    'excludeUrlRegex', '/(?:kategoria|tag|page)/|/podujatia/?$',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR'
  ),
  updated_at = now()
where code = 'senec-events';

update private.source_pages
set
  adapter = 'generic_cards_v4',
  max_event_links = 36,
  config = jsonb_build_object(
    'allowedUrlRegex', '^https://www\.banskabystrica\.sk/podujatia/[^/?#]+/?$',
    'linkSelector', 'a[href*="/podujatia/"]',
    'excludeUrlRegex', '/(?:kategorie-podujati|rocny-prehlad|page)/|/podujatia/?$',
    'minimumQuality', 72,
    'maximumFutureDays', 730,
    'defaultCurrency', 'EUR'
  ),
  updated_at = now()
where code = 'bb-events';

insert into private.schema_versions(version, description)
values (
  '2026-07-18-source-recovery-v1',
  'Card-seeded event recovery for Ostrava, Olomouc region, BKIS, Senec and Banska Bystrica'
)
on conflict (version) do nothing;

commit;
