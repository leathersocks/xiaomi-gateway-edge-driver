# 변경 이력

[English](CHANGELOG.en.md)

이 문서는 **Xiaomi Gateway Edge Driver**의 주요 변경 사항을 최초 `v1.0.0`부터 현재 버전까지 기록합니다.

- 실제로 생성된 패키지, README, 설정 스크립트, 검증 자료 및 런타임 확인 결과를 기준으로 정리했습니다.
- 시험·수정 빌드도 이후 버전에 영향을 준 경우 기록합니다.
- 자료에서 확인되지 않는 버전 번호는 임의로 만들지 않습니다. 따라서 `v1.7.5`처럼 확인 자료가 없는 버전은 목록에서 제외합니다.
- 모든 버전은 기존 드라이버를 업데이트할 수 있도록 `packageKey: xiaomi-gateway`를 유지하는 방향으로 개발되었습니다.

---

## v1.10.1-final-verified — 2026-08-08

- 최종 배포 패키지 전체 감사 및 정리를 수행했습니다.
- T700i 재시작/세션 복구 로직을 `k0918.toothbrush.t700i` 모델에만 적용하도록 범위를 제한했습니다.
- 일반 `motionSensor` 자식 장치가 칫솔 전용 초기화 로직에 의해 `inactive`로 초기화될 가능성을 제거했습니다.
- 오래된 `install-v1.9.2.ps1`을 제거하고 버전 독립적인 `install.ps1`로 교체했습니다.
- Windows에서 SmartThings CLI 실행 시 `smartthings.cmd`를 우선 사용하도록 PowerShell 스크립트를 정리했습니다.
- `sync-ui.ps1`에 남아 있던 사용하지 않는 칫솔 Custom Capability 안내를 제거했습니다.
- openmiio 설치 도구, MQTT/BLE 진단 프로브 및 관련 운영 문서를 Edge 배포 ZIP에서 분리해 별도 도구 패키지로 관리하도록 했습니다.
- 이전 검증 문서는 배포 ZIP에서 제거하고 최신 검증 보고서를 별도 제공하도록 정리했습니다.
- 사용되지 않는 Lua 모듈과 개발 잔여 파일이 없는지 최종 확인했습니다.
- 최종 정적 검증 65개 항목을 통과했습니다.

## v1.10.0-toothbrush-session — 2026-08-08

- Xiaomi Toothbrush T700i의 **완전한 양치 세션 추적**을 추가했습니다.
- 실시간 `type=0` 시작 이벤트에서 최초 양치 시작 시각을 저장합니다.
- 양치 중 반복되는 `type=0` 광고가 와도 최초 시작 시각을 유지해 세션 시간이 짧아지지 않도록 했습니다.
- 실시간 `type=1` 종료 이벤트에서 `종료 시각 - 시작 시각`으로 양치 시간을 계산합니다.
- 마지막 양치 시각, 점수, 양치 시간을 persistent field에 저장합니다.
- 양치 시간을 `MM:SS` 형식으로 로그에 표시합니다.
- `BLE MQTT toothbrush session complete` 완료 로그를 추가했습니다.
- 비정상적으로 오래된 이벤트가 세션으로 계산되지 않도록 최대 세션 길이를 10분으로 제한했습니다.
- Edge 드라이버가 양치 도중 재시작된 경우 최근 10분 이내의 활성 세션을 복구할 수 있도록 했습니다.
- 오래된 `type=1` 재전송 이벤트는 현재 진행 중인 양치 상태를 종료시키지 않습니다.
- 실제 Hub 런타임에서 시작 → 종료, `motionSensor active → inactive`, 121초(`02:01`) 세션 계산 및 점수 갱신을 확인했습니다.

## v1.9.3-toothbrush-runtime-fix — 2026-08-08

- T700i 자식 장치 생성 후 첫 telemetry 처리에서 발생하던 런타임 오류를 수정했습니다.
- 원인은 다음과 같은 중첩 호출이었습니다.
  - `tonumber(child:get_field(...))`
- 값이 아직 저장되지 않은 field에서 `get_field()`가 zero Lua values를 반환할 수 있는 상황을 고려해 field 조회와 `tonumber()` 변환을 분리했습니다.
- 이전 양치 시각이 없으면 안전하게 `0`을 사용하도록 수정했습니다.
- T700i `pdid=6032`, EID `12291 / 0x3003`, 60초 live/history 필터는 그대로 유지했습니다.
- 실제 Hub에서 양치 시작/종료, 점수 및 배터리 이벤트가 정상 처리되고 MQTT 연결이 유지되는 것을 확인했습니다.

