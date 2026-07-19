param(
  [string]$ProjectPath = "$HOME\Desktop\rodinny-radar"
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Set-Location $ProjectPath

Write-Host "`n--- PRAHA 12 DATE FIX V1: LOKÁLNY PREVIEW ---" -ForegroundColor Cyan

$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
[System.IO.File]::WriteAllText(
  (Resolve-Path (Split-Path $envFile -Parent)).Path + "\.env",
  "CATALOG_SYNC_TOKEN=local-dev-token`n",
  (New-Object System.Text.UTF8Encoding($false))
)

$stdout = ".\supabase\praha12-date-fix-serve.out.log"
$stderr = ".\supabase\praha12-date-fix-serve.err.log"
Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

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
    throw "Lokálna Edge Function sa nespustila.`n$($details -join "`n")"
  }

  $body = @{
    action = "preview"
    sourceCodes = @("praha12-events")
    maxEvents = 200
  } | ConvertTo-Json -Depth 6

  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json; charset=utf-8"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
    -TimeoutSec 300

  $items = @($response.preview)

  $krtiny = $items | Where-Object {
    $_.title -eq "Letní kino: Přání k narozeninám: Křtiny"
  } | Select-Object -First 1

  $svihaci = $items | Where-Object {
    $_.title -eq "Letní kino: Šviháci"
  } | Select-Object -First 1

  $vystava = $items | Where-Object {
    $_.title -like "Výstava fotografií: Eva Vokatá*"
  } | Select-Object -First 1

  if (-not $krtiny) { throw "Chýba testovacie podujatie Křtiny." }
  if (-not $svihaci) { throw "Chýba testovacie podujatie Šviháci." }
  if (-not $vystava) { throw "Chýba testovacia výstava Eva Vokatá." }

  $krtinyStart = [DateTimeOffset]$krtiny.startDate
  $svihaciStart = [DateTimeOffset]$svihaci.startDate
  $vystavaStart = [DateTimeOffset]$vystava.startDate
  $vystavaEnd = [DateTimeOffset]$vystava.endDate

  if ($krtinyStart.Hour -ne 21 -or $krtinyStart.Minute -ne 30 -or $krtiny.allDay) {
    throw "Křtiny majú zlý čas alebo allDay: $($krtiny.startDate), allDay=$($krtiny.allDay)"
  }

  if ($svihaciStart.Hour -ne 21 -or $svihaciStart.Minute -ne 15 -or $svihaci.allDay) {
    throw "Šviháci majú zlý čas alebo allDay: $($svihaci.startDate), allDay=$($svihaci.allDay)"
  }

  if (
    $vystavaStart.Day -ne 1 -or
    $vystavaStart.Month -ne 8 -or
    $vystavaEnd.Day -ne 31 -or
    $vystavaEnd.Month -ne 8
  ) {
    throw "Výstava má zlý rozsah: $($vystava.startDate) až $($vystava.endDate)"
  }

  $generic = @($items | Where-Object {
    $_.title -in @("Kulturní akce, zábava", "Ostatní akce", "Ostatni akce")
  })

  if ($generic.Count -gt 0) {
    throw "Preview prepustilo generické názvy."
  }

  $reportDir = ".\supabase\test-results\praha12-date-fix-v1"
  New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

  $response |
    ConvertTo-Json -Depth 50 |
    Set-Content (Join-Path $reportDir "preview.json") -Encoding UTF8

  Write-Host ""
  Write-Host "PRAHA 12 DATE FIX V1 LOKÁLNY TEST PREŠIEL." -ForegroundColor Green
  Write-Host "Křtiny: $($krtiny.startDate), allDay=$($krtiny.allDay)" -ForegroundColor Green
  Write-Host "Šviháci: $($svihaci.startDate), allDay=$($svihaci.allDay)" -ForegroundColor Green
  Write-Host "Výstava: $($vystava.startDate) až $($vystava.endDate)" -ForegroundColor Green
  Write-Host "Generické názvy: 0" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
