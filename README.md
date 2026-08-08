# Xiaomi Gateway Edge Driver v1.10.1-final-verified

Clean final deployment package based on the runtime-verified v1.10.0 session build.

## Runtime scope

Gateway:
- miIO UDP 54321 health check
- online / degraded / offline status
- optional authenticated child discovery
- optional Zigbee temperature/humidity state polling
- optional BLE-over-MQTT receiver

BLE:
- pdid 5860 temperature / humidity / battery
- pdid 6032 Xiaomi Toothbrush T700i
- dynamic BLE child registration
- automatic existing-parent preservation
- MQTT keepalive and reconnect

T700i:
- live start -> motionSensor active
- live end -> motionSensor inactive
- embedded timestamp parsing
- 60-second live/history filtering
- first-start preservation
- session duration calculation
- last brushing timestamp persistence
- score persistence
- battery handling
- up to 10-minute restart-session recovery

## Final cleanup

The Edge driver ZIP intentionally does not include gateway-side/debug helper tools.

Moved to a separate optional tools archive:
- install-openmiio-mgl03-v5.py
- mqtt-ble-probe-v2.py
- OPENMIIO-SETUP.md

Removed as stale:
- install-v1.9.2.ps1

The final package uses a version-neutral:

```powershell
.\install.ps1
```

or direct CLI:

```powershell
smartthings edge:drivers:package . --install
```

## Optional UI maintenance

`sync-ui.ps1` is only for re-applying the already-existing
`locketforest19027.xiaomiGatewayStatus` definition/translations/presentation.

It is not required for normal package/install.

## Security

- No per-sensor BLE key is embedded.
- No per-sensor token is embedded.
- No fixed BLE DID/MAC inventory is embedded.
- Gateway TOKEN remains a user preference and is not printed to logcat.
- MQTT is intended for trusted LAN/VLAN use only.

## Final package structure

Runtime:
- `config.yml`
- `src/`
- `profiles/`

Existing gateway-status UI metadata:
- `capabilities/`
- `translations/`
- `sync-ui.ps1`

Distribution:
- `install.ps1`
- `README.md`
- `CHANGELOG.md`
- `TOKEN-GUIDE.md`
- `TOOTHBRUSH-SESSION.md`
- `VERSION.txt`
- `SHA256SUMS.txt`
