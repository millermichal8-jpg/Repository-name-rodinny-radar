param(
  [Parameter(Mandatory = $true)]
  [string]$FunctionName,

  [string]$ProjectRef = "xvqzpbfcxhrxgovkkajt",

  [switch]$NoVerifyJwt
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$functionPath = Join-Path "supabase/functions" $FunctionName
if (-not (Test-Path $functionPath)) {
  throw "Funkcia '$FunctionName' lokalne neexistuje v $functionPath"
}

$args = @(
  "supabase",
  "functions",
  "deploy",
  $FunctionName,
  "--project-ref",
  $ProjectRef,
  "--use-api"
)

if ($NoVerifyJwt) {
  $args += "--no-verify-jwt"
}

Write-Host "Nasadzujem funkciu $FunctionName..." -ForegroundColor Cyan
& npx @args

Write-Host "HOTOVO - funkcia $FunctionName bola nasadena." -ForegroundColor Green
