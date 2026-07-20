param(
  [int]$MaxEvents = 180
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) {
  Write-Host ""
  Write-Host "==> $Text" -ForegroundColor Cyan
}

function Normalize-SearchText([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
  $builder = New-Object System.Text.StringBuilder
  foreach ($character in $normalized.ToCharArray()) {
    $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
    if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$builder.Append($character)
    }
  }
  return $builder.ToString().ToLowerInvariant().Trim()
}

function Get-SourceStats($Response, [string]$Code) {
  $property = $Response.sources.PSObject.Properties[$Code]
  if (-not $property) {
    throw "Preview neobsahuje zdroj $Code."
  }
  return $property.Value
}

Set-Location (Split-Path $PSScriptRoot -Parent)

$expectedBranch = "wip/trnava-trencin-adapter-v1"
if ((git branch --show-current).Trim() -ne $expectedBranch) {
  throw "Očakávaná vetva je $expectedBranch."
}

Step "Kontrola TypeScriptu aplikácie"
npx tsc --noEmit
if ($LASTEXITCODE -ne 0) {
  throw "TypeScript kontrola aplikácie zlyhala."
}

git diff --check
if ($LASTEXITCODE -ne 0) {
  throw "Git kontrola súborov zlyhala."
}

Step "Kontrola lokálneho Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokálny Supabase nebeží. Spusti npx supabase start."
}

Step "Aplikujem migrácie iba do lokálnej databázy"
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
npx supabase db reset
$resetCode = $LASTEXITCODE
$ErrorActionPreference = $oldPreference
if ($resetCode -ne 0) {
  throw "Lokálny databázový reset zlyhal. Produkcia sa nemenila."
}

$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $envFile,
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  $utf8NoBom
)

