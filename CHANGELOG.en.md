# Changelog

[한국어](CHANGELOG.md)

This document records the major changes to **Xiaomi Gateway Edge Driver** from the initial `v1.0.0` release through the current version.

- The history is based on actual generated packages, README files, setup scripts, verification materials, and runtime verification results.
- Test/fix builds are also recorded when they affected later versions.
- Version numbers that cannot be confirmed from available materials are not invented. For example, versions such as `v1.7.5` are omitted when no supporting material exists.
- Every version was developed with the goal of preserving `packageKey: xiaomi-gateway` so existing installations can be updated.

---

## v1.10.7-final-verified — 2026-08-09

- Finalized and verified Korean display for the Gateway status Custom Capability.
- Added a Gateway profile refresh request on startup using `device:try_update_metadata({ profile = "xiaomi-gateway" })` so existing Gateway devices stop referencing an older Device Presentation/profile.
- Uses a per-version persistent marker so the profile refresh runs only once per Gateway device for this release.
- Verified in the actual SmartThings app that `online / degraded / offline` are displayed as the Korean equivalents of Connected / Unstable / Disconnected.
- Verified the combined `ko` and `ko-KR` translations, Capability Presentation, Embedded Device Configuration, and existing-device profile-refresh path.
- Preserves the v1.10.4+ T700i stale-timestamp forced-stop fix, immediate `motionSensor=inactive` transition, and 30-second watchdog fallback.
- Marked this release as the final verified build as of 2026-08-09.

## v1.10.6-gateway-presentation-refresh — 2026-08-09

- Intermediate fix for a case where Gateway status translations were successfully uploaded to SmartThings cloud but existing Device Presentations still displayed English values.
- Added a `ko-KR` locale translation file mapping `online / degraded / offline` to Korean labels.
- Added Embedded Device Configuration (`config.values.enabledValues`) to the Gateway profile Custom Capability so Edge Driver packaging generates a fresh Device Presentation.
- Translation and Capability Presentation uploads succeeded, but existing devices could still keep an older VID/profile, so v1.10.7 added explicit profile refresh for existing devices.

## v1.10.5-gateway-status-i18n-fix — 2026-08-09

- First-stage fix for Korean values in `translations/xiaomiGatewayStatus-ko.json` not appearing in the SmartThings app.
- Added `alternatives` to the Capability Presentation Dashboard and Detail View and changed displayed state labels to reference `{{i18n.attributes.gatewayStatus.i18n.value.<state>.label}}`.
- Changed `install.ps1` to run `sync-ui.ps1` by default so the Capability definition, EN/KO translations, and Presentation are synchronized to SmartThings cloud before packaging/installing the Edge Driver.
- Updated `sync-ui.ps1` guidance and made UI metadata synchronization an explicit part of the normal install path.
- Cloud translation/Presentation updates succeeded, but the app still displayed English because of the existing Device Presentation/VID, requiring the follow-up releases.

## v1.10.4-t700i-stale-stop-fix — 2026-08-09

- Added handling for the real T700i forced-stop pattern where `frmCnt` and Gateway timestamp (`gwts`) are current but the embedded timestamp in EID `0x3003` repeats the timestamp of a previous completed brushing session.
- Fixed the case where the 60-second live/history filter treated that stale embedded timestamp as history and ignored the forced-stop `type=1` event.
- When a non-zero end event arrives during an active session and only the embedded timestamp is stale, the driver infers `gwts` as the effective end timestamp.
- An inferred forced stop immediately emits `motionSensor=inactive` and invalidates the watchdog.
- Preserves the raw embedded timestamp for diagnostics while using `gwts` for session end time, last brushing time, and brushing-duration calculation.
- Verified on a real Hub: after roughly 10 seconds of brushing, a forced stop produced `forced_stop=true`, `duration=10s`, immediate `inactive`, and no later watchdog timeout.

## v1.10.3-t700i-raw-diagnostics — 2026-08-09

- Added raw T700i BLE diagnostic logging to identify the actual packet structure behind the forced-stop issue.
- For `pdid=6032`, logs topic, DID, MAC, pdid, frmCnt, gwts, and each event's EID/edata/type/event timestamp before child resolution and `frmCnt` duplicate suppression.
- Diagnostics confirmed that forced-stop packets arrive with fresh `frmCnt`/`gwts` and `type=1`, while the embedded event timestamp points to a previous completed brushing session.
- This finding led directly to the stale-timestamp inference logic added in v1.10.4.

