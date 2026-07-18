begin;

create or replace function private.guard_single_primary_experience_source()
returns trigger
language plpgsql
set search_path = public, private
as $$
begin
  if new.is_primary and exists (
    select 1
    from public.experience_sources existing
    where existing.experience_id = new.experience_id
      and existing.is_primary = true
      and not (
        existing.experience_id = new.experience_id
        and existing.source_id = new.source_id
        and existing.external_id = new.external_id
      )
  ) then
    new.is_primary := false;
  end if;

  return new;
end;
$$;

drop trigger if exists experience_sources_primary_guard
  on public.experience_sources;

create trigger experience_sources_primary_guard
before insert or update of experience_id, source_id, external_id, is_primary
on public.experience_sources
for each row
execute function private.guard_single_primary_experience_source();

-- Odstráni iba chybné testovacie záznamy Praha 12 vytvorené z hlavičky webu.
-- Legitímne alebo už zlúčené podujatie s ďalším zdrojom zostane zachované.
delete from public.experiences experience
where experience.publication_status = 'review'
  and (
    private.normalize_text(experience.title) like '%odkaz na titulni stranku%'
    or private.normalize_text(experience.title) like '%oficialni web mestske casti%'
  )
  and exists (
    select 1
    from public.experience_sources source_link
    join public.sources source on source.id = source_link.source_id
    where source_link.experience_id = experience.id
      and source.code = 'praha12_events'
  )
  and not exists (
    select 1
    from public.experience_sources other_link
    join public.sources other_source on other_source.id = other_link.source_id
    where other_link.experience_id = experience.id
      and other_source.code <> 'praha12_events'
  );

commit;
