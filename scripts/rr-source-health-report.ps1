param(
  [string]$BaseUrl = "http://127.0.0.1:54321",
  [string]$ServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY,
  [string]$OutputDirectory = ".\supabase\test-results\data-expansion-v1\health"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Set-Location (Split-Path $PSScriptRoot -Parent)

if ([string]::IsNullOrWhiteSpace($ServiceRoleKey)) {
  throw "Nastav SUPABASE_SERVICE_ROLE_KEY iba v aktualnom terminali alebo ho odovzdaj parametrom. Neukladaj ho do Gitu."
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$headers = @{
  apikey = $ServiceRoleKey
  Authorization = "Bearer $ServiceRoleKey"
  "Content-Type" = "application/json"
}

$response = Invoke-RestMethod `
  -Method Post `
  -Uri "$($BaseUrl.TrimEnd('/'))/rest/v1/rpc/catalog_source_health_report_v1" `
  -Headers $headers `
  -Body "{}" `
  -TimeoutSec 120

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csv = Join-Path $OutputDirectory "$timestamp-source-health.csv"
$json = Join-Path $OutputDirectory "$timestamp-source-health.json"
$response | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
$response | ConvertTo-Json -Depth 20 | Set-Content -Path $json -Encoding UTF8

Write-Host "Source health report: $csv" -ForegroundColor Green
$response | Format-Table group_code, source_page_code, health_status, consecutive_failures, last_success_at, last_error_message -AutoSize -Wrap
