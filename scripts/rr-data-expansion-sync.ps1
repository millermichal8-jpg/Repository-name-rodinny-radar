param(
  [Parameter(Mandatory = $true)]
  [string[]]$Groups,
  [int]$MaxSourcesPerBatch = 3,
  [int]$MaxEventsPerSource = 60,
  [int]$Retries = 1,
  [switch]$ConfirmWrite
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not $ConfirmWrite) {
  throw "Ostry sync je zablokovany. Spusti ho znova s parametrom -ConfirmWrite az po kontrole preview reportu."
}

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

$stdout = ".\supabase\data-expansion-v1-sync.out.log"
$stderr = ".\supabase\data-expansion-v1-sync.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam lokalne Edge Functions"
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
$resultsDir = ".\supabase\test-results\data-expansion-v1\$timestamp-sync"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$rows = New-Object System.Collections.Generic.List[object]

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
      Step "OSTRY SYNC skupiny $group, offset $offset"
      $body = @{
        action = "sync"
        confirmWrite = $true
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

      $batchPath = Join-Path $resultsDir ("{0}-{1:D3}.json" -f $group, $offset)
      Write-Utf8NoBom $batchPath ($response | ConvertTo-Json -Depth 50)

      foreach ($run in @($response.runs)) {
        $rows.Add([PSCustomObject]@{
          Skupina = $group
          Zdroj = $run.sourceCode
          Stav = if ($run.ok) { "OK" } elseif ($run.warning) { "VAROVANIE" } else { "CHYBA" }
          TrvanieMs = $run.durationMs
          Chyba = $run.error
        }) | Out-Null
      }

      $remaining = [int]$response.remainingSourceCount
      $offset = [int]$response.nextSourceOffset
      if (@($response.runs).Count -eq 0) { break }
    }
  }

  $csvPath = Join-Path $resultsDir "sync-report.csv"
  $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
  Write-Host ""
  Write-Host "DATA EXPANSION V1 SYNC DOKONCENY" -ForegroundColor Green
  Write-Host "Report: $csvPath" -ForegroundColor Green
  $rows | Format-Table -AutoSize -Wrap
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
