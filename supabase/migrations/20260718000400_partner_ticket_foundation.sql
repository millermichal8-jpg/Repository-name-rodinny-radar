-- Rodinný radar – Data Expansion V2 foundation
-- Partner ticket sources remain disabled until written permission and an approved feed/API are available.

begin;

create table if not exists private.partner_access_requests (
  source_id uuid primary key references public.sources(id) on delete cascade,
  status text not null default 'not_requested'
    check (status in ('not_requested', 'requested', 'approved', 'rejected', 'paused')),
  contact_email text,
  requested_at timestamptz,
  responded_at timestamptz,
  terms_url text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into private.partner_access_requests (
  source_id,
  status,
  contact_email,
  requested_at,
  notes
)
select
  s.id,
  case when s.code = 'goout' then 'requested' else 'not_requested' end,
  case
    when s.code = 'goout' then 'info@goout.sk'
    when s.code = 'predpredaj' then 'obchod@predpredaj.sk'
    else null
  end,
  case when s.code = 'goout' then now() else null end,
  case
    when s.code = 'goout' then 'Žiadosť o partnerský API/feed prístup odoslaná.'
    else 'Konektor pripravený iba technicky; automatické získavanie dát je vypnuté.'
  end
from public.sources s
where s.code in ('goout', 'predpredaj', 'ticketportal', 'ticketlive', 'eventim')
on conflict (source_id) do update
set
  contact_email = excluded.contact_email,
  status = case
    when private.partner_access_requests.status in ('approved', 'rejected', 'paused')
      then private.partner_access_requests.status
    else excluded.status
  end,
  requested_at = coalesce(private.partner_access_requests.requested_at, excluded.requested_at),
  notes = excluded.notes,
  updated_at = now();

update private.source_connectors c
set
  connector_mode = 'partner',
  enabled = false,
  schedule_cron = null,
  config = coalesce(c.config, '{}'::jsonb) || jsonb_build_object(
    'requiresPartnerAgreement', true,
    'ingestionFunction', 'partner-ticket-sync',
    'feedSchemaVersion', 1,
    'safeMode', true
  ),
  secret_names = case c.connector_key
    when 'goout_partner' then array['GOOUT_PARTNER_FEED_URL', 'GOOUT_PARTNER_FEED_TOKEN']::text[]
    when 'predpredaj_partner' then array['PREDPREDAJ_PARTNER_FEED_URL', 'PREDPREDAJ_PARTNER_FEED_TOKEN']::text[]
    when 'ticketportal_partner' then array['TICKETPORTAL_PARTNER_FEED_URL', 'TICKETPORTAL_PARTNER_FEED_TOKEN']::text[]
    when 'ticketlive_partner' then array['TICKETLIVE_PARTNER_FEED_URL', 'TICKETLIVE_PARTNER_FEED_TOKEN']::text[]
    when 'eventim_partner' then array['EVENTIM_PARTNER_FEED_URL', 'EVENTIM_PARTNER_FEED_TOKEN']::text[]
    else c.secret_names
  end,
  updated_at = now()
where c.connector_key in (
  'goout_partner',
  'predpredaj_partner',
  'ticketportal_partner',
  'ticketlive_partner',
  'eventim_partner'
);

insert into private.schema_versions(version, description)
values (
  '2026-07-18-partner-ticket-foundation',
  'Permission-gated partner ticket feed foundation for GoOut, Predpredaj, Ticketportal, TicketLIVE and Eventim'
)
on conflict (version) do nothing;

commit;
