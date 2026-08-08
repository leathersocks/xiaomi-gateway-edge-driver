# Xiaomi Gateway SmartThings Edge Driver

Xiaomi Gateway를 SmartThings Hub에 **LAN 장치로 등록**하고, Gateway 상태 확인과 Xiaomi Zigbee/BLE 자식 장치를 SmartThings에서 사용할 수 있도록 만든 비공식 Edge Driver입니다.

현재 버전은 Xiaomi Gateway의 로컬 miIO 통신과 MQTT를 이용하며, Xiaomi Cloud 연결 없이 LAN 내부에서 동작하는 것을 목표로 합니다.

---

## 주요 기능

### Xiaomi Gateway

- Xiaomi miIO UDP `54321` 상태 확인
- Gateway 온라인 / 성능저하 / 오프라인 상태 관리
- 설정 가능한 Health Check 주기
- miIO TOKEN 기반 Xiaomi 자식 장치 자동 검색
- 지원되는 Zigbee 온습도 장치 상태 polling
- BLE over MQTT 수신
- 여러 Xiaomi Gateway 등록 가능

#### 실제 동작을 확인한 Gateway

현재 실제 SmartThings Hub 환경에서 다음 Xiaomi Gateway의 동작을 확인했습니다.

| 제품명 | 모델 | 제품 모델 / SKU | 확인한 펌웨어 | 확인된 기능 |
|---|---|---|---|---|
| Xiaomi Smart Home Hub 2 | `lumi.gateway.mgl001` | `ZNDMWG04LM` / `BHR6765GL` | `1.0.8_0013` | miIO 상태 확인 / TOKEN 기반 자식 검색 / Zigbee 상태 polling |
| Xiaomi Mijia Smart Multi-Mode Gateway | `lumi.gateway.mgl03` | `ZNDMWG03LM` / `ZNDMWG02LM` 계열 | `1.5.0_0026` | miIO 상태 확인 / openmiio / MQTT BLE 수신 |

> 위 펌웨어 버전은 실제 테스트 환경에서 확인한 버전이며, 지원 가능한 최소/최대 펌웨어 버전을 의미하지 않습니다. 같은 내부 모델이라도 지역판, 펌웨어 또는 하드웨어 리비전에 따라 동작 차이가 있을 수 있습니다.

### Xiaomi BLE 장치

현재 실제 동작을 확인한 BLE 장치는 다음과 같습니다.

| 구분 | 모델 | 모델명 | pdid | 지원 기능 |
|---|---|---|---:|---|
| Xiaomi BLE 온습도 센서 | `miaomiaoce.sensor_ht.o2` | `LYWSD02MMC` | `5860` | 온도 / 습도 / 배터리 |
| Xiaomi Toothbrush T700i | `k0918.toothbrush.t700i` | `MES604` | `6032` | 양치 시작/종료 / 양치 시간 / 점수 / 배터리 |

BLE 장치는 MQTT 광고를 수신하면 SmartThings `EDGE_CHILD` 장치로 자동 등록됩니다.

### Xiaomi Toothbrush T700i

T700i의 MiBeacon 이벤트를 이용해 양치 상태를 SmartThings에 반영합니다.

```text
양치 시작
    ↓
motionSensor = active

양치 종료
    ↓
motionSensor = inactive
```

현재 확인된 이벤트:

```text
pdid = 6032
EID  = 12291 / 0x3003
```

지원 항목:

- 양치 시작 시각
- 양치 종료 시각
- 양치 시간 계산
- 양치 점수
- 배터리
- 반복되는 시작 이벤트에서 최초 시작 시각 유지
- 과거 BLE 이벤트가 현재 양치 상태를 잘못 종료하지 않도록 필터링
- 최근 활성 세션의 재시작 복구

---

### 기능에 따라 선택적으로 필요

#### Zigbee 자식 장치 자동 검색 / 상태 polling

Xiaomi Gateway 자체의 **32자리 miIO TOKEN**이 필요합니다.

```text
16바이트 / 32자리 16진수 문자열
```

TOKEN은 BLE KEY 또는 Gateway Key와 다른 값입니다.

자세한 내용은 [`TOKEN-GUIDE.md`](TOKEN-GUIDE.md)를 참고하세요.

#### BLE 장치 사용

BLE over MQTT를 사용하려면 Xiaomi Gateway 또는 같은 LAN의 장치에서 다음 서비스가 필요합니다.

```text
openmiio
Mosquitto 또는 호환 MQTT Broker
```

기본 MQTT 포트는 `1883`입니다.

