# Municipal Parser V3

V3 removes the generic heading/parent crawler.

It uses three deterministic source adapters:

- CITIO: exact `/podujatia/<slug>/` detail pages.
- Webygroup: exact `/akcia/<slug>/mid/<id>/.html` detail pages and labelled fields `Dátum`, `Do`, `Čas`, `Miesto`, `Vstupné`, `Popis`.
- Ticketware: only the smallest homepage card containing exactly one `/event/<id>/<slug>` URL and its own visible date.

Important behavior:

- A missing year is interpreted as the current year, never silently moved to the next year.
- Past events are rejected instead of being converted into future events.
- Detail dates are never taken from page footers, calendars, related events or navigation.
- Similar titles are deduplicated only when city and start time also match.
- Preview has hard assertions and fails when it finds navigation text, past events or zero valid events.
