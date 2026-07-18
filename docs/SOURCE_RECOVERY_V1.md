# Source Recovery V1

## Cieľ

Obnoviť získavanie podujatí z piatich zdrojov, ktoré síce zverejňovali odkazy na podujatia, ale parser z detailu nevytvoril kandidáta:

- OstravaInfo
- Olomoucký kraj
- BKIS Bratislava
- Senec
- Banská Bystrica

## Čo sa mení

- výber hlavného obsahu už neberie prvý nájdený `.content`, ale najväčší relevantný kontajner,
- zoznamové karty dodajú parseru názov a dátum ako bezpečný fallback,
- detail podujatia sa číta od posledného výskytu názvu, čím sa preskočia breadcrumb a kategórie,
- pribudla podpora rozsahov `od 20. 3. 2026, do 20. 9. 2026` a rozsahov s rokom pri oboch dátumoch,
- BKIS používa správnu cestu `/udalost/...`,
- všetkých päť zdrojov používa card-seeded detail parser.

## Bezpečnosť

- inštalátor mení iba lokálnu pracovnú vetvu,
- produkčná databáza, online funkcia a Cron sa počas inštalácie nemenia,
- ostré nasadenie sa vykoná až po lokálnom teste, commite a online dry-run teste.

## Očakávaný výsledok

Online preview má pri najmenej jednom z piatich zdrojov vrátiť `parsedCandidates > 0`. Cieľom je dostať všetkých päť zdrojov zo stavu `links-only` do `healthy` alebo do presne vysvetleného `empty/rejected` stavu bez parser erroru.
