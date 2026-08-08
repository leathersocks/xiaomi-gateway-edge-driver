# v1.8.2 Runtime Fix 검증

## 수정 대상

- 동적 Gateway 전환 후 `mqtt_ble.lua`에 남아 있던 이전 Gateway 조회 호출 제거.
- MQTT On/Off lifecycle을 분리하여 Off 전환 시 기존 listener가 남지 않도록 수정.

## 검증 결과

- PASS — YAML/JSON/Python syntax
- PASS — Exact 9 visible settings: ['IP address', 'Health check interval', 'Auto child discovery', 'TOKEN', 'Zigbee state polling', 'Zigbee poll interval', 'BLE via MQTT', 'BLE MQTT broker IP', 'BLE MQTT port']
- PASS — No knownBleChildren preference
- PASS — No runtime reference: gateway_for_device
- PASS — No runtime reference: knownBleChildren
- PASS — No runtime reference: find_ble_host
- PASS — No runtime reference: BLE_HOST_MODEL
- PASS — No runtime reference: require "gateways"
- PASS — No runtime reference: require "known_ble"
- PASS — No runtime reference: lumi.gateway.mgl001
- PASS — No runtime reference: lumi.gateway.mgl03
- PASS — MQTT applicable checks gateway parent only
- PASS — MQTT enabled delegates to preference helper
- PASS — MQTT stop before disabled branch
- PASS — Automatic BLE resolver retained
- PASS — Keepalive retained
- PASS — All Lua modules reachable from init: []
- PASS — No gateways.lua
- PASS — No known_ble.lua
- PASS — No Python bytecode
- PASS — No __pycache__
- PASS — packageKey preserved
- PASS — No embedded 24-32 hex secret-like values: []

## 실제 Hub 검증

정적 검증은 완료했습니다. Hub 설치 후 MQTT connect/PING과 BLE temperature/humidity 이벤트를 logcat으로 확인해야 합니다.
