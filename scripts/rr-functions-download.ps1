param(
  [string]$ProjectRef = "xvqzpbfcxhrxgovkkajt"
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Prihlasujem Supabase CLI..." -ForegroundColor Cyan
npx supabase login

Write-Host "Stahujem vsetky Edge Functions zo Supabase..." -ForegroundColor Cyan
npx supabase functions download --project-ref $ProjectRef --use-api

Write-Host "HOTOVO - funkcie su v supabase/functions" -ForegroundColor Green