$stdout = ".\supabase\trnava-trencin-adapter-v1-serve.out.log"
$stderr = ".\supabase\trnava-trencin-adapter-v1-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spúšťam municipal-event-sync lokálne"
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
  Start-Sleep -Seconds 15

  if ($process.HasExited) {
    $details = @()
    if (Test-Path $stdout) { $details += Get-Content $stdout -Raw }
    if (Test-Path $stderr) { $details += Get-Content $stderr -Raw }
    throw "Edge Function sa nespustila.`n$($details -join "`n")"
  }

  $body = @{
    action = "preview"
    sourceCodes = @(
      "trnava-city-events",
      "trnava-kultura-events",
      "visit-trencin-events"
    )
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 6

  Step "Spúšťam Trnava + Trenčín preview bez zápisu"
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body $body `
    -TimeoutSec 360

  if ($response.version -ne "municipal-parser-v6") {
    throw "Beží nesprávna verzia parsera: $($response.version)"
  }

  $cityStats = Get-SourceStats $response "trnava-city-events"
  $cultureStats = Get-SourceStats $response "trnava-kultura-events"
  $trencinStats = Get-SourceStats $response "visit-trencin-events"

  if ([int]$cityStats.discoveredLinks -lt 5 -or [int]$cityStats.accepted -lt 3) {
    throw "Trnava mesto má slabý výsledok: odkazy=$($cityStats.discoveredLinks), prijaté=$($cityStats.accepted)"
  }
  if ([int]$cultureStats.discoveredLinks -lt 5 -or [int]$cultureStats.accepted -lt 4) {
    throw "Kultúra Trnava má slabý výsledok: odkazy=$($cultureStats.discoveredLinks), prijaté=$($cultureStats.accepted)"
  }
  if ([int]$trencinStats.discoveredLinks -lt 1 -or [int]$trencinStats.accepted -lt 1) {
    throw "Visit Trenčín má slabý výsledok: odkazy=$($trencinStats.discoveredLinks), prijaté=$($trencinStats.accepted)"
  }

  foreach ($stats in @($cityStats, $cultureStats, $trencinStats)) {
    if (@($stats.errors).Count -gt 0) {
      throw "Jeden zo zdrojov obsahuje chybu detailu."
    }
  }

  $items = @($response.preview)
  if ($items.Count -lt 8) {
    throw "Spoločný preview vrátil málo položiek: $($items.Count)"
  }

  $motyle = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "fantasticke motyle – vystava" -or
    (Normalize-SearchText $_.title) -eq "fantasticke motyle - vystava"
  } | Select-Object -First 1

  $kinematograf = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "kinematograf 2026"
  } | Select-Object -First 1

  $divadielka = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "divadielka pod vezou 2026"
  } | Select-Object -First 1

  foreach ($required in @($motyle, $kinematograf, $divadielka)) {
    if (-not $required) {
      throw "Chýba jedno z troch kontrolných podujatí."
    }
  }

  if ($motyle.raw.parser -ne "trnava-city-detail-v1") {
    throw "Fantastické motýle nepoužili Trnava city parser."
  }
  if ($kinematograf.raw.parser -ne "trnava-kultura-detail-v1") {
    throw "Kinematograf nepoužil Kultúra Trnava parser."
  }
  if ($divadielka.raw.parser -ne "visit-trencin-query-detail-v1") {
    throw "Divadielka nepoužili Visit Trenčín parser."
  }

  $motyleEnd = [DateTimeOffset]$motyle.endDate
  if ($motyleEnd.Month -ne 10 -or $motyleEnd.Day -ne 12 -or $motyleEnd.Hour -ne 23) {
    throw "Fantastické motýle majú nesprávny koniec: $($motyle.endDate)"
  }

  $kinoStart = [DateTimeOffset]$kinematograf.startDate
  $kinoEnd = [DateTimeOffset]$kinematograf.endDate
  if (
    $kinoStart.Month -ne 8 -or
    $kinoStart.Day -ne 13 -or
    $kinoStart.Hour -ne 20 -or
    $kinoStart.Minute -ne 30 -or
    $kinoEnd.Day -ne 15
  ) {
    throw "Kinematograf má nesprávny termín: $($kinematograf.startDate) až $($kinematograf.endDate)"
  }

  $divadielkaStart = [DateTimeOffset]$divadielka.startDate
  $divadielkaEnd = [DateTimeOffset]$divadielka.endDate
  if (
    $divadielkaStart.Hour -ne 17 -or
    $divadielkaEnd.Month -ne 8 -or
    $divadielkaEnd.Day -ne 30
  ) {
    throw "Divadielka majú nesprávny termín: $($divadielka.startDate) až $($divadielka.endDate)"
  }

  $wrongTimezone = @($items | Where-Object {
    $_.startDate -and ([string]$_.startDate -notmatch "[+-]0[12]:00$")
  })
  if ($wrongTimezone.Count -gt 0) {
    throw "Niektorá položka nemá slovenské časové pásmo: $($wrongTimezone[0].startDate)"
  }

  $resultDir = ".\supabase\test-results\trnava-trencin-adapter-v1"
  New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
  $resultPath = Join-Path $resultDir "preview.json"
  [System.IO.File]::WriteAllText(
    $resultPath,
    ($response | ConvertTo-Json -Depth 60),
    $utf8NoBom
  )

  Write-Host ""
  Write-Host "TRNAVA + TRENČÍN ADAPTER V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
  Write-Host "Trnava mesto: odkazy=$($cityStats.discoveredLinks), prijaté=$($cityStats.accepted)"
  Write-Host "Kultúra Trnava: odkazy=$($cultureStats.discoveredLinks), prijaté=$($cultureStats.accepted)"
  Write-Host "Visit Trenčín: odkazy=$($trencinStats.discoveredLinks), prijaté=$($trencinStats.accepted)"
  Write-Host "Fantastické motýle: $($motyle.startDate) až $($motyle.endDate)"
  Write-Host "Kinematograf: $($kinematograf.startDate) až $($kinematograf.endDate)"
  Write-Host "Divadielka: $($divadielka.startDate) až $($divadielka.endDate)"
  Write-Host "Preview nič nezapísal." -ForegroundColor Green
  Write-Host "Výsledok: $resultPath" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
