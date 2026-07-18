param(
    [string]$BaseUrl = "http://127.0.0.1:54321/functions/v1",
    [string]$SyncToken = "local-dev-token",
    [switch]$IncludeCron,
    [string]$OutputDirectory = ".\supabase\test-results\monitoring-v1"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

$body = @{
    action = "preview"
    includeCron = [bool]$IncludeCron
} | ConvertTo-Json -Depth 8

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$($BaseUrl.TrimEnd('/'))/monitoring-report" `
    -Headers @{
        "Content-Type" = "application/json; charset=utf-8"
        "X-Sync-Token" = $SyncToken
    } `
    -Body $bodyBytes `
    -TimeoutSec 180

if ($response.version -ne "monitoring-report-v1") {
    throw "Monitoring funkcia vrátila neočakávanú verziu: $($response.version)"
}

$result = $response.result
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultDirectory = Join-Path $OutputDirectory "$timestamp-preview"
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null

$jsonPath = Join-Path $resultDirectory "monitoring-report.json"
$csvPath = Join-Path $resultDirectory "monitoring-findings.csv"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
    $jsonPath,
    ($result | ConvertTo-Json -Depth 40),
    $utf8NoBom
)

@($result.findings) |
    ForEach-Object {
        [pscustomobject]@{
            Severity = $_.severity
            Category = $_.category
            ScopeCode = $_.scopeCode
            Title = $_.title
            Message = $_.message
            Fingerprint = $_.fingerprint
        }
    } |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "`n--- MONITORING V1 PREVIEW ---" -ForegroundColor Cyan
Write-Host "Kontrolované zdroje: $($result.summary.sourcesChecked)"
Write-Host "Kontrolované Cron úlohy: $($result.summary.cronJobsChecked)"
Write-Host "Critical: $($result.summary.critical)" -ForegroundColor Red
Write-Host "Warnings: $($result.summary.warnings)" -ForegroundColor Yellow
Write-Host "Info: $($result.summary.info)" -ForegroundColor Cyan
Write-Host "Incidenty zmenené: NIE – iba preview" -ForegroundColor Green
Write-Host "JSON: $jsonPath" -ForegroundColor Green
Write-Host "CSV: $csvPath" -ForegroundColor Green

@($result.findings) |
    Select-Object severity, category, scopeCode, title, message |
    Format-Table -AutoSize -Wrap
