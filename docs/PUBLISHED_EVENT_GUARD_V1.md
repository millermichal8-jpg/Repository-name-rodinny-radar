# Published Event Guard V1

## Cieľ

Zabrániť tomu, aby sa do mobilnej aplikácie publikovali kategórie namiesto podujatí, neplatné odkazy alebo udalosti s dátumom vytiahnutým z opisného textu namiesto z poľa **Kdy/Termín**.

## Opravy

- Praha 12 povoľuje iba detailné URL v tvare `/nazov/a-12345`.
- Listing parser sleduje iba odkazy obsahujúce `/a-`.
- Generické kategórie ako `Kulturní akce, zábava` a `Ostatní akce` sú blokované už v parseri.
- Rovnaké generické tituly blokuje aj Event Review, takže ich nemožno publikovať ani pri chybe konektora.
- Detailný dátum má poradie dôveryhodnosti:
  1. `time[datetime]`,
  2. nakonfigurovaný selektor,
  3. označené pole `Kdy`, `Termín`, `Dátum` alebo `Datum`,
  4. dátum z listingovej karty,
  5. až potom textový fallback.
- Štyri historické chybné položky Praha 12 sa archivujú a už sa nevracajú do review fronty.

## Bezpečný postup

1. lokálny `db reset`,
2. syntetický test s `ROLLBACK`,
3. online preview Praha 12 bez zápisu,
4. nasadenie migrácie a Edge Function,
5. ďalší preview,
6. malý kontrolovaný sync,
7. manuálna kontrola správnych termínov kín.
