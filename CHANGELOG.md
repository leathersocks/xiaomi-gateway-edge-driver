# Changelog

## v1.10.1-final-verified - 2026-08-08

- Final package audit and cleanup.
- Scoped T700i restart/session restoration to model `k0918.toothbrush.t700i` only.
- Prevents toothbrush-specific initialization from resetting generic motionSensor children.
- Replaced stale `install-v1.9.2.ps1` with version-neutral `install.ps1`.
- Removed stale toothbrush-capability note from `sync-ui.ps1`.
- Hardened PowerShell CLI invocation to prefer `smartthings.cmd` on Windows.
- Moved openmiio installer/probe/setup document to a separate optional tools archive.
- Removed the prior embedded verification report from the deployment ZIP; verification is distributed separately.
- Retained all runtime-referenced Lua modules and Device Profiles.
- packageKey remains `xiaomi-gateway`.

## v1.10.0-toothbrush-session - 2026-08-08

- Added persistent T700i brushing-session tracking.
- Added first-start preservation so repeated type=0 advertisements do not shorten duration.
- Added live start/end duration calculation.
- Added `duration_text` logging in MM:SS format.
- Added explicit `BLE MQTT toothbrush session complete` log.
- Persisted Last Brushing timestamp, Score and Duration.
- Added 10-minute maximum session sanity guard.
- Added Edge restart recovery for a recent active brushing session.
- Stale persisted active sessions are automatically cleared.
- Historical type=1 records still cannot terminate a live brushing session.
- Standard SmartThings `motionSensor` + `battery` profile retained.
- No new custom capability or custom-capability API permission required.
- packageKey remains `xiaomi-gateway`.

## v1.9.3-toothbrush-runtime-fix - 2026-08-08

- Fixed T700i first-telemetry crash in `mqtt_ble.lua`.
- Missing previous brushing timestamp now safely defaults to `0`.
- Removed the risky nested `tonumber(device:get_field(...))` pattern.
- T700i child creation, motion state mapping, history filtering, score parsing and battery handling are unchanged.
- MQTT keepalive/reconnect behavior is unchanged.
- packageKey remains `xiaomi-gateway`.

## v1.9.2-standard-toothbrush - 2026-08-08

- Removed the new T700i custom-capability dependency from the device profile/runtime.
- T700i brushing state now uses standard `motionSensor`.
- T700i battery remains standard `battery`.
- Last brushing timestamp and optional score remain internal/log-only.
- Retained pdid 6032 and EID 12291/0x3003 parsing.
- Retained the 60-second live/history filter.
- Retained dynamic child creation and existing BLE temperature/humidity support.
- packageKey remains `xiaomi-gateway`.
