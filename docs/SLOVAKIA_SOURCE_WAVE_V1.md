# Slovakia Source Wave V1

## Celkový výsledok

- skontrolovaných krajov: 8
- skontrolovaných zdrojov: 15
- zdravých zdrojov: 8
- prijatých budúcich podujatí: 68
- chyby požiadaviek: 0

## Výsledky zdrojov

| Kraj | Zdroj | Odkazy | Spracované | Prijaté | Vyradené | Stav |
|---|---|---:|---:|---:|---:|---|
| sk-ba | bkis-events | 6 | 6 | 5 | 1 | healthy |
| sk-ba | senec-events | 18 | 18 | 16 | 2 | healthy |
| sk-bb | bb-events | 18 | 18 | 16 | 2 | healthy |
| sk-bb | bs-kultura | 0 | 1 | 1 | 0 | healthy |
| sk-bb | zvolen-events | 5 | 5 | 5 | 0 | healthy |
| sk-ke | visit-kosice-events | 10 | 10 | 8 | 2 | healthy |
| sk-nr | nitra-city-events | 0 | 0 | 0 | 0 | empty |
| sk-po | pko-presov-events | 11 | 11 | 11 | 0 | healthy |
| sk-po | velky-saris-events | 2 | 2 | 0 | 2 | links-only |
| sk-tn | bojnice-events | 6 | 6 | 6 | 0 | healthy |
| sk-tn | visit-trencin-events | 3 | 0 | 0 | 0 | links-only |
| sk-tt | trnava-city-events | 0 | 0 | 0 | 0 | empty |
| sk-tt | trnava-kultura-events | 0 | 0 | 0 | 0 | empty |
| sk-za | tvrdosin-events | 0 | 0 | 0 | 0 | empty |
| sk-za | zilina-events | 0 | 0 | 0 | 0 | empty |

## Fungujúce zdroje

- Bratislavské kultúrne a informačné stredisko
- Senec
- Bojnice
- Kultúrne centrum Banská Štiavnica
- Zvolen
- Banská Bystrica
- PKO Prešov
- Visit Košice

## Zdroje na opravu

- Visit Trenčín našiel odkazy, ale nespracoval ich detaily
- Trnava mesto nenašla odkazy
- Kultúra Trnava nenašla odkazy
- Nitra nenašla odkazy
- Žilina nenašla odkazy
- Tvrdošín nenašiel odkazy

## Zdroj bez aktuálnych budúcich podujatí

Veľký Šariš našiel a spracoval dve podujatia, ale obe už boli minulé.
Toto zatiaľ nepovažujeme za chybu adaptéra.

## Nasledujúci postup

1. zistiť technológie nefungujúcich stránok,
2. zoskupiť stránky používajúce rovnaký systém,
3. vytvoriť spoločný adaptér pre celú skupinu,
4. samostatný adaptér pripraviť iba pre výnimky,
5. po preview vykonať kontrolovaný produkčný sync.