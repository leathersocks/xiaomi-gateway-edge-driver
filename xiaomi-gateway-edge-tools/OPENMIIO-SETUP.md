# Xiaomi mgl03 openmiio / MQTT 설정 가이드

이 문서는 **Xiaomi Mijia Smart Multi-Mode Gateway (`lumi.gateway.mgl03`)**에서 `openmiio_agent`와 MQTT Broker를 이용해 BLE 이벤트를 SmartThings Edge Driver로 전달하는 방법을 설명합니다.

> 이 절차는 현재 저장소의 `install-openmiio-mgl03-v5.py`와 `mqtt-ble-probe-v2.py`를 기준으로 작성되었습니다.
>
> 대상 Gateway는 **mgl03 계열**입니다. `mgl001`용 설치 절차와 바이너리는 다르므로 이 스크립트를 `mgl001`에 사용하지 마세요.

---

## 1. 동작 구조

BLE 장치의 광고는 다음 경로로 SmartThings에 전달됩니다.

```text
Xiaomi BLE 장치
      ↓
Xiaomi Gateway mgl03
      ↓
openmiio_agent
      ↓
Mosquitto MQTT Broker :1883
      ↓
miio/report / central/report
      ↓
Xiaomi Gateway SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

Edge Driver는 MQTT topic `#`을 구독하며, 실제 BLE 처리는 `miio/report`와 `central/report`의 `_async.ble_event`를 사용합니다.

---

## 2. 확인된 대상 환경

현재 설치 스크립트가 대상으로 하는 환경은 다음과 같습니다.

| 항목 | 값 |
|---|---|
| 내부 모델 | `lumi.gateway.mgl03` |
| 확인한 펌웨어 계열 | `1.5.0.x` |
| openmiio 바이너리 | `openmiio_agent` MIPS v1.2.1 |
| Telnet 포트 | TCP `23` |
| MQTT 포트 | TCP `1883` |
| Telnet 사용자 | `admin` |
| openmiio 설치 위치 | `/data/openmiio_agent` |
| openmiio 로그 | `/var/log/st-openmiio.log` |

펌웨어 또는 지역판에 따라 Telnet 사용 가능 여부와 동작이 달라질 수 있습니다.

---

## 3. 준비 사항

관리 PC에 다음 환경이 필요합니다.

- Python 3
- 인터넷 연결
  - 설치 스크립트가 `openmiio_agent` MIPS v1.2.1 바이너리를 다운로드할 때 사용합니다.
- PC에서 Xiaomi Gateway로 TCP `23` 및 TCP `1883` 통신 가능
- Xiaomi Gateway의 Telnet 포트가 이미 활성화된 상태

`install-openmiio-mgl03-v5.py` 자체는 Xiaomi miIO TOKEN이나 Gateway Key를 요구하지 않습니다.

### Telnet 상태 확인

Windows PowerShell에서 Gateway IP를 지정합니다.

```powershell
$GatewayIP = "192.168.1.100"
Test-NetConnection $GatewayIP -Port 23
```

정상이라면 다음과 같이 표시됩니다.

```text
TcpTestSucceeded : True
```

`False`라면 먼저 해당 mgl03에서 Telnet을 사용할 수 있도록 준비해야 합니다. 이 설치 스크립트는 **닫혀 있는 Telnet 포트를 직접 활성화하지 않습니다.**

---

## 4. MQTT Broker 상태 확인

먼저 Gateway의 TCP `1883` 포트를 확인합니다.

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

이미 다음처럼 나오면 MQTT Broker가 실행 중일 수 있습니다.

```text
TcpTestSucceeded : True
```

이 경우 기존 `openmiio_agent`가 실행 중일 가능성이 있으므로 바로 `--force-restart`를 사용하지 말고 먼저 현재 상태를 확인하는 것을 권장합니다.

---

## 5. openmiio 설치 및 실행

`xiaomi-gateway-edge-tools` 폴더에서 실행합니다.

