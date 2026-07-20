# Zilina Adapter V1

## Source

- Official city endpoint: `https://zilina.sk/wp-json/iq/v1/event/list`
- Public detail URLs: `https://zilina.sk/podujatie/...`
- Adapter marker: `zilina-wordpress-api-v1`

## Why this source

The city page loads events from a structured WordPress endpoint. The API returns event IDs, titles, date ranges, optional times, descriptions, addresses, images and ticket or web links. This is more stable than scraping the rendered page.

## Probe result on 2026-07-20

- WordPress event archive reported 1,000 records.
- Five archive pages contained 500 real JSON records. The old PowerShell probe displayed 5 because each page array was counted as one object.
- The live event-list endpoint returned 100 records and included 6 active or future events at the time of the probe.
- All 15 read-only requests succeeded.

## Safety

- The migration keeps cron disabled.
- The local test uses preview only.
- Production deployment and event sync are separate later steps.
- Synced events will remain in `review` until explicitly approved.

<!-- PRODUCTION_RESULT_START -->

## Finalny overeny vysledok

- API zaznamy: 100
- aktualne prijate udalosti: 6
- udalosti s obrazkom: 6
- produkcny zapis: 6
- chyby zdroja: 0
- chyby zapisu: 0
- publikacny stav: review
- automaticke publikovanie: nie
- finalny report: C:\Users\radko\Desktop\rr-zilina-production-sync-20260720-192913.json

<!-- PRODUCTION_RESULT_END -->