## v1.9.2-standard-toothbrush — 2026-08-08

- T700i용 신규 Custom Capability 의존성을 제거했습니다.
- SmartThings Custom Capability API 권한 문제를 우회하기 위해 표준 capability만 사용하도록 변경했습니다.
- 양치 시작은 `motionSensor=active`, 양치 종료는 `motionSensor=inactive`로 매핑했습니다.
- 배터리는 표준 `battery` capability를 사용합니다.
- 마지막 양치 시각과 점수는 드라이버 내부 상태 및 logcat에 유지하도록 했습니다.
- `pdid=6032`, EID `12291 / 0x3003`, 60초 live/history 필터를 유지했습니다.
- 기존 동적 BLE 온습도 센서 지원을 그대로 보존했습니다.

## v1.9.1-package-fix — 2026-08-08

- T700i Custom Capability를 Edge Device Profile보다 먼저 생성/검증하기 위한 사전 설치 스크립트를 추가했습니다.
- Capability → 번역 → Presentation → Edge 패키징 순서를 한 번에 처리하도록 구성했습니다.
- 사용자 환경에서 Custom Capability API 호출이 HTTP 403으로 거부되는 것을 확인했습니다.
- 이 결과를 바탕으로 다음 버전에서 신규 칫솔 Custom Capability를 제거하고 SmartThings 표준 capability 방식으로 전환했습니다.

## v1.9.0-toothbrush — 2026-08-08

- Xiaomi Toothbrush T700i 지원을 최초 추가했습니다.
- T700i를 `pdid=6032`으로 식별하고 동적으로 EDGE_CHILD 장치를 생성하도록 했습니다.
- MiBeacon EID `12291 / 0x3003`을 칫솔 이벤트로 파싱했습니다.
- 이벤트 구조를 다음과 같이 처리했습니다.
  - `type=0`: 양치 시작
  - `type=1`: 양치 종료
  - 내장 UTC timestamp
  - 선택적 score 바이트
- Gateway timestamp와 이벤트 timestamp 차이를 이용한 60초 live/history 필터를 추가했습니다.
- 과거 종료 이벤트가 현재 진행 중인 양치 상태를 잘못 종료시키는 문제를 방지했습니다.
- 표준 MiBeacon 배터리 EID `0x100A` 수신 경로를 준비했습니다.
- 초기 설계에서는 양치 상태/마지막 양치/점수를 표시하기 위한 신규 Custom Capability를 사용했으나 패키징 단계에서 플랫폼 권한 문제가 확인됐습니다.

## v1.8.2-runtime-fix — 2026-08-08

- 동적 Gateway 전환 후 남아 있던 `gateway_for_device()` 호출로 발생한 런타임 오류를 수정했습니다.
- `mqtt_ble.start()`에서 마지막 정적 Gateway 조회 경로를 제거했습니다.
- MQTT 적용 가능 여부와 `BLE via MQTT` 활성화 상태를 분리했습니다.
- `BLE via MQTT`를 Off로 변경하면 기존 listener를 먼저 중지/무효화하도록 수정했습니다.
- 자동 BLE 자식 생성과 자동 parent 선택을 유지했습니다.
- Gateway 설정은 9개 항목을 그대로 유지했습니다.
- 동적 Gateway discovery의 DNI 계산에서 비트 연산 의존성을 제거하고 modulo 계산을 사용했습니다.
- `gateways.lua`, `known_ble.lua` 제거 상태를 유지했습니다.

## v1.8.1-auto-ble-parent — 2026-08-08

- BLE 등록 전용 설정을 제거하고 지원되는 BLE 센서를 자동 등록하도록 변경했습니다.
- `pdid=5860` BLE 온습도 장치를 MQTT 광고에서 자동 감지해 EDGE_CHILD로 생성하도록 했습니다.
- 동일 MAC의 기존 BLE 자식이 있으면 기존 parent와 SmartThings 이름을 유지하도록 했습니다.
- 신규 BLE 자식의 parent를 자동 선택하는 로직을 추가했습니다.
- BLE host 전용 역할을 제거하고 Gateway 구조를 단순화했습니다.
- v1.8.0 전환 과정에서 생긴 `child_manager.lua` 구조 문제를 재작성해 수정했습니다.
- Gateway 사용자 설정을 최종 9개 항목으로 줄였습니다.

