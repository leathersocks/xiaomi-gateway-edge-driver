param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$SmartThingsCmd = Get-Command smartthings.cmd -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Xiaomi Gateway Edge Driver install ==="
Write-Host "Package directory: $Root"
Write-Host ""

if ($SmartThingsCmd) {
  & $SmartThingsCmd.Source edge:drivers:package $Root --install
}
else {
  & smartthings edge:drivers:package $Root --install
}

if ($LASTEXITCODE -ne 0) {
  throw "SmartThings Edge package/install failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Driver package/install completed."
