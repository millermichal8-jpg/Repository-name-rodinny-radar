# RodinnĂ˝ radar â€“ stav projektu

**PoslednĂˇ overenĂˇ aktualizĂˇcia:** 18. 7. 2026  
**HlavnĂˇ vetva:** `main`  
**GitHub:** sĂşkromnĂ˝ repozitĂˇr, lokĂˇlna vetva sleduje `origin/main`

## CieÄľ

MobilnĂˇ aplikĂˇcia pre rodiÄŤov, ktorĂˇ nĂˇjde trvalĂ© vĂ˝lety aj aktuĂˇlne podujatia
podÄľa mesta, vzdialenosti, dĂˇtumu, poÄŤtu ÄľudĂ­ a veku detĂ­.

---

## TechnolĂłgie

- React Native
- Expo SDK 54
- Expo Go
- TypeScript
- Supabase
- Supabase Edge Functions
- PostgreSQL + PostGIS
- Docker Desktop + lokĂˇlny Supabase
- Google Places API
- Ticketmaster Discovery API
- Git + GitHub

---

## ÄŚo funguje

### MobilnĂˇ aplikĂˇcia

- aplikĂˇcia sa spĂşĹˇĹĄa v Expo Go
- letnĂ˝ vizuĂˇlny ĹˇtĂ˝l
- zadanie mesta s naĹˇepkĂˇvanĂ­m miest a obcĂ­ SK/CZ
- poÄŤet dospelĂ˝ch
- poÄŤet detĂ­
- samostatnĂ˝ vek kaĹľdĂ©ho dieĹĄaĹĄa
- vĂ˝ber maximĂˇlnej vzdialenosti
- trvalĂ© vĂ˝lety z Google Places
- rozkliknuteÄľnĂ˝ detail vĂ˝letu
- adresa, hodnotenie, web, telefĂłn a otvĂˇracie hodiny pri vĂ˝lete
- sekcia **AktuĂˇlne podujatia**
- reĂˇlne podujatia naÄŤĂ­tanĂ© z online katalĂłgu
- rozkliknuteÄľnĂ˝ detail podujatia
- filtre:
  - VĹˇetky
  - Dnes
  - Tento vĂ­kend
  - Zadarmo
- radenie podÄľa termĂ­nu alebo vzdialenosti
- otvorenie oficiĂˇlnej strĂˇnky alebo odkazu na lĂ­stky

### DatabĂˇza a katalĂłg V2

- univerzĂˇlny katalĂłg pre atrakcie aj podujatia
- miesta a areĂˇly
- organizĂˇtori
- zĂˇĹľitky
- konkrĂ©tne termĂ­ny
- vstupenky a ceny
- mĂ©diĂˇ
- viac zdrojov jednej akcie
- raw zdrojovĂ© zĂˇznamy
- histĂłria synchronizĂˇciĂ­
- kandidĂˇti na duplicity
- histĂłria cien
- kontrola kvality
- jednotnĂ˝ `experience_feed`
- geografickĂ© vyhÄľadĂˇvanie cez PostGIS

### Ticketmaster

- Ticketmaster Discovery API je pripojenĂ©
- preview reĹľim bez zĂˇpisu funguje
- ostrĂ˝ sync do katalĂłgu funguje
- ÄŤeskĂ© podujatia sa ĂşspeĹˇne zapisujĂş
- Slovensko momentĂˇlne cez Ticketmaster vracia 0 udalostĂ­
- Ticketmaster ostĂˇva doplnkovĂ˝ zdroj, nie hlavnĂ˝ slovenskĂ˝ zdroj

### SlovenskĂ© mestskĂ© a kultĂşrne zdroje

Municipal parser V3 je nasadenĂ˝ online a funguje pre:

- Bojnice
- Zvolen
- KultĂşrne centrum BanskĂˇ Ĺ tiavnica

Parser:

- vyhÄľadĂˇva detailnĂ© strĂˇnky podujatĂ­
- ÄŤĂ­ta Schema.org Event/Offer, keÄŹ sĂş dostupnĂ©
- pouĹľĂ­va HTML fallback
- zĂ­skava nĂˇzov, termĂ­n, mesto, obrĂˇzok a cenu alebo vstup zdarma
- filtruje starĂ© a neplatnĂ© poloĹľky
- prideÄľuje skĂłre kvality
- robĂ­ zĂˇkladnĂş deduplikĂˇciu
- zapisuje udalosti do katalĂłgu V2
- overenĂ© udalosti sĂş publikovanĂ© online
- mobilnĂ˝ `experience-feed` ich vracia aplikĂˇcii

