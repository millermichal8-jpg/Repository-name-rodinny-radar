param(
  [string[]]$SourceCodes = @(
    "bb-events",
    "bojnice-events",
    "zvolen-events",
    "bs-kultura"
  ),
  [int]$MaxEvents = 50
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) {
  Write-Host ""
  Write-Host "==> $Text" -ForegroundColor Cyan
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Step "Kontrolujem lokalny Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokalny Supabase nebezi. Spusti npx supabase start."
}

$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $envFile,
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  $utf8NoBom
)

$stdout = ".\supabase\municipal-v2-serve.out.log"
$stderr = ".\supabase\municipal-v2-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam municipal-event-sync V2 lokalne"
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
  Start-Sleep -Seconds 12

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

  Step "Spustam cisty preview oficialnych kalendarov"
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body $body `
    -TimeoutSec 240

  $resultsDir = ".\supabase\test-results"
  New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
  $resultPath = Join-Path $resultsDir "municipal-preview-v2.json"
  $json = $response | ConvertTo-Json -Depth 30
  [System.IO.File]::WriteAllText($resultPath, $json, $utf8NoBom)

  Write-Host ""
  Write-Host "MUNICIPAL V2 PREVIEW PRESIEL" -ForegroundColor Green
  Write-Host "Zdroje: $($response.stats.sourceCount)"
  Write-Host "Prijate pred deduplikaciou: $($response.stats.acceptedBeforeDedupe)"
  Write-Host "Ciste po deduplikacii: $($response.stats.afterDedupe)"
  Write-Host "Vyradene: $($response.stats.rejected)"
  Write-Host "Kvalita 80+: $($response.stats.quality80Plus)"
  Write-Host "Vysledok: $resultPath" -ForegroundColor Green

  Write-Host ""
  $response.preview |
    Select-Object -First 25 title, startDate, endDate, city, priceMin, freeEntry, qualityScore, parser |
    Format-Table -AutoSize

  if ($response.stats.rejected -gt 0) {
    Write-Host ""
    Write-Host "Dovody vyradenia:" -ForegroundColor Yellow
    $response.stats.rejectedReasons | Format-List
  }
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
