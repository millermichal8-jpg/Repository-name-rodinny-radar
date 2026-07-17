# Rodinný radar – stav projektu

**Posledná overená aktualizácia:** 18. 7. 2026  
**Hlavná vetva:** `main`  
**GitHub:** súkromný repozitár, lokálna vetva sleduje `origin/main`

## Cieľ

Mobilná aplikácia pre rodičov, ktorá nájde trvalé výlety aj aktuálne podujatia
podľa mesta, vzdialenosti, dátumu, počtu ľudí a veku detí.

---

## Technológie

- React Native
- Expo SDK 54
- Expo Go
- TypeScript
- Supabase
- Supabase Edge Functions
- PostgreSQL + PostGIS
- Docker Desktop + lokálny Supabase
- Google Places API
- Ticketmaster Discovery API
- Git + GitHub

---

## Čo funguje

### Mobilná aplikácia

- aplikácia sa spúšťa v Expo Go
- letný vizuálny štýl
- zadanie mesta s našepkávaním miest a obcí SK/CZ
- počet dospelých
- počet detí
- samostatný vek každého dieťaťa
- výber maximálnej vzdialenosti
- trvalé výlety z Google Places
- rozkliknuteľný detail výletu
- adresa, hodnotenie, web, telefón a otváracie hodiny pri výlete
- sekcia **Aktuálne podujatia**
- reálne podujatia načítané z online katalógu
- rozkliknuteľný detail podujatia
- filtre:
  - Všetky
  - Dnes
  - Tento víkend
  - Zadarmo
- radenie podľa termínu alebo vzdialenosti
- otvorenie oficiálnej stránky alebo odkazu na lístky

### Databáza a katalóg V2

- univerzálny katalóg pre atrakcie aj podujatia
- miesta a areály
- organizátori
- zážitky
- konkrétne termíny
- vstupenky a ceny
- médiá
- viac zdrojov jednej akcie
- raw zdrojové záznamy
- história synchronizácií
- kandidáti na duplicity
- história cien
- kontrola kvality
- jednotný `experience_feed`
- geografické vyhľadávanie cez PostGIS

### Ticketmaster

- Ticketmaster Discovery API je pripojené
- preview režim bez zápisu funguje
- ostrý sync do katalógu funguje
- české podujatia sa úspešne zapisujú
- Slovensko momentálne cez Ticketmaster vracia 0 udalostí
- Ticketmaster ostáva doplnkový zdroj, nie hlavný slovenský zdroj

### Slovenské mestské a kultúrne zdroje

Municipal parser V3 je nasadený online a funguje pre:

- Bojnice
- Zvolen
- Kultúrne centrum Banská Štiavnica

Parser:

- vyhľadáva detailné stránky podujatí
- číta Schema.org Event/Offer, keď sú dostupné
- používa HTML fallback
- získava názov, termín, mesto, obrázok a cenu alebo vstup zdarma
- filtruje staré a neplatné položky
- prideľuje skóre kvality
- robí základnú deduplikáciu
- zapisuje udalosti do katalógu V2
- overené udalosti sú publikované online
- mobilný `experience-feed` ich vracia aplikácii

### Vývojové prostredie a automatizácia

- Git repozitár je inicializovaný
- projekt je pushnutý na súkromný GitHub
- existuje bezpečný návratový baseline commit
- Supabase CLI je nainštalované lokálne
- všetky Edge Functions sú v `supabase/functions`
- databázové migrácie sú v `supabase/migrations`
- referenčné dáta sú v `supabase/seed.sql`
- lokálny Supabase beží cez Docker
- databáza sa dá vytvoriť od nuly cez migrácie a seed
- `db reset` bol úspešne overený
- lokálne testovacie výstupy a secrets sú ignorované v Gite
- produkčné migrácie aj Edge Functions sa dajú nasadzovať cez CLI

---

## Čo zatiaľ nefunguje alebo nie je dokončené

### Pokrytie dát

