param(
    [string]$BaseUrl = "http://127.0.0.1:54321/functions/v1",
    [Parameter(Mandatory = $true)]
    [string]$SyncToken,
    [ValidateRange(1, 250)]
    [int]$Limit = 100,
    [ValidateRange(0, 100)]
    [int]$MinQuality = 80,
    [string[]]$SourceCodes,
    [ValidateSet("review", "pending", "approved", "published", "rejected", "all")]
    [string]$Status = "review"
)

$ErrorActionPreference = "Stop"

$headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-Sync-Token" = $SyncToken
}

$bodyObject = @{
    action = "queue"
    status = $Status
    minQuality = $MinQuality
    limit = $Limit
}

if ($SourceCodes -and $SourceCodes.Count -gt 0) {
    $bodyObject.sourceCodes = @($SourceCodes)
}

$body = $bodyObject | ConvertTo-Json -Depth 8

Write-Host "`n--- EVENT REVIEW V1 PREVIEW ---" -ForegroundColor Cyan

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/event-review" `
    -Headers $headers `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
    -TimeoutSec 180

$queue = $response.result
$items = @($queue.items)

$rows = foreach ($item in $items) {
    $sourceText = if ($item.sourceCodes) { @($item.sourceCodes) -join "," } else { "" }
    $issueText = if ($item.issues) { @($item.issues) -join "," } else { "" }

    [pscustomobject]@{
        id = [string]$item.id
        title = [string]$item.title
        city = [string]$item.city
        start = [string]$item.nextStartsAt
        quality = [int]$item.qualityScore
        ready = [bool]$item.readyToPublish
        sources = $sourceText
        issues = $issueText
    }
}

$rows |
    Select-Object id, title, city, start, quality, ready, sources, issues |
    Format-Table -AutoSize -Wrap

$statsBody = @{ action = "stats" } | ConvertTo-Json
$statsResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/event-review" `
    -Headers $headers `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($statsBody)) `
    -TimeoutSec 180

$stats = $statsResponse.result

Write-Host "`n--- SUHRN ---" -ForegroundColor Cyan
Write-Host "V review: $($stats.review)" -ForegroundColor Yellow
Write-Host "Cakajuce: $($stats.pending)" -ForegroundColor Yellow
Write-Host "Schvalene, este nepublikovane: $($stats.approved)" -ForegroundColor Yellow
Write-Host "Pripravene na publikovanie: $($stats.readyToPublish)" -ForegroundColor Green
Write-Host "Blokovane kontrolou: $($stats.blocked)" -ForegroundColor Yellow
Write-Host "Publikovane: $($stats.published)" -ForegroundColor Green
Write-Host "Zamietnute: $($stats.rejected)" -ForegroundColor Red

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = ".\supabase\test-results\event-review-v1\$stamp-preview"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$response |
    ConvertTo-Json -Depth 50 |
    Set-Content (Join-Path $reportDir "queue.json") -Encoding UTF8

$statsResponse |
    ConvertTo-Json -Depth 50 |
    Set-Content (Join-Path $reportDir "stats.json") -Encoding UTF8

$rows |
    Export-Csv (Join-Path $reportDir "queue.csv") -NoTypeInformation -Encoding UTF8

Write-Host "`nPreview nic nezapisal." -ForegroundColor Green
Write-Host "Report: $((Resolve-Path $reportDir).Path)" -ForegroundColor Green
