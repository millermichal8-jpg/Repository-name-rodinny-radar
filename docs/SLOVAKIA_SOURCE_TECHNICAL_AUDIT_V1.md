# Slovakia Source Technical Audit V1

## Účel

Technický audit zisťuje, prečo niektoré slovenské zdroje
nevracajú udalosti cez všeobecný municipal parser.

Audit nemení produkciu ani databázu.

## Výsledok

- kontrolovaných stránok: 8
- úspešne stiahnutých stránok: 8
- chýb požiadaviek: 0

## Technický prehľad

| Zdroj | HTTP | Odkazy | Event odkazy | Query ID | API | Dátumy | Odporúčanie |
|---|---:|---:|---:|---:|---:|---:|---|
| trnava-city-current | 200 | 124 | 24 | 0 | 0 | 0 | Overiť presmerovanie a pravdepodobne nahradiť starú URL. |
| trnava-city-candidate | 200 | 106 | 6 | 0 | 0 | 0 | Mestská stránka je skôr rozcestník; zvážiť vypnutie duplicity. |
| trnava-kultura | 200 | 59 | 16 | 1 | 0 | 0 | Vytvoriť calendar-list adaptér pre položky priamo v kalendári. |
| visit-trencin | 200 | 111 | 34 | 6 | 6 | 17 | Vytvoriť query-id detail adaptér pre odkazy typu ?id=123. |
| nitra-city | 200 | 289 | 7 | 0 | 4 | 2 | Vytvoriť list-only adaptér pre ročný plán bez detailných stránok. |
| zilina-current | 200 | 129 | 6 | 0 | 4 | 0 | Opraviť URL alebo nájsť dátový endpoint dynamického kalendára. |
| zilina-candidate | 200 | 129 | 6 | 0 | 4 | 0 | Preskúmať skripty a API volania dynamického kalendára. |
| tvrdosin-home | 200 | 336 | 22 | 0 | 1 | 11 | Nájsť reálnu podstránku kalendára cez odkazy z homepage. |

## Predbežné skupiny adaptérov

### Calendar-list adaptér

- Trnava kultúra
- udalosti sú priamo vo výpise kalendára
- detailná URL nemusí byť potrebná pre každú položku

### Query-ID detail adaptér

- Visit Trenčín
- detailné stránky používajú parameter ?id=...

### List-only ročný adaptér

- Nitra
- zdroj obsahuje ročný plán podujatí v jednej stránke

### Dynamický kalendár alebo API endpoint

- Žilina
- obsah sa môže načítavať JavaScriptom alebo cez samostatný endpoint

### Navigačný audit

- Tvrdošín
- z hlavnej stránky treba nájsť skutočnú podstránku podujatí

### Kandidát na odstránenie duplicity

- mestská stránka Trnavy
- hlavný dátový zdroj bude pravdepodobne kultúrny kalendár

## Nasledujúci krok

Ako prvý implementovať spoločný balík:

1. Trnava calendar-list adaptér,
2. Visit Trenčín query-ID adaptér,
3. spoločný lokálny preview test,
4. až potom riešiť Nitru, Žilinu a Tvrdošín.