## v1.10.2-t700i-forced-stop-fix — 2026-08-09

- Fixed a case where SmartThings `motionSensor` could remain `active` after the user force-stopped or ended T700i brushing early.
- Reproduction logs showed that a BLE MQTT packet still arrived after a `type=0` start, but the previous decoder did not produce the expected end-state transition.
- Changed the T700i MiBeacon EID `12291 / 0x3003` event rule to `type=0 = start`, `type!=0 = end`.
- Handles not only the normal observed `type=1`, but any non-zero end code as an immediate `motionSensor=inactive` transition.
- Keeps the 30-second T700i activity watchdog as the final fallback if an end packet is missing or unusable.
- Preserves the existing 60-second live/history filter, original session start timestamp, duration calculation, score, and last-brushing state.
- This release changed the forced-stop event rule but still required runtime investigation of the remaining stale-timestamp case addressed in v1.10.4.

## v1.10.1-final-verified — 2026-08-08

- Performed a full audit and cleanup of the final deployment package.
- Scoped T700i restart/session recovery logic to model `k0918.toothbrush.t700i` only.
- Removed the possibility that generic `motionSensor` child devices could be reset to `inactive` by toothbrush-specific initialization logic.
- Removed the stale `install-v1.9.2.ps1` and replaced it with the version-neutral `install.ps1`.
- Cleaned up PowerShell scripts to prefer `smartthings.cmd` when invoking SmartThings CLI on Windows.
- Removed stale toothbrush Custom Capability guidance from `sync-ui.ps1`.
- Separated the openmiio installer, MQTT/BLE diagnostic probe, and related operational documentation from the Edge deployment ZIP into a separate tools package.
- Removed the previous verification document from the deployment ZIP and changed the packaging so the latest verification report is distributed separately.
- Performed a final check for unused Lua modules and development leftovers.
- Passed 65 final static verification checks.

## v1.10.0-toothbrush-session — 2026-08-08

- Added **complete brushing-session tracking** for Xiaomi Toothbrush T700i.
- Stores the first brushing start timestamp from a live `type=0` start event.
- Repeated `type=0` advertisements during a brushing session preserve the original start time so the calculated session is not shortened.
- Calculates brushing duration from `end timestamp - start timestamp` on a live `type=1` end event.
- Stores the last brushing timestamp, score, and duration in persistent fields.
- Logs brushing duration in `MM:SS` format.
- Added the `BLE MQTT toothbrush session complete` completion log.
- Limits the maximum session length to 10 minutes so abnormally old events are not treated as valid sessions.
- Allows an active session from the previous 10 minutes to be recovered when the Edge Driver restarts during brushing.
- Historical retransmitted `type=1` events cannot terminate the current active brushing state.
- Verified on a real Hub runtime: start → end, `motionSensor active → inactive`, a 121-second (`02:01`) session calculation, and score update.

## v1.9.3-toothbrush-runtime-fix — 2026-08-08

- Fixed a runtime error that occurred on the first telemetry event after a T700i child device was created.
- The cause was a nested call such as:
  - `tonumber(child:get_field(...))`
- Because `get_field()` may return zero Lua values for a field that has not yet been stored, field access and `tonumber()` conversion were separated.
- When no previous brushing timestamp exists, the driver now safely uses `0`.
- T700i `pdid=6032`, EID `12291 / 0x3003`, and the 60-second live/history filter remain unchanged.
- Verified on a real Hub that brushing start/end, score, and battery events are processed correctly while the MQTT connection remains stable.

## v1.9.2-standard-toothbrush — 2026-08-08

- Removed the dependency on a new T700i Custom Capability.
- Changed the implementation to use only standard SmartThings capabilities in order to avoid Custom Capability API permission issues.
- Brushing start maps to `motionSensor=active`, and brushing end maps to `motionSensor=inactive`.
- Battery uses the standard `battery` capability.
- Last brushing timestamp and score remain available in internal driver state and logcat.
- Preserved `pdid=6032`, EID `12291 / 0x3003`, and the 60-second live/history filter.
- Preserved existing dynamic BLE temperature/humidity sensor support.

