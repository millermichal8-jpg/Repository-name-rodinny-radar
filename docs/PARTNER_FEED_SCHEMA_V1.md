# Rodinný radar – Partner Feed Schema V1

Partner konektory sú zámerne vypnuté, kým poskytovateľ neposkytne písomný súhlas a schválený API alebo feed prístup.

Edge Function: `partner-ticket-sync`

## Povinné polia udalosti

```json
{
  "externalId": "provider-123",
  "title": "Názov podujatia",
  "sourceUrl": "https://partner.example/event/provider-123",
  "startDate": "2026-08-20T18:00:00+02:00",
  "countryCode": "SK"
}
```

## Voliteľné polia

```json
{
  "endDate": "2026-08-20T20:00:00+02:00",
  "purchaseUrl": "https://partner.example/buy/provider-123",
  "summary": "Krátky popis",
  "description": "Dlhší popis",
  "city": "Banská Bystrica",
  "region": "Banskobystrický kraj",
  "venueName": "Amfiteáter",
  "address": "Ulica 1, Banská Bystrica",
  "imageUrl": "https://partner.example/image.jpg",
  "allDay": false,
  "freeEntry": false,
  "priceMin": 15,
  "priceMax": 25,
  "currency": "EUR"
}
```

Feed môže byť priamo pole udalostí alebo objekt s poľom `events`, `items`, `data` alebo `results`.

## Bezpečnostné pravidlá

- `preview` a `validate` môžu pracovať so syntetickými `events` v tele požiadavky.
- `sync` odmietne udalosti vložené priamo v požiadavke.
- `sync` používa iba HTTPS URL uloženú v serverovej premennej konkrétneho partnera.
- `sync` je zablokovaný, kým je konektor v databáze `enabled = false`.
- nové záznamy idú cez katalóg V2 najprv do stavu `review`.
