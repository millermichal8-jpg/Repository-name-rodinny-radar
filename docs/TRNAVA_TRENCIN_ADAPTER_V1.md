# Trnava + Visit Trenčín Adapter V1

## Cieľ

Balík opravuje tri oficiálne mestské zdroje, ktoré v celoslovenskom preview
nevracali použiteľné budúce podujatia:

- `trnava-city-events`
- `trnava-kultura-events`
- `visit-trencin-events`

## Riešenie

### Mesto Trnava

Parser otvára iba detailné adresy v tvare:

`https://www.trnava.sk/podujatia/<id>/<slug>`

Z detailu číta názov, presný začiatok a koniec z poľa `Kedy`, miesto,
popis a obrázok. Navigačné nadpisy mesta sa nepoužijú ako názov podujatia.

### Kultúra Trnava

Parser otvára iba detailné adresy v tvare:

`https://kultura.trnava.sk/podujatie/<slug>`

Z detailu číta hlavný názov, dátum alebo rozsah dátumov, čas uvedený v popise,
popis, obrázok a informáciu o bezplatnom alebo platenom vstupe.

### Visit Trenčín

Parser podporuje detailné adresy, pri ktorých konkrétne podujatie určuje
parameter `?id=`:

`https://visit.trencin.sk/podujatia/?id=<id>`

Na stránke spracuje iba prvý hlavný detail podujatia, nie ďalšie odporúčané
akcie zobrazené pod ním. Číta dátum, čas, miesto, adresu, popis a obrázok.

## Bezpečnosť

- migrácia ponecháva Cron vypnutý,
- lokálny test používa iba akciu `preview`,
- lokálny test nič nezapisuje do produkčnej databázy,
- online nasadenie ani ostrý sync nie sú súčasťou inštalátora.

## Očakávaný lokálny výsledok

- Trnava mesto nájde detailné odkazy a prijme budúce alebo prebiehajúce akcie,
- Kultúra Trnava prijme viacero letných podujatí,
- Visit Trenčín prijme aspoň prebiehajúce `Divadielka pod vežou 2026`,
- všetky prijaté položky použijú jeden z parserov:
  - `trnava-city-detail-v1`
  - `trnava-kultura-detail-v1`
  - `visit-trencin-query-detail-v1`
