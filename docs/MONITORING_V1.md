# Rodinný radar — Monitoring V1

Monitoring V1 pridáva bezpečnú prevádzkovú kontrolu nad mestskými a regionálnymi zdrojmi, automatickým Cronom a incidentmi.

## Čo sleduje

- opakované zlyhania zdroja,
- zdroje so stavom `warning` alebo `failing`,
- zdroje zaradené do Cronu bez pravidelného synchronizovania,
- chýbajúce alebo vypnuté Cron úlohy,
- posledný neúspešný beh Cron úlohy,
- zdroj, ktorý našiel odkazy, ale neprijal žiadne použiteľné podujatie.

## Režimy

### Preview

- iba vyhodnotí aktuálny stav,
- nič nezapisuje,
- nemení incidenty,
- nemení Cron,
- nevypína zdroje.

### Check

- vyhodnotí aktuálny stav,
- vytvorí alebo aktualizuje incidenty,
- automaticky uzavrie incident, keď problém zmizne,
- uloží auditný záznam kontroly.

## Závažnosť

- `critical` — opakované zlyhanie, zastavený alebo chýbajúci Cron, starý sync,
- `warning` — prvé zlyhanie alebo stav vyžadujúci kontrolu,
- `info` — zdroj našiel odkazy, ale neprijal podujatie.

## Bezpečnostné pravidlá

- žiadne automatické vypínanie zdrojov,
- žiadne automatické mazanie dát,
- žiadne odosielanie e-mailov alebo webhookov v Monitoring V1,
- externé upozornenia sa zapnú až po samostatnom teste a nastavení cieľového kanála,
- funkcia je chránená cez `CATALOG_SYNC_TOKEN`.

## Súbory

- migrácia: `supabase/migrations/20260718000600_monitoring_v1.sql`
- Edge Function: `supabase/functions/monitoring-report/index.ts`
- lokálny test: `scripts/rr-monitoring-local-test.ps1`
- preview: `scripts/rr-monitoring-preview.ps1`

## Odporúčaný postup nasadenia

1. lokálny `db reset`,
2. syntetický lokálny test,
3. lokálne preview bez Cronu,
4. Git commit a push pracovnej vetvy,
5. online dry-run migrácie,
6. databázová migrácia a deploy funkcie,
7. online preview s kontrolou Cronu,
8. až potom samostatná migrácia na automatický monitoring.
