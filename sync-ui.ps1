param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$CapabilityId = "locketforest19027.xiaomiGatewayStatus"
$ShortId = "xiaomiGatewayStatus"

$Definition = Join-Path $Root "capabilities\$ShortId.json"
$PresentationTemplate = Join-Path $Root "capabilities\$ShortId-presentation.template.json"

function Invoke-ST {
  param(
    [Parameter(Mandatory=$true)]
    [string[]]$Arguments,
    [Parameter(Mandatory=$true)]
    [string]$Description
  )

  $SmartThingsCmd = Get-Command smartthings.cmd -ErrorAction SilentlyContinue

  Write-Host $Description

  if ($SmartThingsCmd) {
    & $SmartThingsCmd.Source @Arguments
  }
  else {
    & smartthings @Arguments
  }

  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE"
  }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

Write-Host ""
Write-Host "Optional gateway-status UI metadata sync"
Write-Host "This is NOT required for normal driver package/install."
Write-Host "Use it only when the existing gateway-status capability UI must be re-applied."
Write-Host ""

Invoke-ST `
  -Description "Updating capability: $CapabilityId" `
  -Arguments @(
    "capabilities:update",
    $CapabilityId,
    "--capability-version", "1",
    "-i", $Definition
  )

foreach ($Tag in @("en", "ko")) {
  $TranslationFile = Join-Path $Root "translations\$ShortId-$Tag.json"

  Invoke-ST `
    -Description "Updating translation [$Tag]: $CapabilityId" `
    -Arguments @(
      "capabilities:translations:upsert",
      $CapabilityId,
      "--capability-version", "1",
      "-i", $TranslationFile
    )
}

$Template = Get-Content $PresentationTemplate -Raw | ConvertFrom-Json
$UpdateBody = [ordered]@{
  dashboard = $Template.dashboard
  detailView = $Template.detailView
  automation = $Template.automation
}

$Temp = Join-Path $env:TEMP "$ShortId-presentation-update.json"
Write-Utf8NoBom $Temp ($UpdateBody | ConvertTo-Json -Depth 20)

Invoke-ST `
  -Description "Updating presentation: $CapabilityId" `
  -Arguments @(
    "capabilities:presentation:update",
    "-i", $Temp,
    $CapabilityId,
    "--capability-version", "1"
  )

Write-Host ""
Write-Host "Gateway-status UI metadata sync completed."
