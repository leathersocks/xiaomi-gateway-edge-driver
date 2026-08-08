# Changelog

## v1.8.2-runtime-fix - 2026-08-08

- Fixed `attempt to call a nil value (global 'gateway_for_device')`.
- Removed the final stale static-gateway call from `mqtt_ble.start()`.
- Split MQTT applicability from MQTT enabled state.
- Disabling `BLE via MQTT` now stops the previous listener correctly.
- Kept automatic BLE child creation and automatic parent selection.
- Kept the 9 visible Gateway settings.
- Replaced a dynamic-discovery bitwise DNI expression with modulo arithmetic.
- `gateways.lua` and `known_ble.lua` remain removed.
- packageKey remains `xiaomi-gateway`.

## v1.8.1-auto-ble-parent - 2026-08-08

- Removed the BLE-registration preference from the current Gateway profile.
- Supported BLE pdid 5860 children are now created automatically.
- Existing BLE children are searched across all Gateway parents by `ble-<MAC>`.
- Existing child parent and SmartThings name are preserved.
- New-child parent selection is automatic.
- Removed the BLE-host role from gateway runtime.
- Rebuilt `child_manager.lua` to correct the malformed v1.8.0 transition.
- Rebuilt MQTT BLE parent handling and removed the stale BLE host model reference.
- Visible Gateway settings reduced from 10 to 9.
- `gateways.lua` and `known_ble.lua` remain removed.
- packageKey remains `xiaomi-gateway`.

## v1.8.0-dynamic-gateway-ble - 2026-08-08

- Removed `src/gateways.lua`.
- Removed all static gateway model/label/DNI definitions.
- Retained removal of `src/known_ble.lua`.
- Gateway identity is now dynamic for any driver-created `xiaomi-gateway-*` LAN parent.
- Existing legacy `xiaomi-gateway-registration-*` devices remain compatible.
- Gateway roles are determined only by preferences:
  BLE host, MQTT receiver, child discovery, and Zigbee poller.
- Removed runtime model checks for `lumi.gateway.mgl001` and `lumi.gateway.mgl03`.
- BLE MQTT receiver can run on any configured gateway with `BLE via MQTT=On`.
- BLE host is selected dynamically from the gateway with
  `Register known BLE sensors=On`.
- Added generic dynamic gateway registration: one unconfigured gateway slot
  at a time, with no fixed gateway count or model inventory.
- New gateway role defaults are Off; existing stored preferences remain intact.
- packageKey remains `xiaomi-gateway`.

## v1.7.9-dynamic-ble - 2026-08-08

- Removed `src/known_ble.lua`.
- Removed per-sensor static NAME/DID/MAC mappings from runtime source.
- BLE temperature/humidity sensors are identified from live MQTT by pdid 5860 and MAC.
- Existing SmartThings BLE children are found by `ble-<normalized MAC>`.
- `Register known BLE sensors` controls dynamic creation of previously unseen sensors only.
- New sensor default label is `BLE 온습도 <MAC suffix>`.
- Existing child labels are preserved.
- BLE KEY and sensor TOKEN remain unused and are not embedded.
- Authenticated get_device_list continues to skip BLE children.
- v1.7.3 MQTT keepalive and v1.7.4 BLE presentation retained.
- packageKey remains `xiaomi-gateway`.

## v1.7.8-final-verified - 2026-08-08

- Final static audit of scripts, runtime dependency graph, profiles and package contents.
- Fixed `Register known BLE sensors` so it works even when Auto child discovery is Off.
- Authenticated get_device_list discovery now skips BLE DIDs to prevent duplicate BLE
  children under mgl03; known BLE children remain hosted under mgl001.
- Auto discovery and Zigbee polling timers are created only when enabled.
- Zigbee polling explicitly requires Auto child discovery to build current inventory.
- Removed dead Refresh/healthCheck capability-handler paths from the Status-only gateway.
- Removed legacy mgl001 Telnet/openmiio runtime modules:
  `ble_openmiio.lua`, `telnet_enable.lua`, `telnet_client.lua`, `sha256.lua`.
- Removed obsolete gateway custom capability files/translations for IP, latency,
  last-seen and failure-count; Status assets only remain.
- Removed Python `__pycache__`.
- Removed dead manual-child manifest code from `child_manager.lua`.
- Fixed `mqtt-ble-probe-v2.py` keepalive so PINGREQ is based on outbound idle time,
  not receive inactivity.
- Updated stale docs/settings labels and fixed MQTT topic documentation.
- Retained v1.7.3 Edge MQTT keepalive and v1.7.4 temperature+humidity dashboard.
- packageKey remains `xiaomi-gateway`.

## v1.7.7-settings-labels - 2026-08-08

- Renamed visible settings to the exact requested labels.
- `Gateway IP address` -> `IP address`.
- `Gateway miIO token` -> `TOKEN`.
- `Child state polling` -> `Zigbee state polling`.
- `Child poll interval` -> `Zigbee poll interval`.
- `BLE via mgl03 MQTT` -> `BLE via MQTT`.
- Removed `BLE MQTT topic` from the Settings UI.
- MQTT topic is now fixed internally to `#`.
- Retained v1.7.3 MQTT keepalive stabilization.
- Retained v1.7.4 BLE Temperature + Humidity dashboard presentation.
- packageKey remains `xiaomi-gateway`.

