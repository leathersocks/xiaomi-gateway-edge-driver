param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Caps = [ordered]@{
  "locketforest19027.xiaomiGatewayStatus" = "xiaomiGatewayStatus"
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

foreach ($CapabilityId in $Caps.Keys) {
  $ShortId = $Caps[$CapabilityId]
  $Definition = Join-Path $Root "capabilities\$ShortId.json"
  $PresentationTemplate = Join-Path $Root "capabilities\$ShortId-presentation.template.json"

  Write-Host "Updating capability: $CapabilityId"
  & smartthings capabilities:update `
    $CapabilityId `
    --capability-version 1 `
    -i $Definition
  if ($LASTEXITCODE -ne 0) { throw "Capability update failed: $CapabilityId" }

  foreach ($Tag in @("en", "ko")) {
    $TranslationFile = Join-Path $Root "translations\$ShortId-$Tag.json"
    Write-Host "Updating translation [$Tag]: $CapabilityId"
    & smartthings capabilities:translations:upsert `
      $CapabilityId `
      --capability-version 1 `
      -i $TranslationFile
    if ($LASTEXITCODE -ne 0) { throw "Translation update failed: $CapabilityId [$Tag]" }
  }

  $Template = Get-Content $PresentationTemplate -Raw | ConvertFrom-Json
  $UpdateBody = [ordered]@{
    dashboard = $Template.dashboard
    detailView = $Template.detailView
    automation = $Template.automation
  }
  $Temp = Join-Path $env:TEMP "$ShortId-presentation-update.json"
  Write-Utf8NoBom $Temp ($UpdateBody | ConvertTo-Json -Depth 20)

  Write-Host "Updating presentation: $CapabilityId"
  & smartthings capabilities:presentation:update `
    -i $Temp `
    $CapabilityId `
    --capability-version 1
  if ($LASTEXITCODE -ne 0) { throw "Presentation update failed: $CapabilityId" }
}

Write-Host ""
Write-Host "SmartThings UI metadata sync completed."
