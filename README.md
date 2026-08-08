# Xiaomi Gateway Edge Driver v1.10.1-final-verified

실제 SmartThings Hub 런타임에서 검증된 v1.10.0 세션 버전을 기준으로 정리한 최종 배포 패키지입니다.

## 주요 기능

### Xiaomi Gateway

- miIO UDP 54321 상태 확인
- 온라인 / 성능저하 / 오프라인 상태 관리
- TOKEN 기반 선택적 자식 장치 자동 검색
- 선택적 Zigbee 온도/습도 상태 폴링
- 선택적 BLE over MQTT 수신

### BLE 장치

- `pdid 5860` 온도 / 습도 / 배터리 지원
- `pdid 6032` Xiaomi Toothbrush T700i 지원
- BLE 자식 장치 자동 등록
- 기존 BLE 자식의 부모 Gateway 관계 유지
- MQTT keepalive 및 자동 재연결

### Xiaomi Toothbrush T700i

- 양치 시작 이벤트 → `motionSensor = active`
- 양치 종료 이벤트 → `motionSensor = inactive`
- BLE 이벤트 내부 timestamp 해석
- 60초 기준 실시간 / 과거 이벤트 구분
- 반복되는 시작 이벤트에서도 최초 시작 시각 유지
- 양치 세션 시간 자동 계산
- 마지막 양치 시각 저장
- 양치 점수 저장
- 배터리 상태 처리
- Edge Driver 재시작 시 최대 10분 이내의 진행 중 세션 복원

## T700i 이벤트 처리

현재 확인된 T700i BLE 이벤트는 다음과 같습니다.

```text
pdid = 6032
EID  = 12291 / 0x3003
```

양치 시작:

```text
type = 0
motionSensor = active
```

양치 종료:

```text
type = 1
motionSensor = inactive
score = 양치 점수
```

배터리는 별도의 표준 MiBeacon 이벤트로 처리합니다.

```text
EID = 0x100A
```

과거에 저장된 양치 종료 이벤트가 다시 전송되더라도 현재 진행 중인 양치 상태를 종료시키지 않도록 다음 기준을 사용합니다.

```text
abs(gwts - event timestamp) <= 60초
    → 실시간 이벤트

60초 초과
    → 과거 기록
```

## 설치

Windows PowerShell에서 저장소 폴더로 이동한 후 다음을 실행합니다.

```powershell
.\install.ps1
```

또는 SmartThings CLI를 직접 사용할 수 있습니다.

```powershell
smartthings edge:drivers:package . --install
```

## Gateway 설정

현재 Gateway 설정 화면에는 다음 9개 항목만 표시됩니다.

1. IP address
2. Health check interval
3. Auto child discovery
4. TOKEN
5. Zigbee state polling
6. Zigbee poll interval
7. BLE via MQTT
8. BLE MQTT broker IP
9. BLE MQTT port

BLE MQTT를 사용하는 Gateway에서는 Mosquitto/openmiio가 실행 중이어야 합니다.

기본 MQTT 설정:

```text
Topic      #
Keepalive  30초
PINGREQ    15초
PINGRESP   10초 timeout
Reconnect  3초
```

## 선택적 UI 동기화

`sync-ui.ps1`은 기존에 생성되어 있는 다음 Custom Capability의 UI 정의를 다시 적용할 때만 사용합니다.

```text
locketforest19027.xiaomiGatewayStatus
```

일반적인 Edge Driver 설치에는 실행할 필요가 없습니다.

## 보안

- BLE 장치별 BLE KEY를 드라이버에 저장하지 않습니다.
- BLE 장치별 TOKEN을 드라이버에 저장하지 않습니다.
- 고정 DID/MAC 장치 목록을 소스에 포함하지 않습니다.
- Gateway TOKEN은 SmartThings 장치 설정값으로만 사용합니다.
- Gateway TOKEN은 logcat에 출력하지 않습니다.
- MQTT Broker는 신뢰할 수 있는 LAN/VLAN 내부에서만 사용하는 것을 권장합니다.
- 인증 없는 MQTT 1883 포트를 인터넷에 노출하지 마십시오.

## 최종 패키지 구성

### Edge Runtime

```text
config.yml
src/
profiles/
```

### Gateway Status UI 유지보수 파일

```text
capabilities/
translations/
sync-ui.ps1
```

### 설치 및 문서

```text
install.ps1
README.md
CHANGELOG.md
TOKEN-GUIDE.md
TOOTHBRUSH-SESSION.md
VERSION.txt
SHA256SUMS.txt
```

## 별도 관리 도구

SmartThings Edge Driver 런타임에 필요하지 않은 Gateway 관리 및 BLE 분석 도구는 최종 드라이버 패키지에서 분리했습니다.

```text
install-openmiio-mgl03-v5.py
mqtt-ble-probe-v2.py
OPENMIIO-SETUP.md
```

이 파일들은 관리자 PC에서 Gateway 설정 및 BLE MQTT 진단이 필요할 때만 사용합니다.

## 검증 상태

실제 SmartThings Hub에서 다음 항목이 확인되었습니다.

- Xiaomi Gateway miIO 상태 확인
- MQTT CONNECT / SUBSCRIBE
- MQTT PINGREQ / PINGRESP 유지
- BLE 온도/습도 이벤트 수신
- T700i 자동 자식 장치 등록
- T700i 양치 시작 → `motionSensor active`
- T700i 양치 종료 → `motionSensor inactive`
- 양치 시간 계산
- 양치 점수 처리
- 배터리 이벤트 처리

현재 버전:

```text
v1.10.1-final-verified
```
