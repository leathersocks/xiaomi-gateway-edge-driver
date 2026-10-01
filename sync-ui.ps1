param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$Namespace = "locketforest19027"

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
Write-Host "=== Gateway custom capability UI sync ==="
Write-Host "Translations and Capability Presentation are SmartThings cloud metadata."
Write-Host "This sync is required whenever translation or presentation files change."
Write-Host ""

foreach ($ShortId in @("xiaomiGatewayStatus", "xiaomiGatewayDevices", "gatewayView")) {
  $Definition = Join-Path $Root "capabilities\$ShortId.json"
  $DefinitionData = Get-Content $Definition -Raw -Encoding UTF8 | ConvertFrom-Json
  $CapabilityId = "$Namespace.$($DefinitionData.id)"
  $PresentationTemplate = Join-Path $Root "capabilities\$ShortId-presentation.template.json"
  $SmartThingsCmd = Get-Command smartthings.cmd -ErrorAction SilentlyContinue
  $SmartThingsExecutable = if ($SmartThingsCmd) { $SmartThingsCmd.Source } else { "smartthings" }
  $Lookup = & $SmartThingsExecutable capabilities $CapabilityId --capability-version 1 --json 2>&1
  $LookupExit = $LASTEXITCODE

  if ($LookupExit -eq 0) {
    Invoke-ST -Description "Updating capability: $CapabilityId" -Arguments @(
      "capabilities:update", $CapabilityId, "--capability-version", "1", "-i", $Definition
    )
  }
  elseif ($ShortId -in @("xiaomiGatewayDevices", "gatewayView") -and
          ($Lookup -join "`n") -match 'status (403|404)') {
    $Created = Invoke-ST -Description "Creating capability: $CapabilityId" -Arguments @(
      "capabilities:create", "--namespace", $Namespace, "-i", $Definition
    )
    $CreatedDefinition = ($Created -join "`n") | ConvertFrom-Json
    if ($CreatedDefinition.id -ne $CapabilityId) {
      throw "Created capability ID $($CreatedDefinition.id) does not match $CapabilityId. Check the definition name."
    }
  }
  else {
    throw "Capability lookup failed for $CapabilityId (exit $LookupExit): $Lookup"
  }

  foreach ($Tag in @("en", "ko", "ko-KR")) {
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

  $Template = Get-Content $PresentationTemplate -Raw -Encoding UTF8 | ConvertFrom-Json
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
      $CapabilityId,
      "--capability-version", "1",
      "-i", $Temp
    )
}

Write-Host ""
Write-Host "Gateway status and connected-device UI metadata sync completed."
Write-Host "Korean locales uploaded: ko, ko-KR"
Write-Host "Expected values: online=CONNECTED(Korean), degraded=UNSTABLE(Korean), offline=DISCONNECTED(Korean)"
Write-Host "Expected layout: top status, Gateway view selector, native bridge children"
Write-Host "Duplicate status and text inventory detail cards are intentionally hidden."
