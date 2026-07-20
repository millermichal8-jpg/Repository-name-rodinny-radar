# Tvrdošín Adapter V1

## Overený zdroj

- hlavná stránka: https://www.tvrdosin.sk/aktualne/kalendar-akcii/
- oficiálny dokument: Kalendár podujatí Tvrdošín 2026
- PDF má 27 strán a približne 20 MB
- online HTML kalendár momentálne neobsahuje použiteľné riadky podujatí
- mesačný AJAX vracia iba mriežku dní bez detailov udalostí
- 16 nájdených HTML kandidátov boli navigačné odkazy, nie podujatia

## Zvolená architektúra

Edge Function nebude pri každom behu sťahovať a analyzovať 20 MB PDF.
Adapter používa kontrolovaný snapshot 44 výslovne datovaných verejných
a rodinne relevantných udalostí z oficiálneho PDF. Každý záznam odkazuje
na konkrétnu stranu dokumentu.

Parser marker: `tvrdosin-official-pdf-snapshot-v1`

## Bezpečnosť

- cron zostáva vypnutý
- všetky udalosti pri ostrom synchrónnom zápise smerujú do `review`
- žiadna udalosť sa automaticky nepublikuje
- snapshot vyžaduje kontrolovanú aktualizáciu pri novom ročnom kalendári
- udalosti bez presného dátumu a zjavne interné školské aktivity boli vynechané

## Očakávaný lokálny preview

- nakonfigurované udalosti: 44
- aktuálne prijaté udalosti 20. 7. 2026: približne 44
- chyby zdroja: 0
- zápisy: 0

## Produkcia

Zatiaľ nenasadené. Najprv musí prejsť lokálny test a následne online preview
bez zápisu.

<!-- LOCAL_RESULT_FINAL_START -->

## Final verified local result

- configured PDF events: 44
- accepted current events: 44
- preview items: 44
- events with explicit time: 13
- errors: 0
- preview writes: 0
- production changes: 0
- status: ready for safe online dry-run and preview

<!-- LOCAL_RESULT_FINAL_END -->
