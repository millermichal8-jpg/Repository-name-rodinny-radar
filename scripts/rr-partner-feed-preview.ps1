param(
  [ValidateSet('goout','predpredaj','ticketportal','ticketlive','eventim')]
  [string]$Provider = 'predpredaj',
  [string]$FunctionBaseUrl = 'http://127.0.0.1:54321/functions/v1',
  [string]$FixturePath = '.\scripts\fixtures\partner-feed-sample.json'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $FixturePath)) {
  throw "Fixture sa nenašla: $FixturePath"
}

$tokenFile = '.\.rr-backups\secrets\catalog-sync-token.dpapi'
if (-not (Test-Path $tokenFile)) {
  throw 'Nenašiel sa bezpečne uložený CATALOG_SYNC_TOKEN.'
}

$encryptedToken = (Get-Content $tokenFile -Raw).Trim()
$secureToken = ConvertTo-SecureString -String $encryptedToken
$credential = [System.Management.Automation.PSCredential]::new('sync', $secureToken)
$syncToken = $credential.GetNetworkCredential().Password

$fixture = Get-Content $FixturePath -Raw | ConvertFrom-Json
$body = @{
  action = 'preview'
  provider = $Provider
  maxEvents = 50
  events = @($fixture.events)
} | ConvertTo-Json -Depth 30

$response = Invoke-RestMethod `
  -Method Post `
  -Uri "$FunctionBaseUrl/partner-ticket-sync" `
  -Headers @{
    'Content-Type' = 'application/json'
    'X-Sync-Token' = $syncToken
  } `
  -Body $body `
  -TimeoutSec 180

Write-Host "`n--- PARTNER FEED PREVIEW ---" -ForegroundColor Cyan
Write-Host "Provider: $($response.providerName)"
Write-Host "Načítané: $($response.fetched)"
Write-Host "Prijaté: $($response.accepted)" -ForegroundColor Green
Write-Host "Odmietnuté: $($response.rejected)" -ForegroundColor Yellow
Write-Host "Varovania: $($response.warnings)" -ForegroundColor Yellow
Write-Host "Ostrý sync povolený: $($response.canSync)"

$response.issues | Format-Table index, severity, code, message -AutoSize -Wrap
$response.sample | Select-Object externalId, title, city, startDate, priceMin, currency, qualityScore | Format-Table -AutoSize -Wrap

$syncToken = $null
$credential = $null
$secureToken = $null
$encryptedToken = $null
