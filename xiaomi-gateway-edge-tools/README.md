# Xiaomi Gateway Edge Tools

`xiaomi-gateway-edge-tools`는 **Xiaomi Gateway SmartThings Edge Driver의 선택형 관리/진단 도구 모음**입니다.

이 폴더의 파일은 SmartThings Edge Driver 자체가 동작하는 데 필수는 아닙니다. Xiaomi `mgl03` Gateway에서 openmiio/MQTT BLE 경로를 구성하거나, MQTT로 들어오는 BLE 이벤트를 직접 확인할 때 관리 PC에서 사용합니다.

> 일반적인 SmartThings 사용자라면 이 도구를 설치할 필요가 없습니다. BLE over MQTT를 직접 구성하거나 문제를 진단할 때만 사용하세요.

---

## 포함 파일

| 파일 | 용도 |
|---|---|
| [`install-openmiio-mgl03-v5.py`](install-openmiio-mgl03-v5.py) | Telnet이 열려 있는 `mgl03`에 `openmiio_agent`를 설치하고 MQTT/BLE 관련 모듈을 실행 |
| [`mqtt-ble-probe-v2.py`](mqtt-ble-probe-v2.py) | MQTT Broker에 접속해 Xiaomi `_async.ble_event`를 수신하고 BLE 이벤트를 확인 |
| [`OPENMIIO-SETUP.md`](OPENMIIO-SETUP.md) | mgl03 openmiio/MQTT 구성 절차, SmartThings 설정, 문제 해결 가이드 |
| [`SHA256SUMS.txt`](SHA256SUMS.txt) | 도구 파일 무결성 확인용 SHA-256 목록 |

---

## 사용 대상

현재 이 도구의 openmiio 설치 절차는 다음 계열을 대상으로 합니다.

| 항목 | 확인 환경 |
|---|---|
| Xiaomi 내부 모델 | `lumi.gateway.mgl03` |
| Gateway 계열 | Xiaomi Mijia Smart Multi-Mode Gateway |
| 확인된 펌웨어 계열 | `1.5.0.x` |
| CPU/바이너리 | MIPS / `openmiio_agent_mips` |
| Telnet | TCP `23` |
| MQTT | TCP `1883` |

`install-openmiio-mgl03-v5.py`는 **mgl03용 도구**입니다. `mgl001` 또는 다른 아키텍처의 Xiaomi Gateway에 그대로 사용하지 마세요.

---

## 전체 구성

```text
Xiaomi BLE 장치
      ↓
Xiaomi Gateway (mgl03)
      ↓
openmiio_agent
      ↓
Mosquitto / MQTT :1883
      ↓
miio/report / central/report
      ↓
Xiaomi Gateway SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

SmartThings Edge Driver는 MQTT topic `#`을 구독하고 지원되는 BLE 이벤트를 처리합니다.

---

## 준비 사항

관리 PC에 다음 환경이 필요합니다.

- Python 3
- Xiaomi Gateway와 같은 LAN 또는 접근 가능한 관리 네트워크
- 대상 mgl03의 Telnet TCP `23` 접근
- 설치 후 MQTT TCP `1883` 접근
- 인터넷 연결
  - 설치 스크립트가 `openmiio_agent` MIPS v1.2.1 바이너리를 내려받을 때 필요

설치 스크립트 자체에는 Xiaomi 계정 비밀번호, miIO TOKEN, BLE KEY 또는 Gateway Key를 입력하지 않습니다.

---

## 1. Gateway 주소 지정

PowerShell 예:

```powershell
$GatewayIP = "192.168.1.41"
```

이후 문서의 `$GatewayIP`은 실제 mgl03 IP 주소로 바꿔 사용하면 됩니다.

---

## 2. Telnet 확인

openmiio 설치 전 Telnet 포트가 열려 있어야 합니다.

```powershell
Test-NetConnection $GatewayIP -Port 23
```

정상 예:

```text
TcpTestSucceeded : True
```

`False`라면 설치 스크립트를 실행하지 말고 먼저 mgl03에서 Telnet을 사용할 수 있는 상태인지 확인하세요.

---

## 3. openmiio 설치 및 실행

이 폴더에서 다음 명령을 실행합니다.

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

스크립트는 다음 작업을 수행합니다.

1. Telnet TCP `23` 연결 확인
2. `openmiio_agent` MIPS v1.2.1 다운로드
3. 다운로드한 바이너리 MD5 검증
4. mgl03 Telnet 로그인
5. Gateway 정보 확인
6. 기존 `openmiio_agent` 실행 여부 확인
7. 필요한 경우 `/data/openmiio_agent`로 업로드
8. 원격 바이너리 MD5 재검증
9. 실행 권한 적용
10. `miio mqtt cache central` 모듈 실행
11. MQTT TCP `1883` 접근 여부 확인

기본적으로 기존 `openmiio_agent`가 실행 중이면 임의로 교체하거나 재시작하지 않습니다.

