param(
  [int]$MaxEvents = 80
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
  return $builder.ToString().ToLowerInvariant()
}

Set-Location (Split-Path $PSScriptRoot -Parent)

Step "Kontrola lokalneho Supabase"
npx supabase status | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Lokalny Supabase nebezi. Spusti npx supabase start."
}

$envFile = ".\supabase\functions\.env"
New-Item -ItemType Directory -Path (Split-Path $envFile -Parent) -Force | Out-Null
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($envFile, "CATALOG_SYNC_TOKEN=local-dev-token`n", $utf8NoBom)

$stdout = ".\supabase\bb-adapter-v1-serve.out.log"
$stderr = ".\supabase\bb-adapter-v1-serve.err.log"
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
  Start-Sleep -Seconds 14

  if ($process.HasExited) {
    $details = @()
    if (Test-Path $stdout) { $details += Get-Content $stdout -Raw }
    if (Test-Path $stderr) { $details += Get-Content $stderr -Raw }
    throw "Edge Function sa nespustila.`n$($details -join "`n")"
  }

  $body = @{
    action = "preview"
    sourceCodes = @("bb-events")
    maxEvents = $MaxEvents
  } | ConvertTo-Json -Depth 5

  Step "Spustam BB preview bez zapisu"
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "http://127.0.0.1:54321/functions/v1/municipal-event-sync" `
    -Headers @{
      "Content-Type" = "application/json"
      "X-Sync-Token" = "local-dev-token"
    } `
    -Body $body `
    -TimeoutSec 300

  $sourceProperty = $response.sources.PSObject.Properties["bb-events"]
  if (-not $sourceProperty) {
    throw "Preview neobsahuje zdroj bb-events."
  }

  $stats = $sourceProperty.Value
  if ([int]$stats.accepted -lt 8) {
    throw "BB adapter prijal prilis malo podujati: $($stats.accepted)"
  }

  $items = @($response.preview | Where-Object { $_.sourcePageCode -eq "bb-events" })
  if ($items.Count -lt 8) {
    throw "Preview vratil prilis malo BB poloziek: $($items.Count)"
  }

  $halusky = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "halusky fest turecka"
  } | Select-Object -First 1

  $meteority = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "ako sa hladaju meteority"
  } | Select-Object -First 1

  $joga = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "joga v parku"
  } | Select-Object -First 1

  $kostoly = $items | Where-Object {
    (Normalize-SearchText $_.title) -eq "komentovane prehliadky kostolov"
  } | Select-Object -First 1

  foreach ($required in @($halusky, $meteority, $joga, $kostoly)) {
    if (-not $required) {
      throw "Chyba jedno z kontrolnych podujati BB."
    }
  }

  if (-not $halusky.endDate -or ([DateTimeOffset]$halusky.endDate).Hour -ne 23) {
    throw "Halusky nemaju spravny koniec: $($halusky.endDate)"
  }

  if (-not $meteority.endDate -or ([DateTimeOffset]$meteority.endDate).Hour -ne 18) {
    throw "Meteority nemaju spravny koniec: $($meteority.endDate)"
  }

  if (-not $joga.endDate -or ([DateTimeOffset]$joga.endDate).Hour -ne 19) {
    throw "Joga nema spravny koniec: $($joga.endDate)"
  }

  if ([bool]$kostoly.freeEntry -or [decimal]$kostoly.priceMin -ne 4) {
    throw "Kostoly maju nespravnu cenu: free=$($kostoly.freeEntry), min=$($kostoly.priceMin)"
  }

  $badVenue = @($items | Where-Object {
    $_.venueName -and (
      ([string]$_.venueName).Length -gt 180 -or
      (Normalize-SearchText $_.venueName) -match "musim mat|co si priniest|co ak bude"
    )
  })
  if ($badVenue.Count -gt 0) {
    throw "BB adapter vratil poskodene miesto: $($badVenue[0].venueName)"
  }

  $badTimezone = @($items | Where-Object {
    $_.startDate -and ([string]$_.startDate -notmatch "[+-]0[12]:00$")
  })
  if ($badTimezone.Count -gt 0) {
    throw "BB adapter nevratil Bratislava offset: $($badTimezone[0].startDate)"
  }

  $wrongParser = @($items | Where-Object {
    -not $_.raw -or $_.raw.parser -ne "bb-citio-detail-v1"
  })
  if ($wrongParser.Count -gt 0) {
    throw "Niektore BB polozky nepouzili bb-citio-detail-v1."
  }

  $resultDir = ".\supabase\test-results\bb-adapter-v1"
  New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
  $resultPath = Join-Path $resultDir "preview.json"
  [System.IO.File]::WriteAllText(
    $resultPath,
    ($response | ConvertTo-Json -Depth 50),
    $utf8NoBom
  )

  Write-Host ""
  Write-Host "BB DETAIL ADAPTER V1 LOKALNY TEST PRESIEL." -ForegroundColor Green
  Write-Host "Najdene odkazy: $($stats.discoveredLinks)"
  Write-Host "Prijate: $($stats.accepted)"
  Write-Host "Vyradene: $($stats.rejected)"
  Write-Host "Chyby: $(@($stats.errors).Count)"
  Write-Host "Halusky: $($halusky.startDate) az $($halusky.endDate)"
  Write-Host "Meteority: $($meteority.startDate) az $($meteority.endDate)"
  Write-Host "Joga: $($joga.startDate) az $($joga.endDate)"
  Write-Host "Kostoly: $($kostoly.priceMin) EUR, free=$($kostoly.freeEntry)"
  Write-Host "Vysledok: $resultPath" -ForegroundColor Green
}
finally {
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
}