## v1.8.0-dynamic-gateway-ble — 2026-08-08

- `src/gateways.lua`를 제거했습니다.
- 고정 Gateway 모델/라벨/DNI 테이블을 제거하고 동적 Gateway 구조로 전환했습니다.
- 기존 정적 Gateway 개수 및 모델 인벤토리에 대한 런타임 의존성을 제거했습니다.
- 드라이버가 생성한 `xiaomi-gateway-*` LAN 장치를 일반적인 Gateway parent로 처리하도록 했습니다.
- 기존 legacy Gateway 장치도 계속 호환되도록 했습니다.
- Gateway 역할을 모델명이 아니라 사용자 설정에 따라 결정하도록 변경했습니다.
- `BLE via MQTT`가 켜진 Gateway라면 특정 모델에 고정하지 않고 MQTT receiver가 될 수 있도록 했습니다.
- 일반화된 동적 Gateway discovery를 추가했습니다.

## v1.7.9-dynamic-ble — 2026-08-08

- `src/known_ble.lua`를 제거했습니다.
- 런타임 소스에 있던 센서별 고정 이름/DID/MAC 인벤토리를 제거했습니다.
- MQTT BLE 광고의 `pdid=5860`과 MAC을 이용해 온습도 센서를 동적으로 식별하도록 변경했습니다.
- 자식 키를 `ble-<normalized MAC>` 형식으로 동적으로 생성합니다.
- 기존 자식은 같은 키로 재사용하고 기존 SmartThings 이름도 유지합니다.
- 새 센서의 기본 이름은 MAC suffix를 이용하도록 했습니다.
- BLE KEY와 센서 TOKEN은 런타임에서 사용하지 않으며 패키지에 포함하지 않습니다.
- 인증 `get_device_list` 경로에서는 BLE 자식을 건너뛰어 중복 생성을 방지했습니다.

## v1.7.8-final-verified — 2026-08-08

- 스크립트, Lua dependency graph, Device Profile 및 패키지 내용에 대한 정적 감사를 수행했습니다.
- BLE 등록이 Auto child discovery 설정과 불필요하게 결합되어 있던 문제를 수정했습니다.
- 인증 `get_device_list`의 BLE DID가 다른 Gateway 아래에 중복 생성될 수 있는 경로를 차단했습니다.
- Auto discovery와 Zigbee polling 타이머를 해당 기능이 활성화된 경우에만 생성하도록 수정했습니다.
- Status-only Gateway에서 더 이상 사용하지 않는 Refresh/healthCheck handler 경로를 제거했습니다.
- legacy Telnet/openmiio 관련 Lua 모듈을 정리했습니다.
- 앱에서 더 이상 사용하지 않는 IP/Latency/LastSeen/Failures Custom Capability 자산을 제거하고 Status만 유지했습니다.
- Python `__pycache__` 및 사용하지 않는 manual child manifest 코드를 제거했습니다.
- MQTT/BLE 진단 프로브의 keepalive 기준을 수신 timeout이 아니라 outbound idle 기준으로 수정했습니다.

## v1.7.7-settings-labels — 2026-08-08

- Gateway 설정 표시명을 실제 운영 용어에 맞게 정리했습니다.
- 주요 변경:
  - `Gateway IP address` → `IP address`
  - `Gateway miIO token` → `TOKEN`
  - `Child state polling` → `Zigbee state polling`
  - `Child poll interval` → `Zigbee poll interval`
  - `BLE via mgl03 MQTT` → `BLE via MQTT`
- `BLE MQTT topic` 설정을 UI에서 제거했습니다.
- MQTT 구독 topic은 런타임 내부에서 `#`으로 고정했습니다.

## v1.7.6-selected-settings — 2026-08-08

- Gateway Settings를 실제 운영에 필요한 항목 중심으로 축소했습니다.
- Probe timeout은 런타임 내부 기본값 3초로 고정했습니다.
- Offline 판정 threshold는 3회 실패로 고정했습니다.
- 자식 장치의 reachability가 parent Gateway 상태를 따르는 기존 동작을 유지했습니다.
- 이전 manual child manifest 설정/동기화 경로를 제거했습니다.
- 인증 Auto discovery와 Zigbee state polling은 유지했습니다.