기존 프로세스를 의도적으로 재시작하려면:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP --force-restart
```

`--force-restart`는 기존 openmiio 프로세스를 중지할 수 있으므로 필요한 경우에만 사용하세요.

### 주요 옵션

```text
--gateway-ip     Gateway IP
--telnet-port    Telnet 포트, 기본값 23
--mqtt-port      MQTT 포트, 기본값 1883
--force-restart  기존 openmiio_agent를 중지하고 다시 시작
```

---

## 4. MQTT Broker 확인

설치 후:

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

정상이라면:

```text
TcpTestSucceeded : True
```

Gateway 내부 openmiio 로그는 다음 경로를 사용합니다.

```text
/var/log/st-openmiio.log
```

---

## 5. BLE MQTT 이벤트 확인

MQTT가 열려 있으면 probe를 실행합니다.

```powershell
py .\mqtt-ble-probe-v2.py --host $GatewayIP
```

기본값:

```text
Port      : 1883
Topic     : #
Reconnect : 3초
Keepalive : 30초
```

probe는 연결이 끊어지면 다시 접속하며 Xiaomi `_async.ble_event`를 찾아 표시합니다.

종료:

```text
Ctrl+C
```

### 현재 probe가 해석하는 BLE 온습도 이벤트

| 항목 | EID | 데이터 형식 |
|---|---:|---|
| 온도 | `19457` / `0x4C01` | little-endian float32 |
| 습도 | `19458` / `0x4C02` | uint8 |
| 배터리 | `18435` / `0x4803` | uint8 |

지원되지 않는 EID도 원본 `eid`와 `edata`를 확인할 수 있으므로 신규 BLE 장치 분석에 사용할 수 있습니다.

---

## 6. SmartThings 설정

mgl03에서 openmiio/MQTT가 정상 실행된 후 SmartThings의 해당 Xiaomi Gateway 설정에서:

```text
BLE via MQTT        = On
BLE MQTT broker IP  = 비워둠
BLE MQTT port       = 1883
```

`BLE MQTT broker IP`를 비워두면 Edge Driver는 해당 Gateway의 `IP address`를 MQTT Broker 주소로 사용합니다.

MQTT Broker가 다른 장치에 있다면 해당 장치의 IP를 직접 입력하세요.

---

## 정상 동작 확인 순서

```text
Telnet :23 접근 가능
      ↓
openmiio_agent 설치/실행
      ↓
MQTT :1883 접근 가능
      ↓
mqtt-ble-probe-v2.py에서 BLE 이벤트 수신
      ↓
SmartThings BLE via MQTT = On
      ↓
지원 BLE 장치가 EDGE_CHILD로 생성
      ↓
온도/습도/배터리 또는 T700i 이벤트 갱신
```

문제가 생기면 이 순서대로 어느 단계에서 끊기는지 확인하는 것이 가장 빠릅니다.

---

## 설치 스크립트 종료 코드

`install-openmiio-mgl03-v5.py`의 주요 종료 코드는 다음과 같습니다.

| 코드 | 의미 |
|---:|---|
| `0` | openmiio 실행 후 MQTT 포트 접근 확인 성공 |
| `1` | 설치/연결/검증 과정에서 오류 발생 |
| `2` | openmiio 시작은 수행했지만 MQTT 포트 접근 확인 실패 |
| `3` | 기존 `openmiio_agent`가 실행 중이며 `--force-restart`를 사용하지 않아 중단 |

---

## Gateway 재부팅 후

현재 helper는 openmiio를 **런타임 프로세스**로 실행합니다.

따라서 mgl03을 재부팅한 뒤 MQTT TCP `1883`이 더 이상 열리지 않는 경우 다음 순서로 확인하세요.

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

포트가 닫혀 있다면:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP --force-restart
```

---

## 파일 무결성 확인

PowerShell에서 예를 들어:

```powershell
Get-FileHash .\install-openmiio-mgl03-v5.py -Algorithm SHA256
Get-FileHash .\mqtt-ble-probe-v2.py -Algorithm SHA256
```

결과를 [`SHA256SUMS.txt`](SHA256SUMS.txt)와 비교할 수 있습니다.

---

## 보안 주의사항

- Telnet TCP `23`을 인터넷에 노출하지 마세요.
- 인증 없이 사용하는 MQTT TCP `1883`도 인터넷에 노출하지 마세요.
- 관리 작업은 신뢰할 수 있는 LAN/VLAN 내부에서 수행하세요.
- Gateway TOKEN, BLE KEY, Gateway Key, Xiaomi 계정 정보 등을 코드나 GitHub Issue에 기록하지 마세요.
- 로그를 공유하기 전에 민감정보가 포함되어 있지 않은지 확인하세요.

---

## 문제 해결

상세 설치 절차와 문제별 확인 방법은 다음 문서를 참고하세요.

[`OPENMIIO-SETUP.md`](OPENMIIO-SETUP.md)

대표적인 점검 순서는 다음과 같습니다.

```text
Telnet 23
  ↓
openmiio_agent
  ↓
MQTT 1883
  ↓
mqtt-ble-probe
  ↓
SmartThings BLE via MQTT
```

---

## 참고

이 도구들은 `xiaomi-gateway-edge-driver`의 **선택적 관리 도구**이며 SmartThings Edge Lua runtime이나 Device Profile에 포함될 필요가 없습니다.

일반 사용자에게 필요한 기본 드라이버 설치/설정 방법은 상위 저장소의 [`README.md`](../README.md)를 참고하세요.