- databáza podujatí je stále malá
- Banská Bystrica zatiaľ našla odkazy, ale neprijala použiteľné udalosti
- chýba vlastný adaptér pre Banskú Bystricu
- chýba väčšina slovenských miest, regiónov a kultúrnych centier
- chýba systematické pokrytie všetkých 8 slovenských krajov
- české mestské a regionálne zdroje ešte nie sú pripojené
- Ticketportal ešte nie je pripojený
- Predpredaj.sk ešte nie je pripojený
- GoOut ešte nie je pripojený
- TicketLIVE ešte nie je pripojený
- Eventim ešte nie je pripojený
- Tavily ešte nie je pripojené
- Firecrawl ešte nie je pripojený
- PDF programy sa ešte univerzálne nespracúvajú
- JavaScriptové kalendáre ešte nemajú univerzálny fallback
- akcie zo sociálnych sietí a neverejných zdrojov nie sú pokryté

### Deduplikácia a kvalita

- deduplikácia je zatiaľ základná
- rovnaká akcia z mesta, organizátora a ticketového portálu sa ešte nemusí vždy spojiť
- chýba automatický review panel
- chýba správa chýb a ručné schvaľovanie podozrivých položiek
- chýba monitoring nefunkčných zdrojov
- chýba automatické vyradenie dlhodobo nefunkčných zdrojov
- chýba automatická kontrola zrušených a presunutých podujatí
- história cien je pripravená, ale ešte sa pravidelne neplní

### Mobilná aplikácia

- fotografie podujatí a výletov nie sú vyriešené jednotne
- karty ešte nie sú finálne dizajnovo doladené
- obľúbené položky sa neukladajú trvalo do účtu
- používateľské účty a prihlásenie nie sú hotové
- synchronizácia medzi zariadeniami nie je hotová
- vzdialenosť je pri časti obsahu stále iba približná
- reálna cesta autom nie je dokončená pre všetok obsah
- vlak, autobus, prestupy a čas chôdze nie sú dokončené
- chýba finálna kategorizácia podľa veku detí
- chýba komplexné filtrovanie podľa kategórie, ceny a dostupnosti
- chýba mapa výsledkov
- chýba finálne prázdne/loading/error UI
- chýba produkčný onboarding

### Produkcia a automatické behy

- Cron synchronizácie ešte nie sú finálne nastavené pre všetky zdroje
- chýba centrálny orchestrátor dávok
- chýba automatický retry pri dočasnom výpadku webu
- chýba upozornenie pri chybe konektora
- chýba dashboard spotreby API a kvót
- chýba oddelené staging prostredie
- chýba CI/CD kontrola pri každom commite
- chýbajú automatické integračné testy pre všetky konektory

### Právne a obchodné veci

- chýbajú pravidlá atribúcie zdrojov
- chýbajú partnerské dohody s ticketovými portálmi
- chýbajú podmienky používania
- chýba ochrana osobných údajov a zásady súkromia
- monetizácia a predplatné nie sú implementované

---

## Aktuálny hlavný cieľ

Najprv výrazne zväčšiť databázu podujatí.

Poradie:

1. pridať zdroje pre všetkých 8 slovenských krajov
2. pridať prvú vlnu českých miest a regiónov
3. vytvoriť dávkový orchestrátor
4. vytvoriť report fungujúcich a nefunkčných zdrojov
5. rozšíriť deduplikáciu
6. nastaviť automatické pravidelné synchronizácie
7. až potom jednotne riešiť:
   - fotografie
   - krajšie karty
   - trvalé obľúbené položky

---

## Najbližší pracovný balík

**Data Expansion V1**

- register ďalších slovenských a českých zdrojov
- dávkové preview
- dávkový ostrý sync
- kontrola kvality
- report zdrojov
- základný orchestrátor
- príprava na Cron
- aktualizácia tohto PROJECT_STATUS.md po úspešnom nasadení

---

## Pravidlá práce

- produkciu meniť iba cez overenú migráciu alebo nasadzovací skript
- pred veľkou zmenou vytvoriť zálohu
- najprv preview alebo lokálny test
- potom malý online sync
- až potom väčšia dávka
- po dokončenom balíku:
  - TypeScript kontrola
  - Git commit
  - Git push
  - aktualizácia `PROJECT_STATUS.md`