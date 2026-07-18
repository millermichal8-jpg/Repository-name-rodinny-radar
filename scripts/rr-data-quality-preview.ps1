param(
    [switch]$Online,
    [int]$Limit = 50,
    [int]$DaysBack = 180,
    [int]$ScanLimit = 2000
)

$ErrorActionPreference = "Stop"

$tokenFile = ".\.rr-backups\secrets\catalog-sync-token.dpapi"
if (-not (Test-Path $tokenFile)) {
    throw "Nenašiel sa bezpečne uložený synchronizačný token."
}

$encryptedToken = (Get-Content $tokenFile -Raw).Trim()
$secureToken = ConvertTo-SecureString -String $encryptedToken
$credential = [System.Management.Automation.PSCredential]::new("sync", $secureToken)
$syncToken = $credential.GetNetworkCredential().Password

if ($Online) {
    $projectRef = (Get-Content ".\supabase\.temp\project-ref" -Raw).Trim()
    $baseUrl = "https://$projectRef.supabase.co/functions/v1"
} else {
    $baseUrl = "http://127.0.0.1:54321/functions/v1"
}

$body = @{
    action = "preview"
    limit = [Math]::Max(1, [Math]::Min(500, $Limit))
    daysBack = [Math]::Max(1, [Math]::Min(730, $DaysBack))
    scanLimit = [Math]::Max(1, [Math]::Min(10000, $ScanLimit))
} | ConvertTo-Json -Depth 6

$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

$response = Invoke-RestMethod `
    -Method Post `
    -Uri "$baseUrl/data-quality-review" `
    -Headers @{
        "Content-Type" = "application/json; charset=utf-8"
        "X-Sync-Token" = $syncToken
    } `
    -Body $bodyBytes `
    -TimeoutSec 300

Write-Host "`n--- DATA QUALITY V1 PREVIEW ---" -ForegroundColor Cyan
Write-Host "Kandidáti čakajúci na kontrolu: $($response.stats.pending)"
Write-Host "Vyžadujú ručnú kontrolu: $($response.stats.needsReview)"
Write-Host "Vhodné na neskoršie auto-merge: $($response.stats.autoMergeEligible)"
Write-Host "Verejné podujatia zmenené: NIE" -ForegroundColor Green

$response.candidates |
    Select-Object candidate_id, similarity_score,
        left_source_code, left_title, left_city, left_starts_at,
        right_source_code, right_title, right_city, right_starts_at |
    Format-Table -AutoSize -Wrap

$resultsDir = ".\supabase\test-results\data-quality-v1"
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$resultPath = Join-Path $resultsDir (
    "preview-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss")
)

$response | ConvertTo-Json -Depth 40 | Set-Content $resultPath -Encoding utf8
Write-Host "`nReport: $resultPath" -ForegroundColor Green

$syncToken = $null
$credential = $null
$secureToken = $null
$encryptedToken = $null