## v1.9.1-package-fix — 2026-08-08

- Added a pre-install script that creates/verifies the T700i Custom Capability before packaging the Edge Device Profile.
- Combined Capability → translation → Presentation → Edge packaging into one flow.
- Confirmed that Custom Capability API calls were rejected with HTTP 403 in the user environment.
- Based on that result, the next version removed the new toothbrush Custom Capability and switched to standard SmartThings capabilities.

## v1.9.0-toothbrush — 2026-08-08

- Added initial support for Xiaomi Toothbrush T700i.
- Identified T700i as `pdid=6032` and dynamically created an EDGE_CHILD device.
- Parsed MiBeacon EID `12291 / 0x3003` as a toothbrush event.
- Handled the event structure as follows:
  - `type=0`: brushing start
  - `type=1`: brushing end
  - embedded UTC timestamp
  - optional score byte
- Added a 60-second live/history filter based on the difference between the Gateway timestamp and the event timestamp.
- Prevented historical end events from incorrectly ending a brushing session that is currently in progress.
- Prepared the path for the standard MiBeacon battery EID `0x100A`.
- The initial design used a new Custom Capability for brushing state/last brushing/score, but a platform permission issue was discovered during packaging.

## v1.8.2-runtime-fix — 2026-08-08

- Fixed a runtime error caused by a remaining `gateway_for_device()` call after the dynamic Gateway transition.
- Removed the final static Gateway lookup path from `mqtt_ble.start()`.
- Separated MQTT applicability from the enabled state of `BLE via MQTT`.
- When `BLE via MQTT` is turned Off, the existing listener is now stopped/invalidated first.
- Preserved automatic BLE child creation and automatic parent selection.
- Preserved the final nine Gateway settings.
- Removed the dependency on bitwise operations in dynamic Gateway discovery DNI calculation and switched to modulo arithmetic.
- Kept `gateways.lua` and `known_ble.lua` removed.

## v1.8.1-auto-ble-parent — 2026-08-08

- Removed the dedicated BLE registration setting and changed supported BLE sensors to register automatically.
- Automatically detects `pdid=5860` BLE temperature/humidity devices from MQTT advertisements and creates EDGE_CHILD devices.
- If an existing BLE child with the same MAC is found, its existing parent and SmartThings name are preserved.
- Added automatic parent selection for new BLE children.
- Removed the dedicated BLE-host role and simplified the Gateway architecture.
- Rewrote `child_manager.lua` to fix structural problems introduced during the v1.8.0 transition.
- Reduced visible Gateway settings to the final nine items.

## v1.8.0-dynamic-gateway-ble — 2026-08-08

- Removed `src/gateways.lua`.
- Removed the fixed Gateway model/label/DNI table and switched to a dynamic Gateway architecture.
- Removed runtime dependency on a fixed Gateway count and static model inventory.
- Driver-created `xiaomi-gateway-*` LAN devices are now treated as generic Gateway parents.
- Existing legacy Gateway devices remain compatible.
- Gateway roles are now determined by user settings rather than model name.
- Any Gateway with `BLE via MQTT` enabled can act as the MQTT receiver without being locked to a specific model.
- Added generalized dynamic Gateway discovery.

## v1.7.9-dynamic-ble — 2026-08-08

- Removed `src/known_ble.lua`.
- Removed the fixed per-sensor NAME/DID/MAC inventory from runtime source.
- Changed temperature/humidity sensor identification to use `pdid=5860` and MAC from live MQTT BLE advertisements.
- Child keys are generated dynamically in `ble-<normalized MAC>` format.
- Existing children are reused by the same key, preserving their existing SmartThings names.
- New sensor default names use the MAC suffix.
- BLE KEY and sensor TOKEN are not used by runtime and are not bundled in the package.
- Authenticated `get_device_list` discovery skips BLE children to prevent duplicate creation.

## v1.7.8-final-verified — 2026-08-08