## v1.7.4-temp-summary — 2026-08-08

- BLE 온습도 센서 Dashboard에서 온도와 습도가 함께 보이도록 Presentation을 개선했습니다.
- Dashboard composite 상태에 `temperatureMeasurement`와 `relativeHumidityMeasurement`를 함께 표시하도록 했습니다.
- Detail View는 Temperature / Humidity / Battery 3개 항목으로 유지했습니다.
- BLE 자식 category를 `TempHumiditySensor`로 변경했습니다.
- 새로운 Device Presentation 생성을 위해 프로필명을 `xiaomi-child-temp-hum-v174`로 변경했습니다.
- 기존 BLE 자식의 Device ID와 parent 관계를 유지한 채 metadata/profile을 갱신하도록 했습니다.

## v1.7.3-mqtt-keepalive-ui — 2026-08-08

- Gateway SmartThings UI를 Custom `Status` 중심으로 단순화했습니다.
- BLE 온습도 자식 UI를 Temperature / Humidity / Battery 중심으로 정리했습니다.
- Gateway 진단 정보(IP, latency, last seen, failures)는 내부 로직과 로그에는 유지하되 앱 상세 capability에서는 제거했습니다.
- MQTT keepalive를 수신 유무가 아니라 **송신 idle 시간** 기준으로 변경했습니다.
- 15초마다 PINGREQ를 전송하고 10초 이내 PINGRESP를 요구하도록 했습니다.
- MQTT receive timeout을 5초로 줄여 keepalive 스케줄이 안정적으로 동작하도록 했습니다.
- 연결 오류 후 자동 재접속은 3초로 유지했습니다.
- 중복 로그 복사본인 `openmiio/log`는 무시하고 `miio/report`, `central/report`만 BLE parser에서 처리하도록 했습니다.

## v1.7.2-mqtt-fieldfix — 2026-08-08

- 첫 MQTT 실행 시 `device:get_field()`의 미설정 값 때문에 발생할 수 있던 `tonumber()` 오류를 수정했습니다.
- `get_field()` 결과를 먼저 local 변수에 저장한 뒤 nil 여부를 처리하고 `tonumber()`를 호출하도록 변경했습니다.
- `current_generation()`과 `mqtt.status()`를 동일한 방식으로 보강했습니다.
- MQTT 진단, reconnect, BLE 파싱 동작은 유지했습니다.

## v1.7.1-mqtt-diagnostics — 2026-08-08

- Gateway Refresh 시 적용 가능한 경우 BLE MQTT listener를 재시작하도록 했습니다.
- 자식 Refresh에서도 parent Gateway의 MQTT 재시작을 요청할 수 있도록 했습니다.
- MQTT 연결 과정을 단계별로 로그에 기록하도록 진단 기능을 추가했습니다.
  - listener scheduling
  - TCP connect
  - MQTT CONNECT / CONNACK
  - SUBSCRIBE / SUBACK
  - BLE PUBLISH 수신
  - reconnect / exception
- 각 MQTT session을 `pcall`로 감싸 런타임 예외를 명확하게 기록하도록 했습니다.
- 활성 cosock socket을 SmartThings device field가 아니라 module-local runtime table에 보관하도록 변경했습니다.
- 자동 reconnect 간격은 3초로 유지했습니다.

## v1.7.0-mqtt-ble — 2026-08-08

- v1.6의 Telnet/openmiio 로그 polling 방식 대신 **로컬 MQTT push 방식**으로 BLE 전달 구조를 전환했습니다.
- openmiio/Mosquitto가 제공하는 LAN MQTT broker를 사용하도록 했습니다.
- cosock 기반 순수 Lua MQTT 3.1.1 CONNECT/SUBSCRIBE/PUBLISH/PING 처리를 추가했습니다.
- MQTT 연결이 끊어지면 자동 reconnect하도록 했습니다.
- 구독 topic 기본값을 `#`으로 사용해 `central/report`, `miio/report`를 모두 받을 수 있도록 했습니다.
- `_async.ble_event`만 엄격하게 파싱하고 `frmCnt` 중복 억제를 유지했습니다.
- `pdid=5860` 온습도 BLE 이벤트의 실제 수신/변환 경로를 확인했습니다.
- BLE 값 수신을 위해 mgl001 Gateway Key에 의존하던 구조를 제거했습니다.

