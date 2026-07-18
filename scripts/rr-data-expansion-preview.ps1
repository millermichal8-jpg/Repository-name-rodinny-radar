param(
  [string[]]$Groups = @(
    "sk-ba", "sk-tt", "sk-tn", "sk-nr", "sk-za",
    "sk-bb", "sk-po", "sk-ke", "cz-wave1"
  ),
  [int]$MaxSourcesPerBatch = 4,
  [int]$MaxEventsPerSource = 80,
  [int]$Retries = 1,
  [switch]$FailOnConnectorError
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) {
  Write-Host ""
  Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

Step "Kontrolujem lokalny Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokalny Supabase nebezi. Najprv spusti: npx supabase start"
}

$envFile = ".\supabase\functions\.env.data-expansion.local"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
Write-Utf8NoBom $envFile "CATALOG_SYNC_TOKEN=local-dev-token`n"

$stdout = ".\supabase\data-expansion-v1-serve.out.log"
$stderr = ".\supabase\data-expansion-v1-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam lokalne Edge Functions V4 + orchestrator"
$process = Start-Process `
  -FilePath "cmd.exe" `
  -ArgumentList @(
    "/c",
    "npx supabase functions serve --no-verify-jwt --env-file supabase/functions/.env.data-expansion.local"
  ) `
  -PassThru `
  -WindowStyle Hidden `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultsDir = ".\supabase\test-results\data-expansion-v1\$timestamp-preview"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$allRows = New-Object System.Collections.Generic.List[object]
$batchFiles = New-Object System.Collections.Generic.List[string]

try {
  Start-Sleep -Seconds 16
  if ($process.HasExited) {
    $details = @()
    if (Test-Path $stdout) { $details += Get-Content $stdout -Raw }
    if (Test-Path $stderr) { $details += Get-Content $stderr -Raw }
    throw "Edge Functions sa nespustili.`n$($details -join "`n")"
  }

  foreach ($group in $Groups) {
    $offset = 0
    $remaining = 1
    while ($remaining -gt 0) {
      Step "Preview skupiny $group, offset $offset"
      $body = @{
        action = "preview"
        sourceGroup = $group
        sourceOffset = $offset
        maxSources = $MaxSourcesPerBatch
        maxEventsPerSource = $MaxEventsPerSource
        retries = $Retries
      } | ConvertTo-Json -Depth 8

      $response = Invoke-RestMethod `
        -Method Post `
        -Uri "http://127.0.0.1:54321/functions/v1/data-expansion-orchestrator" `
        -Headers @{
          "Content-Type" = "application/json"
          "X-Sync-Token" = "local-dev-token"
        } `
        -Body $body `
        -TimeoutSec 900

      if ($response.version -ne "data-expansion-orchestrator-v1") {
        throw "Nespustil sa Data Expansion orchestrator V1. Vratena verzia: $($response.version)"
      }

      $batchPath = Join-Path $resultsDir ("{0}-{1:D3}.json" -f $group, $offset)
      Write-Utf8NoBom $batchPath ($response | ConvertTo-Json -Depth 50)
      $batchFiles.Add($batchPath) | Out-Null

      foreach ($run in @($response.runs)) {
        $allRows.Add([PSCustomObject]@{
          Skupina = $group
          Zdroj = $run.sourceCode
          Nazov = $run.displayName
          Stav = if ($run.ok) { "OK" } elseif ($run.warning) { "VAROVANIE" } else { "CHYBA" }
          Pokusy = $run.attempts
          TrvanieMs = $run.durationMs
          Http = $run.httpStatus
          Chyba = $run.error
        }) | Out-Null
      }

      $remaining = [int]$response.remainingSourceCount
      $offset = [int]$response.nextSourceOffset
      if (@($response.runs).Count -eq 0) { break }
    }
  }

  $csvPath = Join-Path $resultsDir "source-report.csv"
  $allRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

  $summary = [PSCustomObject]@{
    GeneratedAt = (Get-Date).ToString("o")
    Action = "preview"
    Groups = $Groups
    TotalSources = $allRows.Count
    Ok = @($allRows | Where-Object { $_.Stav -eq "OK" }).Count
    Warnings = @($allRows | Where-Object { $_.Stav -eq "VAROVANIE" }).Count
    Failed = @($allRows | Where-Object { $_.Stav -eq "CHYBA" }).Count
    BatchFiles = $batchFiles
  }
  Write-Utf8NoBom (Join-Path $resultsDir "summary.json") ($summary | ConvertTo-Json -Depth 10)

  Write-Host ""
  Write-Host "DATA EXPANSION V1 PREVIEW DOKONCENY" -ForegroundColor Green
  Write-Host "OK: $($summary.Ok), varovania: $($summary.Warnings), chyby: $($summary.Failed)"
  Write-Host "Report: $csvPath" -ForegroundColor Green
  Write-Host "JSON vysledky: $resultsDir" -ForegroundColor Green
  Write-Host ""
  $allRows | Format-Table Skupina, Zdroj, Stav, TrvanieMs, Chyba -AutoSize -Wrap

  if ($FailOnConnectorError -and $summary.Failed -gt 0) {
    throw "Niektore zdroje zlyhali. Pozri source-report.csv."
  }
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