- Performed a static audit of scripts, the Lua dependency graph, Device Profiles, and package contents.
- Fixed an unnecessary coupling between BLE registration and the Auto child discovery setting.
- Blocked a path where BLE DIDs from authenticated `get_device_list` could be created again under another Gateway.
- Auto discovery and Zigbee polling timers are now created only when the corresponding feature is enabled.
- Removed unused Refresh/healthCheck handler paths from the Status-only Gateway.
- Removed legacy Telnet/openmiio-related Lua modules.
- Removed unused IP/Latency/LastSeen/Failures Custom Capability assets from the app and retained only Status.
- Removed Python `__pycache__` and unused manual child manifest code.
- Changed the MQTT/BLE diagnostic probe keepalive trigger from receive timeout to outbound idle time.

## v1.7.7-settings-labels — 2026-08-08

- Cleaned up Gateway setting labels to match operational terminology.
- Main changes:
  - `Gateway IP address` → `IP address`
  - `Gateway miIO token` → `TOKEN`
  - `Child state polling` → `Zigbee state polling`
  - `Child poll interval` → `Zigbee poll interval`
  - `BLE via mgl03 MQTT` → `BLE via MQTT`
- Removed `BLE MQTT topic` from the Settings UI.
- MQTT subscription topic is fixed internally to `#`.

## v1.7.6-selected-settings — 2026-08-08

- Reduced Gateway Settings to the items required for actual operation.
- Probe timeout is fixed internally to the runtime default of 3 seconds.
- Offline threshold is fixed to three failures.
- Preserved the existing behavior where child-device reachability follows parent Gateway state.
- Removed the previous manual child manifest setting/synchronization path.
- Preserved authenticated Auto discovery and Zigbee state polling.

## v1.7.4-temp-summary — 2026-08-08

- Improved the BLE temperature/humidity sensor Presentation so temperature and humidity appear together on the Dashboard.
- Added both `temperatureMeasurement` and `relativeHumidityMeasurement` to the Dashboard composite state.
- Detail View remains Temperature / Humidity / Battery.
- Changed the BLE child category to `TempHumiditySensor`.
- Renamed the profile to `xiaomi-child-temp-hum-v174` to force generation of a new Device Presentation.
- Existing BLE child Device IDs and parent relationships are preserved while metadata/profile is updated.

## v1.7.3-mqtt-keepalive-ui — 2026-08-08

- Simplified the Gateway SmartThings UI around the custom `Status` capability.
- Simplified the BLE temperature/humidity child UI to Temperature / Humidity / Battery.
- Gateway diagnostic information (IP, latency, last seen, failures) remains available to internal logic and logs but was removed from visible app capabilities.
- Changed MQTT keepalive from receive activity to **outbound idle time**.
- Sends PINGREQ every 15 seconds and requires PINGRESP within 10 seconds.
- Reduced MQTT receive timeout to 5 seconds so keepalive scheduling works reliably.
- Automatic reconnect after connection errors remains 3 seconds.
- The BLE parser ignores duplicate-prone `openmiio/log` copies and processes only `miio/report` and `central/report`.

## v1.7.2-mqtt-fieldfix — 2026-08-08

- Fixed a possible `tonumber()` error caused by an unset `device:get_field()` value on the first MQTT run.
- Stores the result of `get_field()` in a local variable first, handles nil, and only then calls `tonumber()`.
- Hardened `current_generation()` and `mqtt.status()` the same way.
- MQTT diagnostics, reconnect behavior, and BLE parsing were preserved.

## v1.7.1-mqtt-diagnostics — 2026-08-08

- Gateway Refresh restarts the BLE MQTT listener when applicable.
- Child Refresh can also request an MQTT restart on the parent Gateway.
- Added stage-by-stage diagnostic logging for the MQTT connection flow:
  - listener scheduling
  - TCP connect
  - MQTT CONNECT / CONNACK
  - SUBSCRIBE / SUBACK
  - BLE PUBLISH reception
  - reconnect / exception
- Wrapped each MQTT session in `pcall` so runtime exceptions are logged clearly.
- Changed active cosock socket storage from SmartThings device fields to a module-local runtime table.
- Automatic reconnect interval remains 3 seconds.

## v1.7.0-mqtt-ble — 2026-08-08

- Replaced the v1.6 Telnet/openmiio log polling design with a **local MQTT push architecture** for BLE delivery.
- Switched to the LAN MQTT Broker provided by openmiio/Mosquitto.
- Added pure-Lua MQTT 3.1.1 CONNECT/SUBSCRIBE/PUBLISH/PING handling based on cosock.
- Added automatic reconnect when the MQTT connection drops.
- Default subscription topic is `#`, allowing both `central/report` and `miio/report` to be received.
- Strictly parses `_async.ble_event` messages and preserves `frmCnt` duplicate suppression.
- Verified the real reception/conversion path for `pdid=5860` temperature/humidity BLE events.
- Removed the previous dependency on the mgl001 Gateway Key for receiving BLE values.

