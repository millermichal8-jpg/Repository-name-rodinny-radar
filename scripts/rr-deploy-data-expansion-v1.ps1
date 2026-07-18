param(
  [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $ConfirmProduction) {
  throw "Produkčne nasadenie je zablokovane. Pouzi -ConfirmProduction az po uspesnom lokalnom preview a malom sync teste."
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "==> Kontrolujem Git" -ForegroundColor Cyan
$dirty = git status --porcelain
if ($LASTEXITCODE -ne 0) { throw "Git kontrola zlyhala." }
if ($dirty) { throw "Projekt nema cisty Git stav. Najprv commitni alebo vrat zmeny." }

Write-Host "==> Nasadzujem databazovu migraciu" -ForegroundColor Cyan
npx supabase db push
if ($LASTEXITCODE -ne 0) { throw "supabase db push zlyhal." }

Write-Host "==> Nasadzujem municipal-event-sync V4" -ForegroundColor Cyan
npx supabase functions deploy municipal-event-sync --no-verify-jwt
if ($LASTEXITCODE -ne 0) { throw "Deploy municipal-event-sync zlyhal." }

Write-Host "==> Nasadzujem data-expansion-orchestrator V1" -ForegroundColor Cyan
npx supabase functions deploy data-expansion-orchestrator --no-verify-jwt
if ($LASTEXITCODE -ne 0) { throw "Deploy orchestratora zlyhal." }

Write-Host ""
Write-Host "PRODUKCNE NASADENIE DOKONCENE" -ForegroundColor Green
Write-Host "Cron ostava vypnuty. Najprv urob produkcny preview jednej malej skupiny." -ForegroundColor Yellow