## v1.6.0-openmiio-ble — 2026-08-07

- BLE 온습도 센서의 실시간 값을 얻기 위한 최초 openmiio 기반 경로를 추가했습니다.
- MQTT 없이 Gateway의 openmiio trace 로그를 Telnet을 통해 읽는 구조를 사용했습니다.
- `_async.ble_event`를 파싱했습니다.
- 지원 EID:
  - `19457`: 온도(float32 little-endian)
  - `19458`: 습도(uint8)
  - `18435`: 배터리(uint8)
- 동일 `frmCnt` 이벤트를 중복 처리하지 않도록 했습니다.
- Gateway firmware에 따라 Telnet 활성화 방식이 다른 점을 고려했습니다.
- BLE bind key와 센서 TOKEN은 드라이버에 포함하지 않았습니다.
- v1.5의 Zigbee state polling 기능을 그대로 유지했습니다.

## v1.5.0-zigbee-state — 2026-08-07

- 자동 등록된 Zigbee 자식의 실시간 속성을 조회하는 polling 기능을 추가했습니다.
- 인증 miIO `get_device_prop_exp` 호출을 사용했습니다.
- Zigbee 온습도 계열 모델의 temperature/humidity 값을 지원했습니다.
- Gateway가 반환하는 1/100 단위 값을 SmartThings °C/% 값으로 변환했습니다.
- pressure 값은 조회/로그할 수 있지만 당시 프로필에 capability가 없어 앱 이벤트로는 노출하지 않았습니다.
- Contact / Motion / Water 장치는 확인되지 않은 polling 값을 임의로 만들지 않고 등록 프로필만 유지했습니다.
- `Child state polling`, `Child poll interval` 설정을 추가했습니다.
- Poll interval 기본값은 60초이며 허용 범위는 30~3600초로 구성했습니다.
- `get_device_list` inventory scan은 별도 5분 주기를 유지했습니다.

## v1.4.0-auto-child — 2026-08-07

- 수동 자식 manifest에서 **자동 자식 검색/등록** 구조로 확장했습니다.
- 유효한 Gateway miIO TOKEN이 있으면 UDP 54321 인증 요청으로 `get_device_list`를 호출하도록 했습니다.
- AES-128-CBC 기반 인증 miIO 요청을 추가했습니다.
- 반환된 DID/model을 파싱해 장치 유형과 SmartThings EDGE_CHILD 프로필을 자동 선택하도록 했습니다.
- 안정적인 Xiaomi DID를 자식 식별에 사용했습니다.
- 당시 stock Gateway에서 직접 BLE inventory를 얻기 어려운 환경을 보완하기 위한 BLE fallback 등록 경로를 제공했습니다.
- `Auto child discovery`, Gateway TOKEN 관련 설정을 추가했습니다.
- 자식 검색/동기화를 lifecycle, 설정 변경, Refresh 및 300초 주기로 실행했습니다.
- 모델을 temp-humidity/contact/motion/water/generic 프로필로 분류하도록 했습니다.
- 이 버전은 장치 identity/model 자동 등록 단계이며 BLE 실시간 telemetry 전달은 아직 포함하지 않았습니다.

## v1.3.0-child-r3 — 2026-08-07

- SmartThings Device Profile의 남아 있던 `name` 길이 제한 위반을 수정했습니다.
- 길이가 너무 길었던 preference 이름을 `childFollowsGateway`로 축약했습니다.
- `src/child_manager.lua`를 새 preference 이름에 맞게 수정했습니다.
- 모든 YAML `name` 필드가 SmartThings 허용 길이에 맞는지 다시 검증했습니다.
- r1/r2에서 수정한 preference maxLength와 child profile 이름 제한을 그대로 유지했습니다.
- EDGE_CHILD 등록 로직과 miIO 네트워크 동작에는 변경이 없습니다.

## v1.3.0-child-r2 — 2026-08-07

- SmartThings 프로필 이름 길이 제한에 맞추기 위해 child profile 이름을 축약/정리했습니다.
- r1에서 분리한 4개의 자식 manifest 설정 구조를 유지했습니다.
- EDGE_CHILD 식별 및 중복 방지 로직은 유지했습니다.