## v1.6.0-openmiio-ble — 2026-08-07

- Added the first openmiio-based path for receiving live values from BLE temperature/humidity sensors.
- Used Telnet to read Gateway openmiio trace logs without MQTT.
- Parsed `_async.ble_event`.
- Supported EIDs:
  - `19457`: temperature (float32 little-endian)
  - `19458`: humidity (uint8)
  - `18435`: battery (uint8)
- Prevented duplicate processing of the same `frmCnt` event.
- Accounted for different Telnet enablement methods depending on Gateway firmware.
- BLE bind keys and sensor TOKENs were not bundled in the driver.
- Preserved v1.5 Zigbee state polling.

## v1.5.0-zigbee-state — 2026-08-07

- Added polling for live properties of automatically registered Zigbee children.
- Uses authenticated miIO `get_device_prop_exp` calls.
- Added support for temperature/humidity values from Zigbee temperature/humidity model families.
- Converts the Gateway's 1/100 values to SmartThings °C/% values.
- Pressure can be queried/logged, but the profile at that time did not expose a matching capability to the app.
- Contact / Motion / Water devices retain registration profiles without inventing unverified polling values.
- Added `Child state polling` and `Child poll interval` settings.
- Poll interval defaults to 60 seconds with an allowed range of 30–3600 seconds.
- `get_device_list` inventory scan keeps its separate five-minute interval.

## v1.4.0-auto-child — 2026-08-07

- Expanded the manual child manifest design into **automatic child discovery/registration**.
- When a valid Gateway miIO TOKEN is available, calls `get_device_list` through authenticated UDP 54321 requests.
- Added AES-128-CBC-based authenticated miIO requests.
- Parses returned DID/model data to automatically select a device type and SmartThings EDGE_CHILD profile.
- Uses stable Xiaomi DIDs as child identifiers.
- Added a BLE fallback registration path to compensate for stock Gateway environments where direct BLE inventory was difficult to obtain at the time.
- Added `Auto child discovery` and Gateway TOKEN-related settings.
- Runs child discovery/synchronization during lifecycle events, settings changes, Refresh, and every 300 seconds.
- Classifies models into temp-humidity/contact/motion/water/generic profiles.
- This version automated device identity/model registration; live BLE telemetry delivery was not yet included.

## v1.3.0-child-r3 — 2026-08-07

- Fixed remaining SmartThings Device Profile `name` length violations.
- Shortened the preference name that was too long to `childFollowsGateway`.
- Updated `src/child_manager.lua` to use the new preference name.
- Revalidated all YAML `name` fields against SmartThings length limits.
- Preserved the preference maxLength and child profile name fixes from r1/r2.
- EDGE_CHILD registration logic and miIO network behavior were unchanged.

## v1.3.0-child-r2 — 2026-08-07

- Shortened/cleaned up child profile names to fit SmartThings profile-name length limits.
- Preserved the four child-manifest setting fields introduced in r1.
- Preserved EDGE_CHILD identity and duplicate-prevention logic.

## v1.3.0-child-r1 — 2026-08-07

- Split the `Child devices` manifest into four setting fields to account for SmartThings string-preference maximum length limits.
- Internally combines the fields into a single manifest.
- Supports roughly 1 KB of manually entered child-manifest data.
- Preserved temp-humidity/contact/motion/water/generic child types.

## v1.3.0-child — 2026-08-07

- Added the base framework for registering SmartThings `EDGE_CHILD` devices under a Xiaomi Gateway.
- Introduced the `type|key|label|model` manifest format for child definitions.
- Supported child types:
  - temp-humidity
  - contact
  - motion
  - water
  - generic
- Uses `parent_device_id` and `parent_assigned_child_key` to build parent-child relationships.
- Reuses the same child key during repeated synchronization to prevent duplicate device creation.
- Performs child synchronization on Gateway save/Refresh/driver restart.
- This stage provided only the child-registration framework; live sensor telemetry was not yet implemented.

