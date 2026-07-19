# Rodinný radar – stav projektu

**Posledná overená aktualizácia:** 19. 7. 2026
**Stabilná vetva:** `main`
**Aktuálny pracovný balík:** Slovakia Source Wave V1
**GitHub:** súkromný repozitár, lokálne vetvy sledujú `origin`

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
- počet dospelých a detí
- samostatný vek každého dieťaťa
- výber maximálnej vzdialenosti
- trvalé výlety z Google Places
- rozkliknuteľný detail výletu
- adresa, hodnotenie, web, telefón a otváracie hodiny
- sekcia **Aktuálne podujatia**
- reálne podujatia z online katalógu
- rozkliknuteľný detail podujatia
- filtre Všetky, Dnes, Tento víkend a Zadarmo
- radenie podľa termínu alebo vzdialenosti
- otvorenie oficiálnej stránky alebo odkazu na lístky

### Databáza a katalóg V2

- univerzálny katalóg pre atrakcie aj podujatia
- miesta, organizátori, zážitky a konkrétne termíny
- vstupenky, ceny, médiá a viac zdrojov jednej akcie
- raw zdrojové záznamy a história synchronizácií
- história cien a kontrola kvality
- jednotný `experience_feed`
- geografické vyhľadávanie cez PostGIS

### Mestské a regionálne zdroje

- základné pokrytie všetkých 8 slovenských krajov
- prvá vlna českých miest a regiónov
- denný Cron pre 22 zdrojov
- dávkový orchestrátor s retry
- Municipal parser V5 s detailnými adaptérmi a fallbackmi
- fungujú Bojnice, Zvolen, Kultúrne centrum Banská Štiavnica
- obnovené zdroje Ostrava, BKIS Bratislava, Senec a Banská Bystrica
- posledný kontrolovaný sync zapísal alebo aktualizoval 31 podujatí
- 0 chýb zápisu
- Olomoucký kraj je technicky zdravý, ale posledný preview bol prázdny

### Ticketmaster a partneri

- Ticketmaster Discovery API je pripojené
- preview aj ostrý sync fungujú
- české podujatia sa zapisujú
- Slovensko momentálne cez Ticketmaster vracia 0 udalostí
- pripravený partner feed základ pre GoOut, Predpredaj, Ticketportal, TicketLIVE a Eventim
- syntetický preview všetkých 5 partnerov funguje
- reálne feedy čakajú na súhlasy alebo partnerské prístupy

### Kvalita a monitoring

- Data Quality V1 – kandidáti na duplicity a bezpečný manuálny merge
- Source Reliability V1 – rozlíšenie reálnej chyby, prázdneho zdroja a zdroja iba s odkazmi
- Source Recovery V1 – obnovené detailné parsovanie problematických zdrojov
- Monitoring V1 – zdroje, Cron, opakované zlyhania a incidenty
- automatické uzatvorenie incidentu po oprave
- denný monitoring Cron je aktívny
- posledná kontrola: 0 kritických chýb, 0 varovaní, 1 informačný incident

### Vývojové prostredie a automatizácia

- Git repozitár a súkromný GitHub
- bezpečné pracovné vetvy a merge do `main`
- Supabase CLI lokálne
- Edge Functions v `supabase/functions`
- migrácie v `supabase/migrations`
- referenčné dáta v `supabase/seed.sql`
- lokálny Supabase cez Docker
- úspešne overený `db reset`
- lokálne testy s transakciou a `ROLLBACK`
- produkčné migrácie aj funkcie sa nasadzujú cez CLI
- secrets a testovacie výstupy sú ignorované v Gite

---

## Čo zatiaľ nie je dokončené

### Pokrytie dát

- databáza podujatí sa musí ďalej rozširovať
- Olomoucký kraj treba preveriť pri ďalšom behu
- chýba väčšina menších miest, regiónov a kultúrnych centier
- Ticketportal, Predpredaj, GoOut, TicketLIVE a Eventim ešte nemajú reálne partnerské feedy
- Tavily a Firecrawl nie sú pripojené
- PDF programy nemajú univerzálny parser
- JavaScriptové kalendáre nemajú univerzálny fallback
- sociálne siete a neverejné zdroje nie sú pokryté

### Review, deduplikácia a kvalita

- Event Review V1 sa práve implementuje
- zatiaľ nie je hotový grafický administrátorský panel
- rozšírená deduplikácia medzi mestskými a ticketovými zdrojmi pokračuje
- chýba automatická kontrola zrušených a presunutých podujatí
- história cien sa ešte neplní pravidelne
- chýba automatické vyradenie dlhodobo nefunkčných zdrojov

### Mobilná aplikácia

- fotografie nie sú vyriešené jednotne
- karty nie sú finálne dizajnovo doladené
- obľúbené položky sa neukladajú trvalo
- používateľské účty a prihlásenie nie sú hotové
- synchronizácia medzi zariadeniami nie je hotová
- vzdialenosť je pri časti obsahu približná
- reálna cesta autom nie je dokončená pre všetok obsah
- vlak, autobus, prestupy a čas chôdze nie sú dokončené
- chýba finálna kategorizácia podľa veku detí
- chýba komplexné filtrovanie, mapa a produkčný onboarding

### Produkcia

- chýba externé upozornenie e-mailom pri kritickom incidente
- chýba dashboard spotreby API a kvót
- chýba samostatné staging prostredie
- chýba CI/CD kontrola pri každom commite
- chýbajú integračné testy pre všetky konektory

### Právne a obchodné veci

- chýbajú pravidlá atribúcie zdrojov
- chýbajú partnerské dohody s ticketovými portálmi
- chýbajú podmienky používania
- chýbajú zásady ochrany osobných údajov a súkromia
- monetizácia a predplatné nie sú implementované

