param(
  [switch]$SkipUiSync
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$SmartThingsCmd = Get-Command smartthings.cmd -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Xiaomi Gateway Edge Driver install ==="
Write-Host "Package directory: $Root"
Write-Host ""

if (-not $SkipUiSync) {
  $SyncUi = Join-Path $Root "sync-ui.ps1"

  if (Test-Path $SyncUi) {
    Write-Host "Synchronizing custom capability translations/presentation..."
    & $SyncUi

    if ($LASTEXITCODE -ne 0) {
      throw "Gateway-status UI metadata sync failed with exit code $LASTEXITCODE"
    }
  }
  else {
    throw "sync-ui.ps1 was not found: $SyncUi"
  }
}
else {
  Write-Host "Skipping custom capability UI metadata sync (-SkipUiSync)."
}

Write-Host ""
Write-Host "Packaging and installing Edge Driver..."

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