## v1.2.6f-final — 2026-08-07

- Prepared the final deployment package based on the verified v1.2.6f build.
- Removed historical archives and previous setup wrappers.
- Removed V2 fallback and duplicate diagnostics sources, plus development templates, from the deployment package.
- Pre-applied the final five Custom Capability IDs to the Device Profile.
- Pre-generated `src/generated_capabilities.lua` so the driver can be packaged directly without a separate setup step.
- Added direct installation support with `smartthings edge:drivers:package . --install`.
- Retained only the final five capability definitions/Presentations and EN/KO translations.
- Added optional `sync-ui.ps1` so UI metadata can be reapplied.
- miIO runtime and network logic remained identical to v1.2.6f.

## v1.2.6f — 2026-08-07

- Finalized the multilingual (i18n) short-label configuration for the vertical five-card layout.
- Cleaned up the path that updates existing Custom Capability definitions and EN/KO translations.
- Presentation create/update remains safely rerunnable.
- If a previous fallback run changed the diagnostics implementation, setup restores the vertical diagnostics implementation.
- Removes leftover generated capability mappings from fallback mode.
- Preserved the final target UI order: `Status → IP → Latency → Last Seen → Failures`.

## v1.2.6e — 2026-08-07

- Improved Custom Capability translation and display-label synchronization.
- Capability-definition updates and EN/KO translation updates are performed before Presentation handling.
- Added a setup path that applies short UI labels consistently across multilingual environments.
- Preserved the existing vertical/fallback architecture.

## v1.2.6d — 2026-08-07

- Preserved the v1.2.6c network behavior and five vertical items while shortening app display names.
- Standardized display names to:
  - Status
  - IP
  - Latency
  - Last Seen
  - Failures
- Reused existing capability IDs and schemas instead of creating new Custom Capabilities.
- Improved setup usability so both `-Install` and `--install` forms are recognized.

## v1.2.6c — 2026-08-07

- Added recovery for partially created Custom Capabilities left by a previous failed installation.
- Hardened capability discovery order:
  1. Search the full capability list
  2. If namespace is known, query directly
  3. If not found, create it
  4. If HTTP 422 `already exists` is returned, extract and reuse the existing full ID from the response
- Allows remaining capabilities to be created even when the environment begins in a partially created state.
- Preserved Diagnostics V2 fallback and existing miIO network behavior.

## v1.2.6b — 2026-08-07

- Improved setup scripting so SmartThings Custom Capability creation failures are classified more clearly.
- Handles CLI stdout/stderr and exit codes separately.
- Checks the five vertical capabilities in sequence and switches to Diagnostics V2 fallback if any of them cannot be created.
- Made the install path deterministic even when platform permission/creation errors such as HTTP 403 occur.

## v1.2.6a — 2026-08-07

- Added handling for environments where the SmartThings API returns HTTP 403 while creating new Custom Capabilities.
- Uses the original v1.2.6 structure when creation of the five vertical capabilities is allowed.
- Added a fallback mode that reuses the existing `<namespace>.xiaomiGatewayDiagnosticsV2` when creation is rejected.
- Added `-ForceFallback` to select fallback mode from the beginning.
- Network/state-detection logic was unchanged.

## v1.2.6 — 2026-08-07

- Reworked diagnostic information in the SmartThings mobile detail view into a **five-card vertical layout**.
- Split the previous multi-attribute diagnostics capability into five single-attribute Custom Capabilities:
  - Status
  - IP
  - Latency
  - Last Seen
  - Failures
- Removed Gateway summary and Device ID from the mobile UI. Device ID remains available in logcat.
- Simplified Last Seen to KST `HH:MM:SS` format.
- Setup now creates/reuses the five capabilities, handles Presentation, generates the Device Profile, generates Lua mappings, and checks for duplicate profiles.

## v1.2.5 — 2026-08-07

- Introduced `xiaomiGatewayDiagnosticsV2` to avoid schema-cache problems in the previous diagnostics capability.
- The V2 capability contains these seven attributes from the start:
  - gatewayStatus
  - summary
  - gatewayIp
  - deviceId
  - latencyMs
  - lastSeen
  - failureCount
- The existing V1 capability was not deleted or modified.
- The app detail UI shows Status / Gateway / IP / Device ID / Latency / Last Seen / Failures.
- Existing Xiaomi miIO UDP 54321 network behavior was preserved.

