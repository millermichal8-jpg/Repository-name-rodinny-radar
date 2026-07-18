# Source Reliability V1

## Cieľ

Oddeliť technicky pokazený zdroj od webu, ktorý funguje, ale momentálne nemá použiteľné budúce podujatie.

## Čo opravuje

- úspešný beh s `accepted = 0` už nie je `warning`, ale `empty`,
- skutočná chyba detailu alebo zoznamu ostáva `warning`,
- tri po sebe idúce technické zlyhania ostávajú `failing`,
- monitoring pri zdroji s odkazmi bez prijatej udalosti vytvorí iba informačný nález,
- parser zaznamenáva chyby jednotlivých detailov a dôvody odmietnutia po zdrojoch,
- nový report ukáže `healthy`, `empty`, `links-only`, `warning` a `failing` zdroje.

## Bezpečnosť

- inštalácia nemení produkciu ani Cron,
- lokálny test používa transakciu a `ROLLBACK`,
- preview nič nezapisuje,
- produkčné nasadenie sa robí až po lokálnom teste, commite a `db push --dry-run`.

## Súbory

- `supabase/migrations/20260718000800_source_reliability_v1.sql`
- `supabase/functions/municipal-event-sync/index.ts`
- `scripts/rr-source-reliability-local-test.ps1`
- `scripts/rr-source-reliability-preview.ps1`
