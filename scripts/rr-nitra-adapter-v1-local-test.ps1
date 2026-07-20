param(
  [int]$MaxEvents = 100
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Step([string]$Text) {
  Write-Host ""
  Write-Host "==> $Text" -ForegroundColor Cyan
}

function Get-SourceStats($Response, [string]$Code) {
  $property = $Response.sources.PSObject.Properties[$Code]
  if (-not $property) {
    throw "Preview neobsahuje zdroj $Code."
  }
  return $property.Value
}

Set-Location (Split-Path $PSScriptRoot -Parent)

$expectedBranch = "wip/nitra-zilina-tvrdosin-adapter-v1"
if ((git branch --show-current).Trim() -ne $expectedBranch) {
  throw "Ocakavana vetva je $expectedBranch."
}

Step "Kontrola TypeScriptu aplikacie"
npx tsc --noEmit
if ($LASTEXITCODE -ne 0) {
  throw "TypeScript kontrola aplikacie zlyhala."
}

git diff --check
if ($LASTEXITCODE -ne 0) {
  throw "Git kontrola suborov zlyhala."
}

Step "Kontrola lokalneho Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokalny Supabase nebezi. Spusti npx supabase start."
}

Step "Aplikujem migracie iba do lokalnej databazy"
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
npx supabase db reset
$resetCode = $LASTEXITCODE
$ErrorActionPreference = $oldPreference
if ($resetCode -ne 0) {
  throw "Lokalny databazovy reset zlyhal. Produkcia sa nemenila."
}

$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $envFile,
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  $utf8NoBom
)

$stdout = ".\supabase\nitra-adapter-v1-serve.out.log"
$stderr = ".\supabase\nitra-adapter-v1-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Spustam municipal-event-sync lokalne"
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
    sourceCodes = @("nitra-city-events")
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 6

  Step "Spustam Nitra preview bez zapisu"
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
    throw "Bezi nespravna verzia parsera: $($response.version)"
  }

  $stats = Get-SourceStats $response "nitra-city-events"

  if ([int]$stats.discoveredLinks -lt 10) {
    throw "Nitra nasla malo detailnych odkazov: $($stats.discoveredLinks)"
  }

  if ([int]$stats.accepted -lt 8) {
    throw "Nitra prijala malo udalosti: $($stats.accepted)"
  }

  if (@($stats.errors).Count -gt 0) {
    throw "Nitra preview obsahuje chyby detailov."
  }

  $items = @(
    $response.preview |
    Where-Object { $_.sourcePageCode -eq "nitra-city-events" }
  )

  if ($items.Count -lt 8) {
    throw "Nitra preview vratil malo poloziek: $($items.Count)"
  }

  $wrongParser = @(
    $items |
    Where-Object {
      -not $_.raw -or
      $_.raw.parser -ne "nitra-calendar-card-v1"
    }
  )

  if ($wrongParser.Count -gt 0) {
    throw "Niektora Nitra polozka nepouzila novy parser."
  }

  $timedItems = @(
    $items |
    Where-Object { $_.allDay -eq $false }
  )

  if ($timedItems.Count -lt 3) {
    throw "Nitra vratila malo udalosti s presnym casom."
  }

  $withImage = @(
    $items |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.imageUrl) }
  )

  if ($withImage.Count -lt 3) {
    throw "Nitra vratila malo udalosti s obrazkom."
  }

  $withVenue = @(
    $items |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.venueName) }
  )

  if ($withVenue.Count -lt 5) {
    throw "Nitra vratila malo udalosti s miestom."
  }

  $wrongTimezone = @(
    $items |
    Where-Object {
      $_.startDate -and
      ([string]$_.startDate -notmatch "[+-]0[12]:00$")
    }
  )

  if ($wrongTimezone.Count -gt 0) {
    throw "Niektora Nitra polozka nema slovenske casove pasmo."
  }

  $badUrls = @(
    $items |
    Where-Object {
      [string]$_.sourceUrl -notmatch "^https://www\.nitra\.eu/kalendar/[0-9]+/[^/?#]+/?$"
    }
  )

  if ($badUrls.Count -gt 0) {
    throw "Nitra preview obsahuje neplatnu detailnu URL."
  }

  $resultDir = ".\supabase\test-results\nitra-adapter-v1"
  New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
  $resultPath = Join-Path $resultDir "preview.json"
  [System.IO.File]::WriteAllText(
    $resultPath,
    ($response | ConvertTo-Json -Depth 60),
    $utf8NoBom
  )

  Write-Host ""
  Write-Host "NITRA ADAPTER V1 LOKALNY TEST PRESIEL." -ForegroundColor Green
  Write-Host "Najdene odkazy: $($stats.discoveredLinks)"
  Write-Host "Prijate udalosti: $($stats.accepted)"
  Write-Host "Udalosti s casom: $($timedItems.Count)"
  Write-Host "Udalosti s obrazkom: $($withImage.Count)"
  Write-Host "Udalosti s miestom: $($withVenue.Count)"
  Write-Host "Preview nic nezapisal." -ForegroundColor Green
  Write-Host "Vysledok: $resultPath" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