---

## Aktuálny hlavný cieľ

**Bezpečne dostať nové podujatia zo stavu `review` do mobilného `experience_feed`.**

Dokončené pred Event Review V1:

1. Data Expansion V1
2. automatický Cron a orchestrátor
3. Data Quality V1
4. Monitoring V1
5. Source Reliability V1
6. Source Recovery V1
7. kontrolovaný sync 31 podujatí bez chyby zápisu

Aktuálne poradie:

1. Event Review V1 – fronta, kontrola pripravenosti, schválenie, publikovanie, zamietnutie a audit
2. overenie publikovaných podujatí v mobilnej aplikácii
3. oprava alebo nové preverenie Olomouckého kraja
4. Data Expansion V2 – reálne partner feedy po súhlase partnerov
5. rozšírená deduplikácia medzi mestskými a ticketovými zdrojmi
6. fotografie
7. krajšie karty
8. trvalé obľúbené položky

---

## Najbližší pracovný balík

**Event Review V1**

Bezpečnostné pravidlá:

- review nástroje nesmú byť vo verejnej mobilnej aplikácii bez účtov a rolí
- prístup iba cez chránenú Edge Function a synchronizačný token
- preview bez zápisu ako prvý krok
- publikovať iba položky s budúcim termínom, mestom, oficiálnym odkazom a požadovanou kvalitou
- blokovať nevyriešené pravdepodobné duplicity
- každú zmenu auditovať
- hromadný zápis iba s `confirmWrite: true`

---

## Pravidlá práce

- produkciu meniť iba cez overenú migráciu alebo nasadzovací skript
- pred veľkou zmenou vytvoriť zálohu
- najprv preview alebo lokálny test
- potom malý online sync alebo kontrolované publikovanie
- až potom väčšia dávka
- po dokončenom balíku:
  - TypeScript kontrola
  - Git commit
  - Git push
  - aktualizácia `PROJECT_STATUS.md`

---

## Stav k 19. 7. 2026 – Event Review V1

- Event Review V1 je nasadený online
- funguje fronta review, schválenie, publikovanie, zamietnutie a audit
- publikovaných podujatí spolu: 37
- vo fronte review: 124
- pripravených na publikovanie: 101
- blokovaných kontrolou kvality alebo duplicít: 23
- prvá kontrolovaná produkčná dávka prešla bez chyby
---

## Event Date Display V1 – dokončené

- prebiehajúce viacdňové podujatia zobrazujú text Prebieha do
- budúce viacdňové podujatia zobrazujú celý rozsah dátumov
- skončené podujatia sa v aplikácii nezobrazujú
- filtre Dnes a Tento víkend pracujú s celým intervalom podujatia
- prebiehajúce podujatia sa pri radení podľa dátumu zobrazujú medzi prvými
- oprava bola overená na podujatí MOHÁČ 500 SK
---

## Published Event Hotfix V1 – dokončené

- audit publikovaných podujatí bol vykonaný
- štyri nesprávne položky Praha 12 boli vrátené do review
- generické kategórie už nie sú publikované
- dve položky letného kina so zlým termínom už nie sú publikované
- počet publikovaných podujatí po hotfixe: 33
- lokálny databázový reset prešiel
- online migrácia bola úspešne nasadená
- ďalší krok: trvalá ochrana parsera a publikovania
---

## Published Event Guard V1 – rozpracované

- parser Praha 12 prijíma iba skutočné detailné URL `/nazov/a-12345`
- generické kategórie sa blokujú v parseri aj vo fronte Event Review
- detailný dátum uprednostňuje pole Kdy/Termín pred dátumami v opise
- štyri historické chybné položky sa natrvalo archivujú
- ďalší krok: lokálny test, online preview bez zápisu a kontrolovaný sync Praha 12

---

## Praha 12 Date Fix V1 – dokončené

- detailné URL Praha 12 sú filtrované
- generické kategórie sa neprijímajú
- Křtiny majú správny termín 23. 7. 2026 o 21:30
- Šviháci majú správny termín 30. 7. 2026 o 21:15
- výstava Eva Vokatá má rozsah 1. 8. – 31. 8. 2026
- lokálny aj online preview prešli bez zápisu
- opravený municipal parser je nasadený online
---

## GoOut Access Review V1

- verejný API alebo feed prístup zatiaľ nebol potvrdený
- žiadosť o prístup ešte nebola odoslaná
- GoOut konektor zostáva bezpečne vypnutý
- scraping obsahu GoOut nebude použitý
- technická partner-feed vrstva je pripravená na autorizovaný prístup
- ďalší dátový zdroj na preverenie: Predpredaj.sk
---

## Predpredaj.sk Access Review V1

- oficiálny kontakt pre spoluprácu bol nájdený
- verejné API alebo dátový feed zatiaľ nebol potvrdený
- žiadosť o dátový prístup ešte nebola odoslaná
- pripravený je návrh partnerskej žiadosti
- konektor zostáva vypnutý
- pred databázovou migráciou sa overujú presné existujúce identifikátory projektu
---

## Banská Bystrica Detail Adapter V1 – dokončené

- zdroj: oficiálny mestský kalendár Banskej Bystrice
- parser otvára zoznam aj jednotlivé detailné stránky
- lokálny preview prijal 18 z 18 podujatí
- online preview prijal 18 z 18 podujatí
- správne sa spracujú začiatky, konce, slovenské časové pásmo a ceny
- komentované prehliadky kostolov majú cenu 4 EUR a nie sú označené ako bezplatné
- produkčný sync prešiel bez chyby
- udalosti boli uložené do review frontu
- ďalší balík: hromadná kontrola zdrojov zo všetkých ôsmich krajov