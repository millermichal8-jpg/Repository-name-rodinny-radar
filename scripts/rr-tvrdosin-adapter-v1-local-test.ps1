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

$expectedBranch = "wip/tvrdosin-adapter-v1"
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

if ($env:RR_TVRDOSIN_SKIP_DB_RESET -eq "1") {
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

$stdout = ".\supabase\tvrdosin-adapter-v1-serve.out.log"
$stderr = ".\supabase\tvrdosin-adapter-v1-serve.err.log"
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
    sourceCodes = @("tvrdosin-events")
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 6

  Step "Run Tvrdosin preview without writes"
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

  $stats = Get-SourceStats $response "tvrdosin-events"

  if ([int]$stats.discoveredLinks -ne 44) {
    throw "Tvrdosin snapshot does not contain 44 configured events: $($stats.discoveredLinks)"
  }

  if ([int]$stats.accepted -lt 40) {
    throw "Tvrdosin accepted too few current events: $($stats.accepted)"
  }

  if (@($stats.errors).Count -gt 0) {
    throw "Tvrdosin preview contains source errors."
  }

  $items = @(
    $response.preview |
    Where-Object { $_.sourcePageCode -eq "tvrdosin-events" }
  )

  if ($items.Count -ne [int]$stats.accepted) {
    throw "Preview item count does not match source statistics."
  }

  $wrongParser = @(
    $items |
    Where-Object {
      -not $_.raw -or
      $_.raw.parser -ne "tvrdosin-official-pdf-snapshot-v1"
    }
  )

  if ($wrongParser.Count -gt 0) {
    throw "Some Tvrdosin items did not use the PDF snapshot adapter."
  }

  $badUrls = @(
    $items |
    Where-Object {
      [string]$_.sourceUrl -notmatch "^https://www\.tvrdosin\.sk/e_download\.php\?.+#page=[0-9]+&event="
    }
  )

  if ($badUrls.Count -gt 0) {
    throw "Tvrdosin preview contains an invalid PDF source URL."
  }

  $wrongTimezone = @(
    $items |
    Where-Object {
      $_.startDate -and
      ([string]$_.startDate -notmatch "[+-]0[12]:00$")
    }
  )

  if ($wrongTimezone.Count -gt 0) {
    throw "Some Tvrdosin events do not use Slovakia timezone."
  }

  $missingData = @(
    $items |
    Where-Object {
      [string]::IsNullOrWhiteSpace([string]$_.title) -or
      [string]::IsNullOrWhiteSpace([string]$_.startDate) -or
      (
        [string]::IsNullOrWhiteSpace([string]$_.city) -and
        [string]::IsNullOrWhiteSpace([string]$_.venueName) -and
        [string]::IsNullOrWhiteSpace([string]$_.address)
      )
    }
  )

  if ($missingData.Count -gt 0) {
    throw "Some Tvrdosin events are missing title, date or place."
  }

  foreach ($requiredTitle in @(
    "Folklórne slávnosti pod Osobitou a jarmok ľudových remesiel",
    "Dni mesta",
    "Michalský jarmok",
    "Silvester 2026"
  )) {
    if (-not ($items | Where-Object { [string]$_.title -eq $requiredTitle })) {
      throw "Required Tvrdosin event is missing: $requiredTitle"
    }
  }

  if ($response.PSObject.Properties["synced"]) {
    throw "Preview unexpectedly contains synced rows."
  }

  $resultDir = ".\supabase\test-results\tvrdosin-adapter-v1"
  New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
  $resultPath = Join-Path $resultDir "preview.json"
  [System.IO.File]::WriteAllText(
    $resultPath,
    ($response | ConvertTo-Json -Depth 80),
    $utf8NoBom
  )

  $timedItems = @($items | Where-Object { $_.allDay -eq $false })

  Write-Host ""
  Write-Host "TVRDOSIN ADAPTER V1 LOCAL TEST PASSED." -ForegroundColor Green
  Write-Host "Configured PDF events: $($stats.discoveredLinks)"
  Write-Host "Accepted current events: $($stats.accepted)"
  Write-Host "Events with explicit time: $($timedItems.Count)"
  Write-Host "Preview wrote nothing." -ForegroundColor Green
  Write-Host "Result: $resultPath" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
