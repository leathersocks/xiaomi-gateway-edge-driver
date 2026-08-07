# Xiaomi Gateway Edge Driver v1.2.6f-final

Clean distribution package based on the verified v1.2.6f runtime.

## Purpose

Registers and monitors Xiaomi gateways as SmartThings LAN devices using
Xiaomi miIO UDP port 54321.

Validated target gateways:

- `lumi.gateway.mgl001`
- `lumi.gateway.mgl03`

## Final SmartThings UI

```text
Status
IP
Latency
Last Seen
Failures
```

Custom capabilities:

```text
locketforest19027.xiaomiGatewayStatus
locketforest19027.xiaomiGatewayIp
locketforest19027.xiaomiGatewayLatency
locketforest19027.xiaomiGatewayLastSeen
locketforest19027.xiaomiGatewayFailures
```

## Direct install

This final package is already populated with the final Device Profile and
runtime capability IDs. No setup script is required.

```powershell
cd C:\SmartThings\xiaomi-gateway-edge-driver-v1.2.6f-final
smartthings edge:drivers:package . --install
```

## Optional UI metadata re-sync

The existing custom capabilities, translations, and presentations are already
configured in the SmartThings account. If the UI metadata ever needs to be
re-applied:

```powershell
.\sync-ui.ps1
```

Then package/install the driver again if needed.

## Runtime

- Xiaomi miIO UDP hello on port 54321
- No Xiaomi token required
- Scheduled health check
- Manual Refresh health check
- Online / degraded / offline hysteresis
- Latency measurement
- KST Last Seen (`HH:MM:SS`)
- Failure count
- Device ID retained in logs
- `presenceSensor` and `healthCheck` retained for SmartThings compatibility

## Package contents

The final distribution intentionally removes:

- historical `archive/`
- previous setup scripts
- old V1/V2 diagnostics capability assets
- fallback diagnostics code
- duplicate diagnostics source
- profile templates used only during development

Only the final runtime, Device Profile, five capability definitions,
five presentations, EN/KO translations, documentation, and optional UI sync
script remain.

## Important scope

This package uses the existing SmartThings custom capability namespace:

```text
locketforest19027
```

Therefore it is a clean deployment package for the same SmartThings developer
account/environment. A different SmartThings account would need its own custom
capability namespace and regenerated profile/runtime IDs.