## v1.2.4 — 2026-08-07

- Simplified diagnostic labels in the SmartThings detail view.
- Shortened major UI labels to IP / Device ID / Latency / Last Seen / Failures.
- Added `Gateway Status` and an `IP | latency` summary item.
- Changed the Dashboard to focus on `online / degraded / offline` state.
- Last Seen is recorded in Korean Standard Time as `YYYY-MM-DD HH:MM:SS`.
- `presenceSensor` remains for routine compatibility but was moved later in the primary UI order.

## v1.2.3 — 2026-08-07

- Improved SmartThings CLI compatibility and package verification in Diagnostics setup.
- Added a check that exactly one packageable profile exists under `profiles/`.
- Verifies that the expected profile is `xiaomi-gateway.yml`.
- Stabilized Capability Presentation create/update and namespace handling.

## v1.2.2 — 2026-08-07

- Updated the setup script to match SmartThings CLI 2.x Capability Presentation command syntax.
- Checks whether a Presentation already exists and selects create or update accordingly.
- Preserved a Presentation handling flow that supports both CLI 1.x and 2.x.
- Existing diagnostics capability is found and reused on reruns.

## v1.2.1 — 2026-08-07

- Detects SmartThings CLI version and handles Capability Presentation syntax differences between CLI 1.x and 2.x.
- Searches for and reuses an existing `xiaomiGatewayDiagnostics` capability, creating it only when absent.
- Detects the user namespace and builds the full Custom Capability ID.
- Improved setup-script error messages and rerun paths.
- The miIO health-check runtime itself remained based on the v1.2.0 design.

## v1.2.0 — 2026-08-07

- Added the standard SmartThings `healthCheck` capability.
- Connected the `healthCheck.ping` command to a real Xiaomi miIO probe.
- Added miIO round-trip latency measurement in milliseconds.
- Stores last successful response time, miIO Device ID, and consecutive failure count in persistent fields.
- Allows the consecutive-failure threshold for Offline to be configured from 1 to 5, defaulting to 3.
- Added a `degraded` state so a single UDP loss does not immediately mark the Gateway offline.
- Introduced an optional `xiaomiGatewayDiagnostics` Custom Capability for the SmartThings detail view.
- Added `setup-v1.2.ps1`, which creates/searches the capability in the account namespace and configures the profile.

## v1.1.0 — 2026-08-07

- Added the first **real Gateway health check** using Xiaomi miIO UDP `54321`.
- Added IPv4-address validation.
- SmartThings `online / offline` state now reflects actual miIO responses.
- `presenceSensor` also reflects the real communication result.
- Refresh triggers an immediate health check.
- Added periodic automatic health checks.
- Health-check interval is configurable from 30 to 3600 seconds.
- UDP probe timeout is configurable from 1 to 10 seconds.
- Logs the Device ID and timestamp returned by miIO.

## v1.0.0 — 2026-08-06

- Initial release.
- Started as a minimal Edge Driver for registering a Xiaomi Gateway as a SmartThings LAN device.
- Focused on registering the Gateway in the device list and maintaining basic identity information.
- In the initial version, `presenceSensor=present` represented SmartThings registration state rather than an actual network response.
- The following features were not included in the initial version:
  - real miIO network health checking
  - Zigbee/BLE child-device discovery
  - BLE sensor data
  - MQTT
  - openmiio
  - Telnet
  - Xiaomi Cloud login/token use

---

## Version progression summary

```text
v1.0.x   Gateway registration
   ↓
v1.1.x   Real miIO Health Check
   ↓
v1.2.x   Diagnostics/status/UI and Custom Capability cleanup
   ↓
v1.3.x   EDGE_CHILD framework
   ↓
v1.4.x   Automatic child discovery/registration
   ↓
v1.5.x   Zigbee state polling
   ↓
v1.6.x   openmiio-based live BLE values
   ↓
v1.7.x   MQTT BLE + keepalive + dynamic BLE transition
   ↓
v1.8.x   Dynamic Gateway / automatic BLE parent
   ↓
v1.9.x   Xiaomi Toothbrush T700i support
   ↓
v1.10.x  T700i session/forced-stop handling + Gateway status localization and final verification
```