```powershell
cd xiaomi-gateway-edge-tools
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

설치 스크립트는 다음 작업을 수행합니다.

1. TCP `23` Telnet 연결 확인
2. mgl03 `admin` shell 로그인
3. Gateway 정보 확인
4. 기존 `openmiio_agent` 프로세스 확인
5. `openmiio_agent` MIPS v1.2.1 다운로드
6. 다운로드한 바이너리 MD5 검증
7. Gateway의 `/data/openmiio_agent`에 업로드
8. 원격 바이너리 MD5 재검증
9. 실행 권한 설정
10. 다음 모듈로 `openmiio_agent` 실행
11. 프로세스 / MQTT `1883` / 로그 상태 확인

실행되는 모듈은 다음과 같습니다.

```text
miio
mqtt
cache
central
```

실제 실행 형태는 다음과 같습니다.

```text
/data/openmiio_agent miio mqtt cache central --log.level=trace
```

이 BLE/MQTT 구성에서는 `z3` 모듈을 사용하지 않습니다.

### 정상 완료 예

성공하면 마지막에 다음과 유사한 메시지가 표시됩니다.

```text
SUCCESS: MQTT broker is reachable at <Gateway IP>:1883
Next: subscribe to topic # and wait for BLE advertisements.
```

---

## 6. 기존 openmiio가 실행 중인 경우

설치 스크립트는 기존 `openmiio_agent`를 발견하면 기본적으로 중단합니다.

이는 이미 정상 동작 중인 프로세스를 실수로 종료하거나 다른 구성으로 바꾸는 것을 방지하기 위한 동작입니다.

기존 프로세스를 **의도적으로 교체하거나 재시작하려는 경우에만** 다음 옵션을 사용하세요.

```powershell
py .\install-openmiio-mgl03-v5.py `
  --gateway-ip $GatewayIP `
  --force-restart
```

> `--force-restart`는 기존 `openmiio_agent`를 종료한 뒤 이 저장소의 구성으로 다시 실행합니다. 정상 동작 중인 별도 openmiio 구성이 있다면 사용하지 마세요.

---

## 7. 다른 포트를 사용하는 경우

기본값은 다음과 같습니다.

```text
Telnet : 23
MQTT   : 1883
```

필요한 경우 옵션으로 변경할 수 있습니다.

```powershell
py .\install-openmiio-mgl03-v5.py `
  --gateway-ip $GatewayIP `
  --telnet-port 23 `
  --mqtt-port 1883
```

SmartThings Edge Driver의 `BLE MQTT port`도 실제 Broker 포트와 동일해야 합니다.

---

## 8. MQTT BLE 이벤트 확인

openmiio 설치가 끝나면 `mqtt-ble-probe-v2.py`로 실제 BLE 이벤트가 MQTT에 들어오는지 확인할 수 있습니다.

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

필요하면 직접 지정할 수 있습니다.

```powershell
py .\mqtt-ble-probe-v2.py `
  --host $GatewayIP `
  --port 1883 `
  --topic "#" `
  --reconnect 3
```

정상 연결 시 다음과 유사한 메시지가 표시됩니다.

```text
Subscribed; waiting for BLE events...
```

BLE 장치가 광고하면 다음과 같은 정보가 출력됩니다.

```text
--- BLE EVENT ---
topic : miio/report
did   : ...
mac   : ...
pdid  : ...
frmCnt: ...
gwts  : ...
evt   : eid=... edata=...
```

### 현재 probe에서 해석하는 온습도 이벤트

| 항목 | EID | 형식 |
|---|---:|---|
| 온도 | `19457 / 0x4C01` | little-endian IEEE-754 float32 |
| 습도 | `19458 / 0x4C02` | uint8 |
| 배터리 | `18435 / 0x4803` | uint8 |

알 수 없는 EID도 원본 `eid`와 `edata`가 출력되므로 새로운 BLE 장치 분석에 사용할 수 있습니다.

종료하려면 `Ctrl+C`를 누릅니다.

---

## 9. SmartThings Gateway 설정

SmartThings 앱에서 MQTT를 담당하는 Xiaomi Gateway 장치를 열고 다음과 같이 설정합니다.

```text
IP address              = Xiaomi Gateway IP
BLE via MQTT            = On
BLE MQTT broker IP      = 비워둠 또는 MQTT Broker IP
BLE MQTT port           = 1883
```

Broker가 Xiaomi Gateway 자체에서 실행 중이라면 `BLE MQTT broker IP`를 비워둘 수 있습니다. 이 경우 Edge Driver는 `IP address` 값을 MQTT Broker 주소로 사용합니다.

다른 LAN 장치에서 MQTT Broker를 운영한다면 `BLE MQTT broker IP`에 해당 장치의 IP를 입력합니다.

Edge Driver의 MQTT 구독 topic은 내부적으로 `#`으로 고정되어 있습니다.

---

## 10. 정상 동작 확인 순서

다음 순서로 확인하면 문제 원인을 빠르게 구분할 수 있습니다.

