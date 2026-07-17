-- Rodinný radar — mobilný feed reálnych podujatí V1
-- Publikuje iba overené municipal podujatia a dopĺňa GPS pre prvé zdroje.

begin;

create or replace function private.apply_known_city_coordinates_v1()
returns trigger
language plpgsql
security invoker
set search_path = public, private, extensions
as $$
begin
  if new.latitude is null or new.longitude is null then
    case private.normalize_text(coalesce(new.city, ''))
      when 'bojnice' then
        new.latitude := 48.7797;
        new.longitude := 18.5776;
      when 'zvolen' then
        new.latitude := 48.5744;
        new.longitude := 19.1532;
      when 'banska stiavnica' then
        new.latitude := 48.4589;
        new.longitude := 18.8964;
      else
        null;
    end case;
  end if;

  return new;
end;
$$;

drop trigger if exists venues_00_known_city_coordinates_trigger
  on public.venues;
create trigger venues_00_known_city_coordinates_trigger
before insert or update of city, latitude, longitude
on public.venues
for each row execute function private.apply_known_city_coordinates_v1();

-- Doplní GPS aj už existujúcim miestam. Existujúci prepare_venue trigger
-- následne automaticky vytvorí PostGIS geography bod.
update public.venues
set
  latitude = case private.normalize_text(coalesce(city, ''))
    when 'bojnice' then 48.7797
    when 'zvolen' then 48.5744
    when 'banska stiavnica' then 48.4589
    else latitude
  end,
  longitude = case private.normalize_text(coalesce(city, ''))
    when 'bojnice' then 18.5776
    when 'zvolen' then 19.1532
    when 'banska stiavnica' then 18.8964
    else longitude
  end
where active = true
  and (latitude is null or longitude is null)
  and private.normalize_text(coalesce(city, '')) in (
    'bojnice',
    'zvolen',
    'banska stiavnica'
  );

create or replace function private.publish_verified_municipal_experience_v1(
  p_experience_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  update public.experiences e
  set
    publication_status = 'published',
    lifecycle_status = case
      when e.lifecycle_status in ('cancelled', 'postponed', 'closed')
        then e.lifecycle_status
      else 'scheduled'
    end,
    published_at = coalesce(e.published_at, now()),
    updated_at = now()
  where e.id = p_experience_id
    and e.kind = 'event'
    and e.active = true
    and e.quality_score >= 90
    and e.lifecycle_status not in ('cancelled', 'closed')
    and exists (
      select 1
      from public.experience_sources es
      join public.sources s on s.id = es.source_id
      where es.experience_id = e.id
        and s.code in (
          'bojnice_events',
          'zvolen_events',
          'banska_stiavnica_kultura'
        )
        and s.active = true
    )
    and exists (
      select 1
      from public.experience_occurrences o
      where o.experience_id = e.id
        and o.active = true
        and o.status in ('scheduled', 'rescheduled')
        and coalesce(o.ends_at, o.starts_at) >= now()
    );
end;
$$;

create or replace function private.publish_verified_municipal_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  perform private.publish_verified_municipal_experience_v1(new.experience_id);
  return new;
end;
$$;

drop trigger if exists occurrences_publish_verified_municipal_trigger
  on public.experience_occurrences;
create trigger occurrences_publish_verified_municipal_trigger
after insert or update of starts_at, ends_at, status, active
on public.experience_occurrences
for each row execute function private.publish_verified_municipal_occurrence_v1();

-- Publikuje už dnes zosynchronizované a otestované podujatia.
do $$
declare
  v_experience_id uuid;
begin
  for v_experience_id in
    select distinct e.id
    from public.experiences e
    join public.experience_sources es on es.experience_id = e.id
    join public.sources s on s.id = es.source_id
    where e.kind = 'event'
      and e.active = true
      and e.quality_score >= 90
      and s.code in (
        'bojnice_events',
        'zvolen_events',
        'banska_stiavnica_kultura'
      )
  loop
    perform private.publish_verified_municipal_experience_v1(v_experience_id);
  end loop;
end;
$$;

commit;