## v1.3.0-child-r1 — 2026-08-07

- SmartThings string preference의 최대 길이 제한을 고려해 `Child devices` manifest를 4개 설정 필드로 분리했습니다.
- 여러 필드를 내부에서 하나의 manifest처럼 합쳐 처리하도록 했습니다.
- 약 1KB 규모의 수동 자식 manifest를 입력할 수 있도록 했습니다.
- temp-humidity/contact/motion/water/generic 자식 유형을 유지했습니다.

## v1.3.0-child — 2026-08-07

- Xiaomi Gateway 아래에 SmartThings `EDGE_CHILD` 장치를 등록하는 기본 프레임워크를 추가했습니다.
- 자식 정의 형식으로 `type|key|label|model` manifest를 도입했습니다.
- 지원 child 유형:
  - temp-humidity
  - contact
  - motion
  - water
  - generic
- `parent_device_id`와 `parent_assigned_child_key`를 이용해 parent-child 관계를 구성했습니다.
- 반복 동기화 시 동일 child key를 재사용해 중복 장치 생성을 방지했습니다.
- Gateway 저장/Refresh/드라이버 재시작에서 자식 동기화를 수행했습니다.
- 이 단계에서는 자식 등록 프레임워크만 제공했으며 실시간 센서 telemetry는 아직 구현하지 않았습니다.

## v1.2.6f-final — 2026-08-07

- 검증된 v1.2.6f를 기준으로 최종 배포용 패키지를 정리했습니다.
- 과거 archive 및 이전 setup wrapper를 제거했습니다.
- V2 fallback 및 중복 diagnostics 소스, 개발용 template을 배포 패키지에서 제거했습니다.
- 최종 5개 Custom Capability ID를 Device Profile에 미리 반영했습니다.
- `src/generated_capabilities.lua`를 미리 생성해 별도 setup 없이 직접 패키징할 수 있도록 했습니다.
- `smartthings edge:drivers:package . --install` 직접 설치를 지원했습니다.
- 최종 5개 capability 정의/Presentation 및 EN/KO 번역만 유지했습니다.
- UI metadata를 다시 적용할 수 있도록 선택적 `sync-ui.ps1`을 추가했습니다.
- miIO 런타임 및 네트워크 로직은 v1.2.6f와 동일하게 유지했습니다.

## v1.2.6f — 2026-08-07

- 세로 5카드 구조의 다국어(i18n) 짧은 라벨 구성을 마무리했습니다.
- 기존 Custom Capability 정의와 EN/KO 번역을 업데이트하는 경로를 정리했습니다.
- Presentation create/update를 재실행 가능하도록 유지했습니다.
- 이전 fallback 실행으로 diagnostics 구현이 변경된 경우 vertical diagnostics 구현을 다시 복구하도록 했습니다.
- fallback용 generated capability mapping이 남아 있으면 정리하도록 했습니다.
- 최종 목표 UI를 `Status → IP → Latency → Last Seen → Failures` 순으로 유지했습니다.

## v1.2.6e — 2026-08-07

- Custom Capability의 번역 및 표시 라벨 동기화 기능을 강화했습니다.
- Capability 정의 업데이트와 EN/KO translation 업데이트를 Presentation 처리 전에 수행하도록 정리했습니다.
- 짧은 UI 라벨을 다국어 환경에서도 일관되게 적용하는 setup 경로를 추가했습니다.
- 기존 vertical/fallback 구조는 유지했습니다.

## v1.2.6d — 2026-08-07

- v1.2.6c의 네트워크 및 5개 세로 항목 구조를 유지하면서 앱 표시 이름을 짧게 정리했습니다.
- 표시 이름을 다음으로 통일했습니다.
  - Status
  - IP
  - Latency
  - Last Seen
  - Failures
- 새 Custom Capability를 생성하지 않고 기존 capability ID와 schema를 재사용했습니다.
- `-Install`뿐 아니라 `--install` 형식도 인식하도록 setup 사용성을 개선했습니다.

## v1.2.6c — 2026-08-07

- 이전 실패한 설치에서 일부 Custom Capability만 생성된 상태를 복구할 수 있도록 했습니다.
- Capability 탐색 순서를 강화했습니다.
  1. 전체 capability 목록 검색
  2. namespace를 알고 있으면 직접 조회
  3. 없으면 생성
  4. HTTP 422 `already exists`이면 응답에서 기존 전체 ID를 추출해 재사용
