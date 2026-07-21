-- Rodinny radar - Tvrdosin mobile feed coordinates V1
-- Adds safe city-centre fallback coordinates only when a venue has no GPS.
-- Existing exact venue coordinates are never overwritten.

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
      when 'tvrdosin' then
        new.latitude := 49.333611;
        new.longitude := 19.555111;
      when 'liesek' then
        new.latitude := 49.361111;
        new.longitude := 19.675000;
      when 'zuberec' then
        new.latitude := 49.258611;
        new.longitude := 19.612778;
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

update public.venues
set
  latitude = case private.normalize_text(coalesce(city, ''))
    when 'tvrdosin' then 49.333611
    when 'liesek' then 49.361111
    when 'zuberec' then 49.258611
    else latitude
  end,
  longitude = case private.normalize_text(coalesce(city, ''))
    when 'tvrdosin' then 19.555111
    when 'liesek' then 19.675000
    when 'zuberec' then 19.612778
    else longitude
  end
where active = true
  and (latitude is null or longitude is null)
  and private.normalize_text(coalesce(city, '')) in (
    'tvrdosin',
    'liesek',
    'zuberec'
  );

insert into private.schema_versions(version, description)
values (
  '2026-07-21-tvrdosin-mobile-feed-coordinates-v1',
  'City-centre GPS fallback for Tvrdosin, Liesek and Zuberec event venues'
)
on conflict (version) do nothing;

commit;
