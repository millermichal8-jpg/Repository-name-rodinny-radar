param(
    [string]$BaseUrl = "http://127.0.0.1:54321/functions/v1",
    [string]$SyncToken,
    [string[]]$SourceCodes = @(
        "praha12-events",
        "ostrava-events",
        "olomouc-region-events",
        "usti-events",
        "plzen-events",
        "bkis-events",
        "senec-events",
        "bb-events",
        "nitra-city-events",
        "trnava-city-events",
        "zilina-events",
        "tvrdosin-events"
    )
)

$ErrorActionPreference = "Stop"

if (-not $SyncToken) {
    $tokenFile = ".\.rr-backups\secrets\catalog-sync-token.dpapi"
    if (-not (Test-Path $tokenFile)) {
        throw "Chýba SyncToken a nenašiel sa lokálne uložený token."
    }

    $encryptedToken = (Get-Content $tokenFile -Raw).Trim()
    $secureToken = ConvertTo-SecureString -String $encryptedToken
    $credential = [System.Management.Automation.PSCredential]::new("sync", $secureToken)
    $SyncToken = $credential.GetNetworkCredential().Password
}

$headers = @{
    "Content-Type" = "application/json; charset=utf-8"
    "X-Sync-Token" = $SyncToken
}

$rows = @()
$rawRuns = @()

foreach ($sourceCode in $SourceCodes) {
    Write-Host "`n=== PREVIEW: $sourceCode ===" -ForegroundColor Yellow

    $body = @{
        action = "preview"
        sourceCodes = @($sourceCode)
        maxEvents = 200
    } | ConvertTo-Json -Depth 8

    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri "$BaseUrl/municipal-event-sync" `
            -Headers $headers `
            -Body $bodyBytes `
            -TimeoutSec 300

        $statsProperty = $response.sources.PSObject.Properties[$sourceCode]
        if (-not $statsProperty) {
            throw "Odpoveď neobsahuje štatistiky zdroja $sourceCode."
        }

        $stats = $statsProperty.Value
        $errorCount = @($stats.errors).Count
        $accepted = [int]$stats.accepted
        $discovered = [int]$stats.discoveredLinks
        $parsed = [int]$stats.parsedCandidates
        $rejected = [int]$stats.rejected

        $status = if ($errorCount -gt 0) {
            "warning"
        } elseif ($accepted -gt 0) {
            "healthy"
        } elseif ($discovered -gt 0) {
            "links-only"
        } else {
            "empty"
        }

        $reasonParts = @()
        if ($stats.rejectedReasons) {
            foreach ($property in $stats.rejectedReasons.PSObject.Properties) {
                $reasonParts += "$($property.Name)=$($property.Value)"
            }
        }

        $row = [pscustomobject]@{
            sourceCode = $sourceCode
            status = $status
            discoveredLinks = $discovered
            parsedCandidates = $parsed
            accepted = $accepted
            rejected = $rejected
            parserErrors = $errorCount
            rejectedReasons = ($reasonParts -join "; ")
        }

        $rows += $row
        $rawRuns += [pscustomobject]@{
            sourceCode = $sourceCode
            response = $response
        }

        $row | Format-Table -AutoSize -Wrap
    }
    catch {
        $rows += [pscustomobject]@{
            sourceCode = $sourceCode
            status = "failed"
            discoveredLinks = 0
            parsedCandidates = 0
            accepted = 0
            rejected = 0
            parserErrors = 1
            rejectedReasons = $_.Exception.Message
        }
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = ".\supabase\test-results\source-reliability-v1\$stamp-preview"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$rows | Export-Csv (Join-Path $reportDir "source-reliability.csv") -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    generatedAt = (Get-Date).ToString("o")
    baseUrl = $BaseUrl
    summary = @{
        healthy = @($rows | Where-Object status -eq "healthy").Count
        empty = @($rows | Where-Object status -eq "empty").Count
        linksOnly = @($rows | Where-Object status -eq "links-only").Count
        warnings = @($rows | Where-Object status -eq "warning").Count
        failed = @($rows | Where-Object status -eq "failed").Count
    }
    rows = $rows
    runs = $rawRuns
} | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $reportDir "source-reliability.json") -Encoding UTF8

Write-Host "`n--- SOURCE RELIABILITY V1 SÚHRN ---" -ForegroundColor Cyan
$rows | Format-Table -AutoSize -Wrap
Write-Host "Report: $reportDir" -ForegroundColor Green
Write-Host "Preview nič nezapísal." -ForegroundColor Green
