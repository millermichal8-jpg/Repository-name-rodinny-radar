param(
  [string[]]$SourceCodes = @(
    "bb-events",
    "bojnice-events",
    "zvolen-events",
    "bs-kultura"
  ),
  [int]$MaxEvents = 60
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

$stdout = ".\supabase\municipal-v3-serve.out.log"
$stderr = ".\supabase\municipal-v3-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam municipal-event-sync V3 lokalne"
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
  Start-Sleep -Seconds 14

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

  Step "Spustam produkcne prisny preview V3"
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body $body `
    -TimeoutSec 300

  if ($response.version -ne "municipal-parser-v3") {
    throw "Nespustila sa V3 funkcia. Vratena verzia: $($response.version)"
  }

  if ([int]$response.stats.afterDedupe -lt 1) {
    throw "V3 nenasla ziadne pouzitelne podujatie. Test sa nepovazuje za uspesny."
  }

  $forbidden = @(
    "Mapa stránok",
    "Všeobecné obchodné podmienky",
    "Zostaň informovaný o našich novinkách",
    "Organizačné zaradenie",
    "Referencie",
    "Pomocník",
    "Kontakty",
    "Prihlasovanie na Univerzitu tretieho veku je spustené"
  )

  $badTitles = @($response.preview | Where-Object { $forbidden -contains $_.title })
  if ($badTitles.Count -gt 0) {
    throw "V3 prepustila navigacny obsah: $($badTitles.title -join ', ')"
  }

  $now = [DateTimeOffset]::Now
  $past = @($response.preview | Where-Object {
    $effectiveEnd = if ($_.endDate) { [DateTimeOffset]$_.endDate } else { [DateTimeOffset]$_.startDate }
    $effectiveEnd -lt $now.AddHours(-6)
  })
  if ($past.Count -gt 0) {
    throw "V3 prepustila ukoncene podujatia: $($past.title -join ', ')"
  }

  $resultsDir = ".\supabase\test-results"
  New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
  $resultPath = Join-Path $resultsDir "municipal-preview-v3.json"
  $json = $response | ConvertTo-Json -Depth 40
  [System.IO.File]::WriteAllText($resultPath, $json, $utf8NoBom)

  Write-Host ""
  Write-Host "MUNICIPAL V3 PREVIEW PRESIEL" -ForegroundColor Green
  Write-Host "Zdroje: $($response.stats.sourceCount)"
  Write-Host "Prijate pred deduplikaciou: $($response.stats.acceptedBeforeDedupe)"
  Write-Host "Ciste po deduplikacii: $($response.stats.afterDedupe)"
  Write-Host "Odstranene duplicity: $($response.stats.duplicatesRemoved)"
  Write-Host "Vyradene: $($response.stats.rejected)"
  Write-Host "Kvalita 80+: $($response.stats.quality80Plus)"
  Write-Host "Vysledok: $resultPath" -ForegroundColor Green

  Write-Host ""
  $rows = $response.preview | ForEach-Object {
    $start = [DateTimeOffset]$_.startDate
    $end = if ($_.endDate) { [DateTimeOffset]$_.endDate } else { $null }
    [PSCustomObject]@{
      Datum = $start.ToLocalTime().ToString("dd.MM.yyyy HH:mm")
      Do = if ($end) { $end.ToLocalTime().ToString("dd.MM.yyyy HH:mm") } else { "" }
      Mesto = $_.city
      Nazov = $_.title
      Cena = if ($_.freeEntry) { "zdarma" } elseif ($null -ne $_.priceMin) { "$($_.priceMin) EUR" } else { "nezistena" }
      Kvalita = $_.qualityScore
      Parser = $_.parser
    }
  }
  $rows | Format-Table -AutoSize -Wrap

  Write-Host ""
  Write-Host "Statistiky zdrojov:" -ForegroundColor Cyan
  foreach ($property in $response.sources.PSObject.Properties) {
    $value = $property.Value
    Write-Host ("{0}: adapter={1}, odkazy={2}, kandidati={3}, prijate={4}, vyradene={5}, chyby={6}" -f `
      $property.Name,
      $value.adapter,
      $value.discoveredLinks,
      $value.parsedCandidates,
      $value.accepted,
      $value.rejected,
      @($value.errors).Count)
  }
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
