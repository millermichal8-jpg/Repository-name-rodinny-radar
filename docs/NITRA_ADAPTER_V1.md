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
