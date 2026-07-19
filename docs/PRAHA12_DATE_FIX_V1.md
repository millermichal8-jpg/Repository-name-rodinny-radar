# Praha 12 Date Fix V1

Oprava rieši dve chyby parsera:

- kompaktný text `Kdy:23.7.2026 21:30Kde:...` sa správne ukončí pred poľom `Kde`,
- rozsah `1.8.2026 - 31.8.2026` sa spracuje ako viacdňové podujatie.

Očakávané výsledky:
- Křtiny: 23. 7. 2026 o 21:30, `allDay = false`
- Šviháci: 30. 7. 2026 o 21:15, `allDay = false`
- Eva Vokatá: 1. 8. – 31. 8. 2026