- 부분 생성 상태에서도 나머지 capability 생성을 계속할 수 있도록 했습니다.
- Diagnostics V2 fallback과 기존 miIO 네트워크 기능을 유지했습니다.

## v1.2.6b — 2026-08-07

- SmartThings Custom Capability 생성 실패를 더 명확히 판정하도록 setup 스크립트를 보강했습니다.
- CLI stdout/stderr와 종료 코드를 분리해 처리하도록 했습니다.
- 5개 세로 capability를 순차적으로 확인하고, 하나라도 생성할 수 없으면 Diagnostics V2 fallback으로 전환하도록 했습니다.
- 403 등 플랫폼 권한/생성 오류가 있어도 설치 경로를 결정적으로 선택하도록 개선했습니다.

## v1.2.6a — 2026-08-07

- 신규 Custom Capability 생성 시 SmartThings API가 HTTP 403을 반환하는 환경을 처리했습니다.
- 5개 세로 capability 생성이 허용되면 기존 v1.2.6 구조를 사용합니다.
- 생성이 거부되면 기존 `<namespace>.xiaomiGatewayDiagnosticsV2`를 재사용하는 fallback 모드를 추가했습니다.
- 처음부터 fallback을 선택할 수 있는 `-ForceFallback` 옵션을 제공했습니다.
- 네트워크/상태 판정 로직은 변경하지 않았습니다.

## v1.2.6 — 2026-08-07

- SmartThings 모바일 상세 화면의 진단 정보를 **세로 5카드** 형태로 개편했습니다.
- 기존 하나의 multi-attribute diagnostics capability를 다음 5개의 단일 속성 Custom Capability로 분리했습니다.
  - Status
  - IP
  - Latency
  - Last Seen
  - Failures
- Gateway summary와 Device ID를 모바일 UI에서 제거했습니다. Device ID는 logcat에 유지했습니다.
- Last Seen을 KST `HH:MM:SS` 형식으로 단순화했습니다.
- setup 스크립트가 5개 capability 생성/재사용, Presentation 처리, Device Profile 생성, Lua mapping 생성 및 profile 중복 검사를 수행하도록 했습니다.

## v1.2.5 — 2026-08-07

- 기존 diagnostics capability의 schema cache 문제를 피하기 위해 `xiaomiGatewayDiagnosticsV2`를 도입했습니다.
- V2 capability는 처음부터 다음 7개 속성을 포함하도록 했습니다.
  - gatewayStatus
  - summary
  - gatewayIp
  - deviceId
  - latencyMs
  - lastSeen
  - failureCount
- 기존 V1 capability는 삭제하거나 변경하지 않았습니다.
- 앱 상세 UI에서 Status / Gateway / IP / Device ID / Latency / Last Seen / Failures를 표시하도록 했습니다.
- 기존 Xiaomi miIO UDP 54321 네트워크 동작은 유지했습니다.

## v1.2.4 — 2026-08-07

- SmartThings 상세 화면의 진단 항목 이름을 간결하게 정리했습니다.
- 주요 UI 명칭을 IP / Device ID / Latency / Last Seen / Failures 형태로 축약했습니다.
- `Gateway Status`와 `IP | latency` 요약 항목을 추가했습니다.
- Dashboard를 `online / degraded / offline` 상태 중심으로 변경했습니다.
- Last Seen을 한국시간 `YYYY-MM-DD HH:MM:SS` 형식으로 기록하도록 했습니다.
- `presenceSensor`는 루틴 호환성을 위해 유지하되 주요 UI 순서에서는 뒤로 이동했습니다.

## v1.2.3 — 2026-08-07

- Diagnostics setup의 SmartThings CLI 호환성 및 패키징 검증을 강화했습니다.
- `profiles/` 아래에 패키징 가능한 프로필이 정확히 하나인지 확인하는 검사를 추가했습니다.
- 예상 프로필이 `xiaomi-gateway.yml`인지 확인하도록 했습니다.
- Capability Presentation create/update 및 namespace 처리 흐름을 안정화했습니다.

## v1.2.2 — 2026-08-07

