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
    throw "Preview does not contain source $Code."
  }
  return $property.Value
}

Set-Location (Split-Path $PSScriptRoot -Parent)

$expectedBranch = "wip/zilina-adapter-v1"
if ((git branch --show-current).Trim() -ne $expectedBranch) {
  throw "Expected branch is $expectedBranch."
}

Step "TypeScript check"
npx tsc --noEmit
if ($LASTEXITCODE -ne 0) {
  throw "TypeScript check failed."
}

git diff --check
if ($LASTEXITCODE -ne 0) {
  throw "Git file check failed."
}

Step "Local Supabase check"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Local Supabase is not running."
}

if ($env:RR_ZILINA_SKIP_DB_RESET -eq "1") {
  Step "Use already reset local database"
} else {
  Step "Apply migrations only to local database"

  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"

  npx supabase db reset

  $resetCode = $LASTEXITCODE
  $ErrorActionPreference = $oldPreference

  if ($resetCode -ne 0) {
    throw "Local database reset failed. Production was not changed."
  }
}
$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(
  $envFile,
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  $utf8NoBom
)

$stdout = ".\supabase\zilina-adapter-v1-serve.out.log"
$stderr = ".\supabase\zilina-adapter-v1-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

Step "Start municipal-event-sync locally"
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
    throw "Edge Function did not start.`n$($details -join "`n")"
  }

  $body = @{
    action = "preview"
    sourceCodes = @("zilina-events")
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 6

  Step "Run Zilina preview without writes"
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
    throw "Wrong parser version: $($response.version)"
  }

  $stats = Get-SourceStats $response "zilina-events"

  if ([int]$stats.discoveredLinks -lt 50) {
    throw "Zilina API returned too few records: $($stats.discoveredLinks)"
  }

  if ([int]$stats.accepted -lt 4) {
    throw "Zilina accepted too few current events: $($stats.accepted)"
  }

  if (@($stats.errors).Count -gt 0) {
    throw "Zilina preview contains source errors."
  }

  $items = @(
    $response.preview |
    Where-Object { $_.sourcePageCode -eq "zilina-events" }
  )

  if ($items.Count -lt 4) {
    throw "Zilina preview returned too few items: $($items.Count)"
  }

  $wrongParser = @(
    $items |
    Where-Object {
      -not $_.raw -or
      $_.raw.parser -ne "zilina-wordpress-api-v1"
    }
  )

  if ($wrongParser.Count -gt 0) {
    throw "Some Zilina items did not use the API adapter."
  }

  $badUrls = @(
    $items |
    Where-Object {
      [string]$_.sourceUrl -notmatch "^https://zilina\.sk/podujatie/[^/?#]+/?$"
    }
  )

  if ($badUrls.Count -gt 0) {
    throw "Zilina preview contains an invalid event URL."
  }

  $wrongTimezone = @(
    $items |
    Where-Object {
      $_.startDate -and
      ([string]$_.startDate -notmatch "[+-]0[12]:00$")
    }
  )

  if ($wrongTimezone.Count -gt 0) {
    throw "Some Zilina events do not use Slovakia timezone."
  }

  $withImage = @(
    $items |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.imageUrl) }
  )

  if ($withImage.Count -lt 4) {
    throw "Zilina returned too few images."
  }

  $missingPlace = @(
    $items |
    Where-Object {
      [string]::IsNullOrWhiteSpace([string]$_.city) -and
      [string]::IsNullOrWhiteSpace([string]$_.venueName) -and
      [string]::IsNullOrWhiteSpace([string]$_.address)
    }
  )

  if ($missingPlace.Count -gt 0) {
    throw "Some Zilina events have no place."
  }

  $resultDir = ".\supabase\test-results\zilina-adapter-v1"
  New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
  $resultPath = Join-Path $resultDir "preview.json"
  [System.IO.File]::WriteAllText(
    $resultPath,
    ($response | ConvertTo-Json -Depth 60),
    $utf8NoBom
  )

  Write-Host ""
  Write-Host "ZILINA ADAPTER V1 LOCAL TEST PASSED." -ForegroundColor Green
  Write-Host "API records: $($stats.discoveredLinks)"
  Write-Host "Accepted current events: $($stats.accepted)"
  Write-Host "Events with image: $($withImage.Count)"
  Write-Host "Preview wrote nothing." -ForegroundColor Green
  Write-Host "Result: $resultPath" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
