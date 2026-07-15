# Rodinný radar – stav projektu

## Cieľ
Mobilná aplikácia pre rodičov, ktorá automaticky nájde výlety a podujatia
podľa mesta, počtu ľudí, veku detí a vzdialenosti.

## Technológie
- React Native
- Expo SDK 54
- Expo Go
- TypeScript
- Supabase
- Google Places API
- Google Routes API

## Čo funguje
- aplikácia sa spúšťa v Expo Go
- letný dizajn
- zadanie mesta
- počet dospelých
- počet detí
- samostatný vek každého dieťaťa
- výber maximálnej vzdialenosti
- ukážkové výsledky výletov
- ukladanie výletov počas otvorenej aplikácie
- mobilná aplikácia je napojená na Supabase funkciu city-search
- ručný zoznam miest bol odstránený
- živé našepkávanie miest a obcí SK/CZ funguje priamo v mobile
- úspešne otestované vyhľadávanie Šiah

## Supabase
Vytvorené tabuľky:
- public.places
- public.events
- public.route_cache
- private.place_candidates
- private.sync_runs

## Google Cloud
- projekt RodinnyRadar vytvorený
- billing účet pripojený vo Free Trial
- pôvodný API kľúč bol vymazaný, pretože bol viditeľný na screenshote
- nový bezpečný API kľúč ešte nebol vytvorený
- vytvorený nový API kľúč obmedzený iba na Places API (New)
- API kľúč nie je uložený v mobilnej aplikácii
- API kľúč je uložený ako GOOGLE_MAPS_API_KEY v Supabase Secrets

## Čo zatiaľ nefunguje
- automatické vyhľadávanie výletov
- načítanie výletov zo Supabase
- detail výletu
- cesta autom
- vlak a autobus
- prestupy a čas chôdze
- trvalé ukladanie obľúbených výletov
- prihlasovanie používateľov
- predplatné
- Supabase Edge Function city-search je nasadená a funguje
- Google Places API kľúč je bezpečne uložený v Supabase Secrets
- živé vyhľadávanie miest a obcí pre Slovensko a Česko funguje
- úspešne otestované mesto Šahy
- city-search vracia názov mesta, krajinu, Google placeId a typ lokality
- funkcia na získanie detailu mesta a GPS súradníc funguje
- úspešne otestované mesto Šahy
- získavame placeId, presnú adresu, GPS, krajinu a región

## Ďalší krok
11. Upratať funkciu pod názvom city-details.
2. Napojiť mobilnú aplikáciu na city-details.
3. Po výbere mesta uložiť GPS súradnice.
4. Automaticky vyhľadať reálne výlety vo vybranom okruhu.
5. Zobraziť reálne výlety namiesto ukážkových.
6. Pridať dopravu autom a verejnou dopravou.