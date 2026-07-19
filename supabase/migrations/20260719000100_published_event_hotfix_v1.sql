-- Rodinný radar – Published Event Hotfix V1
-- Dočasne vracia štyri nesprávne Praha 12 záznamy do review.
-- Záznamy sa nemažú a po oprave parsera sa môžu znovu publikovať.

begin;

update public.experiences
set
  publication_status = 'review',
  updated_at = now()
where id in (
  '3cca6038-b630-4110-b113-749bdfed1439',
  'd5c4768d-e6ad-4fc1-8f91-cafd34f90f48',
  '582cb6a8-02c4-48f2-af8f-1f476bb56fef',
  'b0447558-5645-4593-a5f4-5575f68a8141'
)
and publication_status = 'published';

insert into private.schema_versions (
  version,
  description
)
values (
  '2026-07-19-published-event-hotfix-v1',
  'Demote four incorrect Praha 12 category or wrong-date records to review'
)
on conflict (version) do nothing;

commit;