- SmartThings CLI 2.x의 Capability Presentation 명령 형식에 맞춰 setup 스크립트를 수정했습니다.
- 기존 Presentation 존재 여부를 확인해 create 또는 update를 선택하도록 했습니다.
- CLI 1.x와 2.x를 모두 고려한 Presentation 처리 흐름을 유지했습니다.
- 재실행 시 기존 diagnostics capability를 찾아 재사용하도록 했습니다.

## v1.2.1 — 2026-08-07

- SmartThings CLI 버전을 감지해 CLI 1.x/2.x의 Capability Presentation 문법 차이를 처리하도록 했습니다.
- 기존 `xiaomiGatewayDiagnostics` capability를 검색해 재사용하고 없으면 생성하도록 했습니다.
- 사용자 namespace를 확인해 완전한 Custom Capability ID를 구성하도록 했습니다.
- setup 스크립트의 오류 메시지와 재실행 경로를 보강했습니다.
- miIO 상태 확인 런타임 자체는 v1.2.0 구조를 유지했습니다.

## v1.2.0 — 2026-08-07

- SmartThings 표준 `healthCheck` capability를 추가했습니다.
- `healthCheck.ping` 명령을 실제 Xiaomi miIO probe와 연결했습니다.
- miIO 왕복 latency(ms) 측정을 추가했습니다.
- 마지막 정상 응답 시각, miIO Device ID, 연속 실패 횟수를 persistent field로 저장했습니다.
- Offline 판정 연속 실패 횟수를 1~5회 범위로 설정할 수 있도록 했으며 기본값은 3회입니다.
- 1회 UDP 손실만으로 offline이 되지 않도록 `degraded` 상태를 추가했습니다.
- SmartThings 상세 화면을 위한 선택적 `xiaomiGatewayDiagnostics` Custom Capability를 도입했습니다.
- 계정 namespace에서 capability를 생성/검색하고 profile을 구성하는 `setup-v1.2.ps1`을 추가했습니다.

## v1.1.0 — 2026-08-07

- Xiaomi miIO UDP `54321`을 이용한 **실제 Gateway health check**를 최초 추가했습니다.
- 입력된 IPv4 주소를 검증하도록 했습니다.
- 실제 miIO 응답에 따라 SmartThings `online / offline` 상태를 변경하도록 했습니다.
- `presenceSensor` 값도 실제 통신 결과를 반영하도록 변경했습니다.
- Refresh 실행 시 즉시 health check를 수행하도록 했습니다.
- 주기적인 자동 health check를 추가했습니다.
- Health check 주기를 30~3600초 범위에서 설정하도록 했습니다.
- UDP probe timeout을 1~10초 범위에서 설정하도록 했습니다.
- miIO 응답의 Device ID 및 timestamp를 로그에 기록하도록 했습니다.

## v1.0.0 — 2026-08-06

- 최초 릴리스입니다.
- Xiaomi Gateway를 SmartThings LAN 장치로 등록하기 위한 최소 Edge Driver로 시작했습니다.
- Gateway를 장치 목록에 등록하고 기본 식별 정보를 관리하는 기능에 집중했습니다.
- 초기 버전의 `presenceSensor=present`는 실제 네트워크 응답이 아니라 SmartThings 등록 상태를 의미했습니다.
- 다음 기능은 초기 버전에서 포함하지 않았습니다.
  - 실제 miIO 네트워크 상태 검사
  - Zigbee/BLE 자식 장치 검색
  - BLE 센서 데이터
  - MQTT
  - openmiio
  - Telnet
  - Xiaomi Cloud 로그인/토큰 사용

---

## 버전 흐름 요약

```text
v1.0.x   Gateway 등록
   ↓
v1.1.x   실제 miIO Health Check
   ↓
v1.2.x   진단/상태/UI 및 Custom Capability 정비
   ↓
v1.3.x   EDGE_CHILD 프레임워크
   ↓
v1.4.x   자동 자식 검색/등록
   ↓
v1.5.x   Zigbee 상태 polling
   ↓
v1.6.x   openmiio 기반 BLE 실시간 값
   ↓
v1.7.x   MQTT BLE + keepalive + 동적 BLE 전환
   ↓
v1.8.x   동적 Gateway / 자동 BLE parent
   ↓
v1.9.x   Xiaomi Toothbrush T700i 지원
   ↓
v1.10.x  양치 세션 추적 및 최종 배포 검증
```