## v1.7.6-selected-settings - 2026-08-08

- Gateway Settings reduced to the exact requested operational list:
  Gateway IP, health interval, auto discovery, gateway token, known BLE
  registration, child polling + interval, and mgl03 MQTT settings.
- Removed UI preferences for probe timeout, failure threshold, installation note,
  manual child manifests, and child-follows-gateway.
- Probe timeout remains fixed internally at 3 seconds.
- Offline threshold remains fixed internally at 3 failures.
- Child reachability continues to follow the parent gateway.
- Manual child manifest sync removed from lifecycle.
- Retained authenticated auto discovery and child state polling.
- Retained v1.7.3 MQTT keepalive stabilization.
- Retained v1.7.4 temperature+humidity dashboard presentation.
- packageKey remains `xiaomi-gateway`.

## v1.7.4-temp-summary - 2026-08-08

- Fixed BLE sensor dashboard/summary presentation so temperature is shown
  together with humidity.
- Added embedded `deviceConfig.dashboard.states` with composite:
  - temperatureMeasurement
  - relativeHumidityMeasurement
- Detail view remains exactly:
  - Temperature
  - Humidity
  - Battery
- Changed BLE child category to official `TempHumiditySensor`.
- Changed BLE child profile name to `xiaomi-child-temp-hum-v174` to force
  a new Device Presentation.
- Existing BLE children are migrated to the new profile using
  `try_update_metadata({ profile = definition.profile, ... })`; device IDs
  and parent-child relationships are preserved.
- v1.7.3 MQTT keepalive and duplicate-topic filtering retained.

## v1.7.3-mqtt-keepalive-ui - 2026-08-08

- Gateway SmartThings profile now displays only custom `Status`.
- BLE temperature/humidity child profile now displays only:
  `Temperature`, `Humidity`, and `Battery`.
- Gateway IP, latency, last seen, failures, presence, healthCheck and refresh
  are no longer exposed as gateway UI capabilities.
- Gateway diagnostic values remain available internally for driver logic/logs.
- MQTT keepalive no longer depends on receive inactivity.
- Sends PINGREQ every 15 seconds based on client outbound idle time.
- Requires PINGRESP within 10 seconds.
- MQTT receive timeout shortened to 5 seconds to drive keepalive scheduling.
- Automatic reconnect remains 3 seconds.
- BLE parser now ignores `openmiio/log` copies and processes only
  `miio/report` and `central/report`.
- Existing BLE child keys and packageKey remain unchanged.

## v1.7.2-mqtt-fieldfix - 2026-08-08

- Fixed first-run MQTT restart crash in `current_generation()`.
- SmartThings `device:get_field()` may return zero Lua values when unset;
  v1.7.1 passed it directly to `tonumber()` and triggered:
  `bad argument #1 to 'tonumber' (value expected)`.
- `current_generation()` now stores the field result in a local variable first,
  returns `0` when nil, and only then calls `tonumber(value)`.
- `mqtt.status()` was hardened in the same way.
- MQTT diagnostics, automatic reconnect, BLE event parsing, and existing child
  mappings are otherwise unchanged.

## v1.7.1-mqtt-diagnostics - 2026-08-08

- SmartThings Refresh on a gateway now restarts the BLE MQTT listener when applicable.
- Child Refresh also requests a restart on its parent gateway when applicable.
- Added stage-by-stage MQTT diagnostics:
  - start/restart request
  - listener scheduling
  - callback entry
  - TCP connect
  - MQTT CONNECT / CONNACK
  - SUBSCRIBE / SUBACK
  - BLE-matching PUBLISH
  - reconnect and exceptions
- Added an internal MQTT connection state for diagnostic logging.
- Wrapped each MQTT session with `pcall` so runtime exceptions are explicit in logcat.
- Active cosock sockets are now stored in a module-local runtime table instead of
  `device:set_field`, avoiding userdata storage through the SmartThings device field API.
- Automatic reconnect remains 3 seconds.
- Existing packageKey, gateway definitions, BLE child keys, miIO health checks,
  child discovery, and Zigbee state polling are preserved.

## v1.7.0-mqtt-ble - 2026-08-08

- Replaced v1.6 mgl001 Telnet/openmiio log polling with local MQTT push.
- Uses the mgl03 openmiio/Mosquitto broker over TCP 1883.
- Added pure-Lua MQTT 3.1.1 CONNECT/SUBSCRIBE/PUBLISH/PING handling over cosock.
- Added automatic reconnect after broker/network disconnects.
- Default subscription is `#` to cover both `central/report` and `miio/report`.
- Strict `_async.ble_event` JSON parsing avoids false BLE-shaped MQTT messages.
- Retains `frmCnt` duplicate suppression.
- Retains the same known BLE child keys under mgl001.
- Validated against a live pdid 5860 event:
  - DID `blt.1.1g5h2pv194k00`
  - EID 19458
  - edata `32`
  - decoded humidity 50%.
- Removed runtime dependency on the mgl001 Gateway Key for BLE values.
- Bundled the mgl03 openmiio v5 helper and resilient MQTT BLE probe v2.
- Existing parent health, authenticated miIO discovery, and Zigbee state polling retained.
