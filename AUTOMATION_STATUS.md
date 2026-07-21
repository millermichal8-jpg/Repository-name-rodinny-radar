# Automatizacia Rodinneho radaru

Vytvorene: 2026-07-15 20:41:06
Projekt ref: xvqzpbfcxhrxgovkkajt

## Hotovo
- bezpecny .gitignore
- lokalny Supabase CLI
- supabase/config.toml
- skript na stiahnutie Edge Functions
- skript na kontrolu TypeScriptu a lint
- skript na nasadenie jednej funkcie
- .env.example bez tajnych hodnot

## Dalsi krok
1. Prihlasit Supabase CLI.
2. Stiahnut vsetky vzdialene Edge Functions.
3. Skontrolovat, ci Git neobsahuje tajne kluce.
4. Publikovat privatny GitHub repozitar.
5. Zachytit databazu do migracii.
6. Pridat CI/CD az po prvom cistom commite.

<!-- AUTOMATION_STATUS_20260721_START -->

## Overený stav 21. 7. 2026

- lokálny Supabase CLI, Docker workflow, migrácie a Edge Functions fungujú
- súkromný GitHub je zapojený a pracovná vetva sleduje origin
- Event Review V1 používa chránený `CATALOG_SYNC_TOKEN`
- Tvrdošín bol synchronizovaný do produkčného review stavu
- 44 záznamov je pending a pripravených na kontrolované publikovanie
- automatické publikovanie zostáva vypnuté
- jeden pracovný deň používa jeden spoločný PowerShell transcript

<!-- AUTOMATION_STATUS_20260721_END -->
