$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "=== TypeScript kontrola ===" -ForegroundColor Cyan
npx tsc --noEmit
$tsExit = $LASTEXITCODE

$package = Get-Content "package.json" -Raw | ConvertFrom-Json
if ($package.scripts -and $package.scripts.lint) {
  Write-Host ""
  Write-Host "=== ESLint kontrola ===" -ForegroundColor Cyan
  npm run lint
  $lintExit = $LASTEXITCODE
} else {
  Write-Host "Lint skript v package.json nie je definovany - preskakujem." -ForegroundColor Yellow
  $lintExit = 0
}

Write-Host ""
if ($tsExit -eq 0 -and $lintExit -eq 0) {
  Write-Host "KONTROLA PRESLA." -ForegroundColor Green
  exit 0
}

Write-Host "KONTROLA NASLA CHYBY. Nic sa nenasadilo." -ForegroundColor Red
exit 1