### VĂ˝vojovĂ© prostredie a automatizĂˇcia

- Git repozitĂˇr je inicializovanĂ˝
- projekt je pushnutĂ˝ na sĂşkromnĂ˝ GitHub
- existuje bezpeÄŤnĂ˝ nĂˇvratovĂ˝ baseline commit
- Supabase CLI je nainĹˇtalovanĂ© lokĂˇlne
- vĹˇetky Edge Functions sĂş v `supabase/functions`
- databĂˇzovĂ© migrĂˇcie sĂş v `supabase/migrations`
- referenÄŤnĂ© dĂˇta sĂş v `supabase/seed.sql`
- lokĂˇlny Supabase beĹľĂ­ cez Docker
- databĂˇza sa dĂˇ vytvoriĹĄ od nuly cez migrĂˇcie a seed
- `db reset` bol ĂşspeĹˇne overenĂ˝
- lokĂˇlne testovacie vĂ˝stupy a secrets sĂş ignorovanĂ© v Gite
- produkÄŤnĂ© migrĂˇcie aj Edge Functions sa dajĂş nasadzovaĹĄ cez CLI

---

## ÄŚo zatiaÄľ nefunguje alebo nie je dokonÄŤenĂ©

### Pokrytie dĂˇt

- databĂˇza podujatĂ­ je stĂˇle malĂˇ
- BanskĂˇ Bystrica zatiaÄľ naĹˇla odkazy, ale neprijala pouĹľiteÄľnĂ© udalosti
- chĂ˝ba vlastnĂ˝ adaptĂ©r pre BanskĂş Bystricu
- chĂ˝ba vĂ¤ÄŤĹˇina slovenskĂ˝ch miest, regiĂłnov a kultĂşrnych centier
- chĂ˝ba systematickĂ© pokrytie vĹˇetkĂ˝ch 8 slovenskĂ˝ch krajov
- ÄŤeskĂ© mestskĂ© a regionĂˇlne zdroje eĹˇte nie sĂş pripojenĂ©
- Ticketportal eĹˇte nie je pripojenĂ˝
- Predpredaj.sk eĹˇte nie je pripojenĂ˝
- GoOut eĹˇte nie je pripojenĂ˝
- TicketLIVE eĹˇte nie je pripojenĂ˝
- Eventim eĹˇte nie je pripojenĂ˝
- Tavily eĹˇte nie je pripojenĂ©
- Firecrawl eĹˇte nie je pripojenĂ˝
- PDF programy sa eĹˇte univerzĂˇlne nespracĂşvajĂş
- JavaScriptovĂ© kalendĂˇre eĹˇte nemajĂş univerzĂˇlny fallback
- akcie zo sociĂˇlnych sietĂ­ a neverejnĂ˝ch zdrojov nie sĂş pokrytĂ©

### DeduplikĂˇcia a kvalita

- deduplikĂˇcia je zatiaÄľ zĂˇkladnĂˇ
- rovnakĂˇ akcia z mesta, organizĂˇtora a ticketovĂ©ho portĂˇlu sa eĹˇte nemusĂ­ vĹľdy spojiĹĄ
- chĂ˝ba automatickĂ˝ review panel
- chĂ˝ba sprĂˇva chĂ˝b a ruÄŤnĂ© schvaÄľovanie podozrivĂ˝ch poloĹľiek
- chĂ˝ba monitoring nefunkÄŤnĂ˝ch zdrojov
- chĂ˝ba automatickĂ© vyradenie dlhodobo nefunkÄŤnĂ˝ch zdrojov
- chĂ˝ba automatickĂˇ kontrola zruĹˇenĂ˝ch a presunutĂ˝ch podujatĂ­
- histĂłria cien je pripravenĂˇ, ale eĹˇte sa pravidelne neplnĂ­

### MobilnĂˇ aplikĂˇcia

