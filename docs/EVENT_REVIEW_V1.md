# Event Review V1

Event Review V1 pridáva bezpečný administratívny postup pre podujatia uložené v stave `review`.

## Prečo nejde priamo do mobilnej aplikácie

Mobilná aplikácia zatiaľ nemá používateľské účty ani administrátorské roly. Review nástroje preto nie sú vložené do verejnej aplikácie a neobsahujú servisný kľúč. Správa podujatí prebieha cez chránenú Supabase Edge Function `event-review`, ktorá vyžaduje `CATALOG_SYNC_TOKEN`.

## Funkcie

- fronta podujatí v stave `review`
- kontrola pripravenosti na publikovanie
- schválenie bez publikovania
- publikovanie do `experience_feed`
- zamietnutie a skrytie podujatia
- obnovenie zamietnutého podujatia späť do review
- bezpečné hromadné publikovanie iba pripravených položiek
- audit každej zmeny
- žiadny zápis bez `confirmWrite: true`

## Podmienky pripravenosti

Podujatie je pripravené na publikovanie, ak má:

- názov
- mesto
- budúci aktívny termín
- oficiálny odkaz
- požadované skóre kvality, predvolene minimálne 80
- žiadnu nevyriešenú pravdepodobnú duplicitu so skóre aspoň 0,84

## Edge Function

Názov: `event-review`

Podporované akcie:

- `queue`
- `stats`
- `audit`
- `approve`
- `publish`
- `reject`
- `restore`
- `batch-publish`

Zápisové akcie vyžadujú:

```json
{
  "confirmWrite": true
}
```

## PowerShell skripty

### Preview bez zápisu

```powershell
.\scripts\rr-event-review-preview.ps1 `
  -BaseUrl $baseUrl `
  -SyncToken $syncToken `
  -MinQuality 80 `
  -Limit 100
```

### Kontrolované hromadné publikovanie

```powershell
.\scripts\rr-event-review-batch-publish.ps1 `
  -BaseUrl $baseUrl `
  -SyncToken $syncToken `
  -MinQuality 80 `
  -Limit 100 `
  -ConfirmWrite
```

Skript publikuje iba položky, ktoré prejdú všetkými kontrolami pripravenosti. Blokované položky zostanú v review fronte.

## Databázové objekty

- `private.event_review_state`
- `private.event_review_actions`
- `private.event_review_queue_base_v1`
- `private.event_review_readiness_v1(...)`
- `public.catalog_event_review_bridge_v1(...)`

## Bezpečnostné pravidlá

- verejná mobilná aplikácia nemá prístup k review funkciám
- všetky databázové funkcie sú odobraté roli `public`
- prístup má iba `service_role` cez chránenú Edge Function
- každá zmena sa auditne zapisuje
- lokálny test prebieha v transakcii s `ROLLBACK`