```text
Xiaomi BLE 장치
      ↓
Xiaomi Gateway / openmiio
      ↓
MQTT Broker
      ↓
SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

BLE over MQTT 경로에서는 Xiaomi Gateway miIO TOKEN이 필요하지 않습니다.

---
### 채널 초대 링크

[https://bestow-regional.api.smartthings.com/invite/Kr2zLBpAKpjA](https://bestow-regional.api.smartthings.com/invite/Kr2zLBpAKpjA)

### 설치 순서

1. 설치 가능한 드라이버 목록에서 **Xiaomi Gateway** 드라이버를 설치합니다.
2. 설치가 완료되면 SmartThings 앱으로 돌아갑니다.
3. `기기 추가` → `주변 검색`을 실행합니다.
4. 생성된 `Xiaomi Gateway` 장치를 열고 실제 Gateway의 `IP address`를 입력합니다.
5. 필요한 경우 TOKEN, Zigbee polling, BLE MQTT 설정을 추가합니다.

> 드라이버를 채널에서 설치하는 것만으로 Xiaomi Gateway가 자동으로 완전히 설정되는 것은 아닙니다. SmartThings 앱에서 Gateway 장치를 검색한 후 실제 Xiaomi Gateway의 IP 주소를 입력해야 합니다.

---

## Xiaomi Gateway 등록

드라이버를 Hub에 설치한 후 SmartThings 앱에서 Gateway를 등록합니다.

1. SmartThings 앱을 엽니다.
2. `기기 추가`를 선택합니다.
3. `주변 검색`을 실행합니다.
4. `Xiaomi Gateway` 장치가 생성될 때까지 기다립니다.
5. 생성된 `Xiaomi Gateway` 장치를 엽니다.
6. `설정`에서 실제 Xiaomi Gateway 정보를 입력합니다.

한 번에 하나의 **미설정 Xiaomi Gateway 등록 슬롯**만 생성합니다. 여러 Gateway를 사용할 경우 첫 번째 Gateway의 IP 설정을 완료한 후 다시 `주변 검색`을 실행해 다음 Gateway를 추가하세요.

---

## Gateway 설정

SmartThings의 Xiaomi Gateway 설정에는 다음 9개 항목이 있습니다.

| 설정 | 설명 | 기본값 |
|---|---|---:|
| `IP address` | Xiaomi Gateway IPv4 주소 | 없음 |
| `Health check interval` | miIO 상태 확인 주기 | 60초 |
| `Auto child discovery` | TOKEN 기반 Xiaomi 자식 자동 검색 | Off |
| `TOKEN` | Xiaomi Gateway miIO TOKEN | 없음 |
| `Zigbee state polling` | 지원 Zigbee 장치 상태 polling | Off |
| `Zigbee poll interval` | Zigbee polling 주기 | 60초 |
| `BLE via MQTT` | BLE MQTT 수신 활성화 | Off |
| `BLE MQTT broker IP` | MQTT Broker IP | 비워두면 Gateway IP 사용 |
| `BLE MQTT port` | MQTT Broker TCP Port | 1883 |

---

## 가장 간단한 사용 방법

### Gateway 상태만 확인하는 경우

다음 설정만 필요합니다.

```text
IP address = Xiaomi Gateway IP
```

이 경우 드라이버는 UDP `54321`로 Gateway 상태만 확인합니다.

```text
online
  ↓
degraded
  ↓
offline
```

기본적으로 3회 연속 실패해야 offline으로 판정합니다.

### Zigbee 자식 장치를 사용하는 경우

다음 설정을 추가합니다.

```text
Auto child discovery = On
TOKEN                = Xiaomi Gateway miIO TOKEN
```

온습도 값을 polling하려면:

```text
Zigbee state polling = On
Zigbee poll interval = 60
```

현재 상태 polling이 구현된 주요 계열은 Xiaomi Zigbee 온습도 장치입니다.

예:

```text
lumi.weather.v1
lumi.sensor_ht.v1
```

자동 검색된 모델은 이름에 따라 다음 SmartThings child profile로 분류됩니다.

- 온습도
- Contact
- Motion
- Water Leak
- Generic

다만 **자동 등록된 모든 모델의 실시간 상태가 구현되어 있는 것은 아닙니다.** 현재 Zigbee polling은 온습도 계열을 중심으로 지원합니다.

### BLE 온습도 센서 / T700i를 사용하는 경우

MQTT가 실행되는 Gateway의 설정에서:

```text
BLE via MQTT       = On
BLE MQTT broker IP = MQTT Broker IP
BLE MQTT port      = 1883
```

Broker IP를 비워두면 해당 Xiaomi Gateway의 `IP address`를 사용합니다.

정상 연결 시 드라이버는 MQTT topic `#`을 구독하고 Xiaomi BLE 이벤트를 자동으로 처리합니다.

