param(
    [string]$BaseUrl = "http://127.0.0.1:54321/functions/v1",
    [Parameter(Mandatory = $true)]
    [string]$SyncToken,
    [ValidateRange(1, 250)]
    [int]$Limit = 100,
    [ValidateRange(0, 100)]
    [int]$MinQuality = 80,
    [string[]]$SourceCodes,
    [string]$Note = "Kontrolovane publikovanie cez Event Review V1.",
    [switch]$ConfirmWrite
)

$ErrorActionPreference = "Stop"

$headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-Sync-Token" = $SyncToken
}

if (-not $ConfirmWrite) {
    Write-Host "`nZAPIS NIE JE POVOLENY." -ForegroundColor Yellow
    Write-Host "Najprv spusti rr-event-review-preview.ps1 a skontroluj frontu." -ForegroundColor Yellow
    Write-Host "Pre realne publikovanie pridaj parameter -ConfirmWrite." -ForegroundColor Yellow
    exit 2
}

$bodyObject = @{
    action = "batch-publish"
    confirmWrite = $true
    minQuality = $MinQuality
    limit = $Limit
    actor = "rr-event-review-batch-publish.ps1"
    note = $Note
}

if ($SourceCodes -and $SourceCodes.Count -gt 0) {
    $bodyObject.sourceCodes = @($SourceCodes)
}

$body = $bodyObject | ConvertTo-Json -Depth 8

Write-Host "`n--- EVENT REVIEW V1: KONTROLOVANE PUBLIKOVANIE ---" -ForegroundColor Yellow
Write-Host "Minimalna kvalita: $MinQuality" -ForegroundColor Cyan
Write-Host "Maximalny pocet: $Limit" -ForegroundColor Cyan

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$BaseUrl/event-review" `
    -Headers $headers `
    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
    -TimeoutSec 300

$result = $response.result
$publishedItems = @($result.results)

$publishedItems |
    ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.experienceId
            title = [string]$_.title
            status = [string]$_.publicationStatus
        }
    } |
    Format-Table -AutoSize -Wrap

Write-Host "`nPublikovane podujatia: $($result.published)" -ForegroundColor Green

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = ".\supabase\test-results\event-review-v1\$stamp-batch-publish"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$response |
    ConvertTo-Json -Depth 50 |
    Set-Content (Join-Path $reportDir "batch-publish.json") -Encoding UTF8

Write-Host "Audit a report: $((Resolve-Path $reportDir).Path)" -ForegroundColor Green