```text
1. Telnet TCP 23 열림
        ↓
2. install-openmiio-mgl03-v5.py 정상 완료
        ↓
3. MQTT TCP 1883 열림
        ↓
4. mqtt-ble-probe-v2.py 구독 성공
        ↓
5. BLE 광고 수신 확인
        ↓
6. SmartThings에서 BLE via MQTT = On
        ↓
7. EDGE_CHILD 자동 생성 및 값 갱신 확인
```

---

## 11. 문제 해결

### `Telnet ...:23 is not open`

원인:

- mgl03 Telnet이 활성화되지 않음
- Gateway IP가 잘못됨
- PC와 Gateway 사이 방화벽/VLAN 차단

확인:

```powershell
Test-NetConnection $GatewayIP -Port 23
```

### `Existing openmiio_agent detected`

기존 openmiio 프로세스가 실행 중인 상태입니다.

정상 시스템이라면 그대로 유지하는 것이 안전합니다. 이 스크립트로 교체하려는 것이 확실한 경우에만 `--force-restart`를 사용합니다.

### 설치 후 MQTT `1883`이 열리지 않음

Telnet으로 Gateway에 접속할 수 있다면 다음 로그를 확인합니다.

```sh
cat /var/log/st-openmiio.log
```

또는 최근 로그만 확인합니다.

```sh
tail -n 100 /var/log/st-openmiio.log
```

프로세스 확인:

```sh
ps w | grep '[o]penmiio_agent'
```

MQTT listen 상태 확인:

```sh
netstat -ltnp 2>/dev/null | grep ':1883 '
```

### MQTT 연결은 되지만 BLE 이벤트가 없음

다음을 순서대로 확인합니다.

- BLE 장치가 실제로 광고 중인지
- `mqtt-ble-probe-v2.py`에서 `miio/report` 또는 `central/report`가 수신되는지
- `_async.ble_event`가 payload에 포함되는지
- Gateway의 openmiio 로그에 오류가 없는지

### SmartThings에서 BLE 장치가 생성되지 않음

- `BLE via MQTT = On` 확인
- `BLE MQTT broker IP` 확인
- `BLE MQTT port = 1883` 확인
- SmartThings Hub에서 Broker IP의 TCP `1883` 접근 가능 여부 확인
- 먼저 `mqtt-ble-probe-v2.py`에서 실제 BLE 이벤트가 들어오는지 확인

---

## 12. Gateway 재부팅 시 주의사항

현재 helper는 `openmiio_agent`를 **런타임 프로세스**로 실행합니다.

따라서 Gateway를 재부팅한 뒤 `openmiio_agent`와 TCP `1883` 서비스가 자동으로 복구되지 않을 수 있습니다.

재부팅 후 먼저 확인합니다.

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

포트가 열리지 않는다면 Telnet `23` 상태를 확인한 후 설치 helper를 다시 실행합니다.

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

기존 프로세스가 남아 있다고 판단되는 경우에만 `--force-restart`를 사용하세요.

---

## 13. 보안 주의사항

- TCP `23` Telnet과 TCP `1883` MQTT를 인터넷에 직접 노출하지 마세요.
- Gateway와 MQTT Broker는 신뢰할 수 있는 LAN/VLAN 내부에서만 운영하는 것을 권장합니다.
- 공유기 Port Forwarding으로 `23` 또는 `1883`을 외부에 공개하지 마세요.
- 실제 Gateway TOKEN, BLE KEY, Gateway Key를 GitHub Issue나 로그에 게시하지 마세요.
- 이 설치 스크립트는 miIO TOKEN/Gateway Key를 필요로 하지 않으며 해당 비밀값을 출력하지 않습니다.
- 이 절차는 본인이 관리하는 Xiaomi Gateway에서만 사용하세요.

---

## 14. 참고 파일

| 파일 | 용도 |
|---|---|
| `install-openmiio-mgl03-v5.py` | mgl03에 openmiio_agent 설치 및 MQTT/BLE 구성 실행 |
| `mqtt-ble-probe-v2.py` | MQTT 구독 및 BLE 이벤트 진단 |
| `README.md` | 도구 폴더 개요 |
| `../README.md` | SmartThings Edge Driver 설치 및 사용 방법 |

---

## 요약

일반적인 설정 순서는 다음과 같습니다.

```powershell
$GatewayIP = "192.168.1.100"

# 1. Telnet 확인
Test-NetConnection $GatewayIP -Port 23

# 2. openmiio 설치/실행
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP

# 3. MQTT 확인
Test-NetConnection $GatewayIP -Port 1883

# 4. BLE 이벤트 확인
py .\mqtt-ble-probe-v2.py --host $GatewayIP
```

이후 SmartThings에서 해당 Gateway의 `BLE via MQTT`를 `On`으로 설정하면 됩니다.
