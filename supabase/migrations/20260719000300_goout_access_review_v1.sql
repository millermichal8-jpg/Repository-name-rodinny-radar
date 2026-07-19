-- Rodinny radar – GoOut Access Review V1
-- GoOut connector remains disabled until written permission
-- and an approved API or feed are available.

begin;

update private.partner_access_requests par
set
  status = 'not_requested',
  requested_at = null,
  responded_at = null,
  terms_url = 'https://goout.net/sk/podmienky-pre-partnerov/',
  notes = 'Verejna API dokumentacia nebola potvrdena. Ziadost o pristup zatial nebola odoslana. Automaticke ziskavanie dat ostava vypnute do pisomneho suhlasu a schvaleneho API alebo feedu.',
  updated_at = now()
from public.sources s
where par.source_id = s.id
  and s.code = 'goout'
  and par.status not in ('approved', 'rejected', 'paused');

update private.source_connectors
set
  enabled = false,
  schedule_cron = null,
  connector_mode = 'partner',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'requiresPartnerAgreement', true,
    'requiresWrittenPermission', true,
    'scrapingAllowed', false,
    'accessStatus', 'not_requested',
    'ingestionFunction', 'partner-ticket-sync',
    'feedSchemaVersion', 1,
    'safeMode', true
  ),
  updated_at = now()
where connector_key = 'goout_partner';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-19-goout-access-review-v1',
  'GoOut connector kept disabled pending written permission and approved API or feed access'
)
on conflict (version) do nothing;

commit;