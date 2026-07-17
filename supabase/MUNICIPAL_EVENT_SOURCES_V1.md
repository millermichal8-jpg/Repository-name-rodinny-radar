# Municipal event sources V1

Prvý produktový balík Rodinného radaru:

- register 4 official Slovak event sources,
- discover event detail links,
- extract Schema.org Event/Offer when available,
- use a conservative HTML fallback when JSON-LD is missing,
- parse dates, free entry, EUR prices, city, image and basic venue text,
- deduplicate preview candidates,
- save good candidates to catalog V2 with `publication_status = review`,
- keep raw source payload in `private.source_records`.

Initial official sources:

- Banská Bystrica
- Bojnice
- Zvolen
- Kultúrne centrum Banská Štiavnica

The preview action does not write to the catalog.