- fotografie podujatĂ­ a vĂ˝letov nie sĂş vyrieĹˇenĂ© jednotne
- karty eĹˇte nie sĂş finĂˇlne dizajnovo doladenĂ©
- obÄľĂşbenĂ© poloĹľky sa neukladajĂş trvalo do ĂşÄŤtu
- pouĹľĂ­vateÄľskĂ© ĂşÄŤty a prihlĂˇsenie nie sĂş hotovĂ©
- synchronizĂˇcia medzi zariadeniami nie je hotovĂˇ
- vzdialenosĹĄ je pri ÄŤasti obsahu stĂˇle iba pribliĹľnĂˇ
- reĂˇlna cesta autom nie je dokonÄŤenĂˇ pre vĹˇetok obsah
- vlak, autobus, prestupy a ÄŤas chĂ´dze nie sĂş dokonÄŤenĂ©
- chĂ˝ba finĂˇlna kategorizĂˇcia podÄľa veku detĂ­
- chĂ˝ba komplexnĂ© filtrovanie podÄľa kategĂłrie, ceny a dostupnosti
- chĂ˝ba mapa vĂ˝sledkov
- chĂ˝ba finĂˇlne prĂˇzdne/loading/error UI
- chĂ˝ba produkÄŤnĂ˝ onboarding

### Produkcia a automatickĂ© behy

- Cron synchronizĂˇcie eĹˇte nie sĂş finĂˇlne nastavenĂ© pre vĹˇetky zdroje
- chĂ˝ba centrĂˇlny orchestrĂˇtor dĂˇvok
- chĂ˝ba automatickĂ˝ retry pri doÄŤasnom vĂ˝padku webu
- chĂ˝ba upozornenie pri chybe konektora
- chĂ˝ba dashboard spotreby API a kvĂłt
- chĂ˝ba oddelenĂ© staging prostredie
- chĂ˝ba CI/CD kontrola pri kaĹľdom commite
- chĂ˝bajĂş automatickĂ© integraÄŤnĂ© testy pre vĹˇetky konektory

### PrĂˇvne a obchodnĂ© veci

- chĂ˝bajĂş pravidlĂˇ atribĂşcie zdrojov
- chĂ˝bajĂş partnerskĂ© dohody s ticketovĂ˝mi portĂˇlmi
- chĂ˝bajĂş podmienky pouĹľĂ­vania
- chĂ˝ba ochrana osobnĂ˝ch Ăşdajov a zĂˇsady sĂşkromia
- monetizĂˇcia a predplatnĂ© nie sĂş implementovanĂ©

---

## AktuĂˇlny hlavnĂ˝ cieÄľ

Najprv vĂ˝razne zvĂ¤ÄŤĹˇiĹĄ databĂˇzu podujatĂ­.

Poradie:

1. pridaĹĄ zdroje pre vĹˇetkĂ˝ch 8 slovenskĂ˝ch krajov
2. pridaĹĄ prvĂş vlnu ÄŤeskĂ˝ch miest a regiĂłnov
3. vytvoriĹĄ dĂˇvkovĂ˝ orchestrĂˇtor
4. vytvoriĹĄ report fungujĂşcich a nefunkÄŤnĂ˝ch zdrojov
5. rozĹˇĂ­riĹĄ deduplikĂˇciu
6. nastaviĹĄ automatickĂ© pravidelnĂ© synchronizĂˇcie
7. aĹľ potom jednotne rieĹˇiĹĄ:
   - fotografie
   - krajĹˇie karty
   - trvalĂ© obÄľĂşbenĂ© poloĹľky

---

## NajbliĹľĹˇĂ­ pracovnĂ˝ balĂ­k

**Data Expansion V1**

- register ÄŹalĹˇĂ­ch slovenskĂ˝ch a ÄŤeskĂ˝ch zdrojov
- dĂˇvkovĂ© preview
- dĂˇvkovĂ˝ ostrĂ˝ sync
- kontrola kvality
- report zdrojov
- zĂˇkladnĂ˝ orchestrĂˇtor
- prĂ­prava na Cron
- aktualizĂˇcia tohto PROJECT_STATUS.md po ĂşspeĹˇnom nasadenĂ­

---

## PravidlĂˇ prĂˇce

- produkciu meniĹĄ iba cez overenĂş migrĂˇciu alebo nasadzovacĂ­ skript
- pred veÄľkou zmenou vytvoriĹĄ zĂˇlohu
- najprv preview alebo lokĂˇlny test
- potom malĂ˝ online sync
- aĹľ potom vĂ¤ÄŤĹˇia dĂˇvka
- po dokonÄŤenom balĂ­ku:
  - TypeScript kontrola
  - Git commit
  - Git push
  - aktualizĂˇcia `PROJECT_STATUS.md`