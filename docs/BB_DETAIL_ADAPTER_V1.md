# Banska Bystrica Detail Adapter V1

Tento balik upravuje `municipal-event-sync` pre zdroj `bb-events`.

## Opravy

- cita presny zaciatok aj koniec z `time[itemprop=startDate/endDate]`,
- cas bez timezone interpretuje ako Europe/Bratislava,
- pouziva ciste miesto z `itemprop=location`,
- berie popis iba z hlavnej casti podujatia,
- pouziva originalny obrazok z detailu,
- pri cene uprednostni realnu platenu cenu pred textom typu "deti zdarma",
- zapisuje diagnostiku `bb-citio-detail-v1`.

## Bezpecnost

Instalator nic nenasadzuje online a nic nezapisuje do produkcnej databazy.
Najprv sa spusti lokalny preview test bez zapisu.