---

## MQTT 기본 동작

```text
Subscription Topic : #
Keepalive          : 30초
PINGREQ            : 15초
PINGRESP timeout   : 10초
Receive timeout    : 5초
Reconnect          : 3초
```

BLE 이벤트는 다음 topic에서 처리합니다.

```text
miio/report
central/report
```

중복 가능성이 있는 `openmiio/log` 복사본은 BLE 상태 처리에서 사용하지 않습니다.

---

## SmartThings에 생성되는 장치

예를 들어 다음과 같은 구조가 만들어질 수 있습니다.

```text
Xiaomi Gateway
├─ Xiaomi Zigbee 온습도 센서
├─ Xiaomi Contact Sensor
├─ Xiaomi Motion Sensor
└─ Xiaomi Water Leak Sensor

BLE MQTT 광고
├─ BLE 온습도 xxxx
└─ BLE 칫솔 xxxx
```

BLE 장치는 MAC을 기반으로 만든 안정적인 child key를 사용하기 때문에 같은 센서가 반복 광고되더라도 새로운 장치를 계속 생성하지 않습니다.

기존 BLE child가 이미 존재하면 가능한 경우 기존 SmartThings 장치와 이름, parent 관계를 유지합니다.

---

## 정상 동작 확인

### Gateway

SmartThings 앱에서 Gateway Status가 다음 중 하나로 표시되는지 확인합니다.

```text
online
degraded
offline
```

### BLE / MQTT

BLE 기능을 사용하는 경우 정상 연결 후 다음 동작을 확인합니다.

- BLE 온습도 센서가 자동으로 생성되는지
- 온도/습도 값이 갱신되는지
- T700i를 사용하면 양치 시작/종료 상태가 변경되는지
- MQTT 연결이 끊긴 뒤 자동 재연결되는지

### 개발자용 logcat 확인

일반 사용자는 필요하지 않지만, 문제 분석 시 SmartThings CLI를 설치한 PC에서 다음과 같이 로그를 확인할 수 있습니다.

```powershell
smartthings edge:drivers
```

드라이버 ID를 확인한 후:

```powershell
smartthings edge:drivers:logcat <DRIVER_ID> --hub-address <HUB_IP>
```

정상 MQTT 연결에서는 다음과 유사한 로그가 표시됩니다.

```text
BLE MQTT TCP connected
BLE MQTT CONNACK accepted
BLE MQTT SUBACK accepted
BLE MQTT PINGREQ sent
BLE MQTT PINGRESP OK
```

### T700i

양치를 시작하면:

```text
motionSensor = active
```

양치를 종료하면:

```text
motionSensor = inactive
```

정상 세션 종료 로그 예:

```text
BLE MQTT toothbrush session complete
start=...
end=...
duration=121s
duration_text=02:01
score=...
```

T700i 세션 처리에 대한 자세한 내용은 [`TOOTHBRUSH-SESSION.md`](TOOTHBRUSH-SESSION.md)를 참고하세요.

---

## 문제 해결

### Xiaomi Gateway가 검색되지 않는 경우

- 채널 초대 링크를 통해 드라이버가 해당 SmartThings Hub에 설치되어 있는지 확인합니다.
- SmartThings 앱에서 `주변 검색`을 다시 실행합니다.
- 이미 IP가 비어 있는 `Xiaomi Gateway` 장치가 하나 존재하는지 확인합니다.
- 미설정 Gateway가 있으면 먼저 해당 장치의 IP를 설정한 후 다시 검색합니다.

### Gateway가 offline으로 표시되는 경우

- `IP address`가 올바른지 확인합니다.
- SmartThings Hub에서 Xiaomi Gateway로 UDP `54321` 통신이 가능한지 확인합니다.
- VLAN을 사용하는 경우 Hub와 Gateway 사이의 방화벽/ACL을 확인합니다.

### Auto child discovery가 동작하지 않는 경우

- `Auto child discovery = On`인지 확인합니다.
- Xiaomi Gateway 자체의 올바른 **32자리 miIO TOKEN**을 입력했는지 확인합니다.
- BLE 센서는 이 기능으로 등록하지 않습니다. BLE 장치는 MQTT 광고를 통해 동적으로 등록됩니다.

### BLE 장치가 생성되지 않는 경우

