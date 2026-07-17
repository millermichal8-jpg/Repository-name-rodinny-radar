param(
  [string[]]$SourceCodes = @(
    "bb-events",
    "bojnice-events",
    "zvolen-events",
    "bs-kultura"
  ),
  [int]$MaxEvents = 40
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) {
  Write-Host ""
  Write-Host "==> $Text" -ForegroundColor Cyan
}

Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not (Test-Path ".\supabase\config.toml")) {
  throw "Skript spusti v projekte rodinny-radar."
}

Step "Kontrolujem lokalny Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokalny Supabase nebezi. Spusti npx supabase start."
}

$envFile = ".\supabase\functions\.env"
$envDir = Split-Path $envFile -Parent
New-Item -ItemType Directory -Path $envDir -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $envFile,
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  $utf8NoBom
)
$stdout = ".\supabase\municipal-serve.out.log"
$stderr = ".\supabase\municipal-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam lokalnu Edge Function"
$process = Start-Process `
  -FilePath "cmd.exe" `
  -ArgumentList @(
    "/c",
    "npx supabase functions serve municipal-event-sync --no-verify-jwt --env-file supabase/functions/.env"
  ) `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr

try {
  Start-Sleep -Seconds 10

  if ($process.HasExited) {
    $details = @()
    if (Test-Path $stdout) { $details += Get-Content $stdout -Raw }
    if (Test-Path $stderr) { $details += Get-Content $stderr -Raw }
    throw "Edge Function sa nespustila.`n$($details -join "`n")"
  }

  $body = @{
    action = "preview"
    sourceCodes = $SourceCodes
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 5

  Step "Spustam preview oficialnych kalendarov"
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body $body `
    -TimeoutSec 180

  $resultsDir = ".\supabase\test-results"
  New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
  $resultPath = Join-Path $resultsDir "municipal-preview.json"
  $response | ConvertTo-Json -Depth 20 |
    Set-Content -Path $resultPath -Encoding UTF8

  Write-Host ""
  Write-Host "PREVIEW PRESIEL" -ForegroundColor Green
  Write-Host "Zdroje: $($response.stats.sourceCount)"
  Write-Host "Najdene pred deduplikaciou: $($response.stats.parsed)"
  Write-Host "Po deduplikacii: $($response.stats.afterDedupe)"
  Write-Host "Pripravene na kontrolu: $($response.stats.readyForReview)"
  Write-Host "Vysledok: $resultPath" -ForegroundColor Green

  Write-Host ""
  $response.preview |
    Select-Object -First 15 title, startDate, city, priceMin, freeEntry, qualityScore |
    Format-Table -AutoSize
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
