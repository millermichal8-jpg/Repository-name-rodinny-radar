# Data Quality V1

Data Quality V1 rieši rovnaké podujatie prichádzajúce z viacerých zdrojov, napríklad z mestského kalendára a ticketového portálu.

## Bezpečnostný model

- `preview` iba obnoví tabuľku kandidátov a nič nemení v `public.experiences`.
- Automatické spájanie nie je zapnuté.
- Skutočný merge vyžaduje konkrétny `candidateId` a `confirmWrite: true`.
- Každý merge sa zapisuje do `private.experience_merge_log` so snapshotom pôvodných záznamov.
- Zlúčený záznam sa nemaže; archivuje sa a prestane sa zobrazovať vo feede.
- Zdrojové odkazy, termíny, vstupenky, médiá a raw source records sa presunú na zachované podujatie.

## Skóre kandidáta

Skóre kombinuje:

- podobnosť názvu: 58 %,
- podobnosť termínu: 22 %,
- zhodu mesta: 15 %,
- podobnosť miesta: 5 %.

Kandidát sa vytvorí od skóre `0.72`. Pole `autoMergeEligible` je iba informatívne; Data Quality V1 nič automaticky nespája.

## Lokálny test

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rr-data-quality-local-test.ps1
```

Test vytvorí dve syntetické podujatia v transakcii, nájde kandidáta, zlúči ho, skontroluje zdroje a audit a následne vykoná `ROLLBACK`.

## Preview cez Edge Function

Najprv lokálne spusti funkciu:

```powershell
npx supabase functions serve data-quality-review --no-verify-jwt --env-file <lokálny-env-s-tokenom>
```

Potom:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rr-data-quality-preview.ps1
```

Po nasadení online:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rr-data-quality-preview.ps1 -Online
```