- `BLE via MQTT = On`인지 확인합니다.
- Broker IP와 Port가 맞는지 확인합니다.
- Xiaomi Gateway에서 openmiio와 MQTT Broker가 정상 실행 중인지 확인합니다.
- SmartThings Hub에서 MQTT Broker TCP 포트로 접근 가능한지 확인합니다.
- MQTT에 실제 `miio/report` 또는 `central/report` BLE 이벤트가 들어오는지 확인합니다.

### T700i 점수 또는 배터리가 바로 표시되지 않는 경우

T700i의 점수와 배터리는 항상 같은 BLE 패킷으로 오지 않을 수 있습니다.

- 점수는 양치 종료 이벤트에 포함될 수 있습니다.
- 배터리는 별도의 MiBeacon 배터리 이벤트로 수신됩니다.

따라서 종료 직후 배터리가 별도로 갱신되는 것은 정상입니다.

---

## 개발자용 소스 설치

일반 사용자는 이 절차가 필요하지 않습니다. 드라이버 개발, 수정 또는 테스트가 필요한 경우에만 저장소를 직접 패키징할 수 있습니다.

```powershell
git clone https://github.com/leathersocks/xiaomi-gateway-edge-driver.git
cd xiaomi-gateway-edge-driver
smartthings edge:drivers:package . --install
```

Windows에서는 다음 스크립트도 사용할 수 있습니다.

```powershell
.\install.ps1
```

`sync-ui.ps1`은 일반 설치용이 아니라 기존 Gateway Status Custom Capability의 UI 정의를 다시 적용하기 위한 유지보수 스크립트입니다.

---

## 보안 주의사항

- 실제 Gateway TOKEN을 GitHub, README, Issue 또는 로그에 공개하지 마세요.
- BLE KEY, BLE Bind Key, Gateway Key를 저장소에 기록하지 마세요.
- 이 드라이버는 설정된 Gateway TOKEN을 logcat에 출력하지 않습니다.
- 인증 없는 MQTT `1883` 포트를 인터넷에 직접 노출하지 마세요.
- MQTT Broker는 신뢰할 수 있는 LAN/VLAN 내부에서만 운영하는 것을 권장합니다.

---

## 현재 검증된 항목

실제 SmartThings Hub 환경에서 다음 항목을 확인했습니다.

- Xiaomi Gateway miIO UDP 상태 확인
- Gateway online/offline 상태 관리
- MQTT CONNECT / SUBSCRIBE
- MQTT PINGREQ / PINGRESP 유지
- MQTT 자동 재연결
- BLE 온도/습도 이벤트 수신
- BLE 자식 장치 자동 등록
- Xiaomi Toothbrush T700i 자동 등록
- T700i 양치 시작 → `motionSensor active`
- T700i 양치 종료 → `motionSensor inactive`
- T700i 양치 시간 계산
- T700i 점수 처리
- T700i 배터리 처리

---

## 참고 및 제한사항

- 본 프로젝트는 Xiaomi 또는 Samsung SmartThings의 공식 드라이버가 아닙니다.
- Xiaomi Gateway 펌웨어, 지역 버전 또는 하드웨어 리비전에 따라 동작 차이가 있을 수 있습니다.
- 일부 Xiaomi Gateway에서는 `get_device_list` 또는 `get_device_prop_exp` 사용을 위해 올바른 miIO TOKEN이 필요합니다.
- BLE 기능은 Xiaomi Gateway 자체 기능만으로 동작하는 것이 아니라 openmiio/MQTT 환경이 필요합니다.
- 모든 Xiaomi Zigbee/BLE 모델을 지원하는 범용 드라이버가 아닙니다.
- 지원되지 않는 장치는 Generic child로 등록되거나 실시간 상태가 제공되지 않을 수 있습니다.
- `sync-ui.ps1`은 저장소의 기존 Custom Capability namespace를 관리하기 위한 유지보수 도구이므로 일반 사용자는 실행하지 않는 것을 권장합니다.

---

## 관련 문서

- [`TOKEN-GUIDE.md`](TOKEN-GUIDE.md) — Xiaomi Gateway miIO TOKEN 설명
- [`TOOTHBRUSH-SESSION.md`](TOOTHBRUSH-SESSION.md) — T700i 양치 세션 처리
- [`CHANGELOG.md`](CHANGELOG.md) — 버전별 변경 이력

오류 재현이나 지원 장치 추가에 필요한 정보는 GitHub Issue를 통해 공유할 수 있습니다. 로그를 첨부할 때는 TOKEN, BLE KEY, Gateway Key 등 민감정보가 포함되지 않았는지 반드시 확인하세요.