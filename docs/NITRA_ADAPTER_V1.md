# Nitra Calendar Adapter V1

## Zdroj

Oficialny kalendar udalosti:

`https://www.nitra.eu/kalendar`

## Co adapter robi

- cita iba detailne odkazy v tvare `/kalendar/<id>/<slug>`
- berie nazov priamo z karty udalosti
- spracuje datum, zaciatok a koniec
- cita miesto, kratky popis, obrazok a cenu
- oznaci zrusene podujatia
- ignoruje navigacne odkazy, strankovanie a iCal export

## Bezpecnost

- migracia meni iba konfiguraciu zdroja `nitra-city-events`
- Cron zostava vypnuty
- lokalny test pouziva iba lokalnu databazu
- instalator nic nenasadzuje online
- produkcny zapis podujati sa nevykona

## Dalsi postup

1. nainstalovat balik na vetve `wip/nitra-zilina-tvrdosin-adapter-v1`
2. spustit lokalny test
3. skontrolovat vysledok
4. az potom pripravit Git commit a online preview bez zapisu

<!-- PRODUCTION_RESULT_START -->

## Finalny overeny vysledok

- detailne odkazy: 21
- prijate udalosti: 14
- udalosti s casom: 14
- udalosti s miestom: 14
- udalosti s obrazkom: 11
- produkcny zapis: 14
- chyby zdroja: 0
- chyby zapisu: 0
- publikacny stav: review
- automaticke publikovanie: nie
- finalny report: C:\Users\radko\Desktop\rr-nitra-retry-20260720-160901\FINAL-SUCCESS.json

Prvy produkcny pokus zachytil docasny HTTP 500 zo zdroja.
Tento pokus zapisal 0 zaznamov. Kontrolovane opakovanie najskor
overilo preview a potom uspesne zapisalo vsetkych 14 udalosti.

<!-- PRODUCTION_RESULT_END -->
