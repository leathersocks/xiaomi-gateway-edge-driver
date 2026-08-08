# T700i 양치 세션 추적

[English](TOOTHBRUSH-SESSION.en.md)

이 설계에는 실제 SmartThings Hub 런타임에서 관찰한 다음 데이터를 사용했습니다.

```text
start:                 type=0, 현재 timestamp, live=true
normal end:            type=1, 현재 timestamp, score present
forced/early stop:     type=1, 이전 완료 세션 timestamp가 재사용될 수 있음
battery:               separate standard MiBeacon event
```

T700i의 MiBeacon 칫솔 이벤트(EID `12291 / 0x3003`)는 `type=0`을 양치 시작으로 처리하고, **0이 아닌 이벤트 타입은 종료 후보**로 처리합니다.

v1.10.2에서는 모든 non-zero `0x3003` 이벤트를 종료로 처리하도록 확장했고, v1.10.3에서는 강제 정지 순간의 실제 BLE 패킷을 확인하기 위해 raw 진단 로그를 추가했습니다.

v1.10.3 실제 강제정지 테스트에서 다음 패턴이 확인되었습니다.

```text
start
frmCnt=234
gwts=1786207645
edata=009b5d776a
type=0
event_ts=1786207643

forced stop
frmCnt=236
gwts=1786207649
edata=01b920776a
type=1
event_ts=1786192057
```

강제정지 패킷의 `type=1` 자체는 정상 종료와 같지만, 내장 `event_ts=1786192057`은 현재 종료 시각이 아니라 이전 정상 양치 완료 시각을 다시 사용했습니다. 이 때문에 기존 60초 live/history 필터에서는 강제정지 패킷이 과거 이벤트로 판정되어 즉시 `inactive`가 되지 않고 30초 watchdog으로만 복구되었습니다.

## v1.10.4 stale-stop 처리

v1.10.4부터는 다음 조건을 모두 만족하는 non-zero `0x3003` 패킷을 **현재 세션의 강제/조기 종료**로 추론합니다.

- T700i 현재 세션이 `active`
- 저장된 `start_ts > 0`
- `type != 0`
- 패킷의 내장 timestamp가 60초 live window 밖에 있음
- Gateway 수신 시각 `gwts`가 현재 `start_ts` 이후임
- `gwts - start_ts <= 10분`
- `frmCnt` 중복 억제를 통과한 새 advertisement

이 경우 원본 timestamp는 진단용으로 그대로 보존하고, 실제 상태·세션 계산에는 다음처럼 `gwts`를 유효 종료 시각으로 사용합니다.

```text
raw_event_ts       = 패킷에 포함된 이전 완료 timestamp
effective_end_ts   = gwts
duration           = effective_end_ts - start_ts
motionSensor       = inactive
watchdog           = invalidated
```

예를 들어 실제 관측 로그에서는 시작 `1786207643`, 강제정지 수신 `1786207649`이므로 예상 양치 시간은 약 6초입니다.

## 상태 머신

```text
IDLE
  |
  | live type=0
  v
BRUSHING
  |
  | repeated type=0 advertisement
  | keep first start timestamp
  | refresh 30s watchdog
  |
  +---- live type!=0 ----------------------+
  |                                         |
  +---- stale type!=0 + active session -----+
        use gwts as effective end timestamp
                                            v
                                  IDLE + completed session

BRUSHING
  |
  | no decodable end advertisement for 30s
  v
IDLE + watchdog fallback
```

세션이 active가 아닌 상태에서 들어오는 오래된 종료 패킷은 기존과 같이 현재 상태를 변경하지 않습니다. 따라서 단순 과거 재전송 패킷을 무조건 현재 종료 이벤트로 처리하지 않습니다.

## 30초 watchdog

종료 advertisement 자체가 유실되거나 해석할 수 없는 경우를 대비해 T700i 전용 30초 activity watchdog을 최종 안전망으로 유지합니다.

- 새로운 `live type=0` 시작 이벤트에서 watchdog 시작
- 반복되는 `type=0` 광고에서 watchdog 갱신
- 정상 live 종료 또는 v1.10.4 stale-stop 추론 성공 시 watchdog 즉시 무효화
- 종료 패킷이 전혀 없으면 마지막 활동 이후 30초에 `motionSensor=inactive`
- watchdog fallback은 종료 시각·점수 같은 완료 메타데이터를 임의로 만들지 않음

## Raw BLE 진단 로그

v1.10.3 이상에서는 `pdid=6032` 패킷을 자식 장치 조회 및 `frmCnt` 중복 억제보다 먼저 기록합니다.

```text
BLE MQTT T700i RAW: topic=miio/report did=... mac=... pdid=6032 frmCnt=... gwts=... events=[#1 eid=... eid_hex=... edata=... bytes=... type=... event_ts=...]
```

주요 필드:

- `frmCnt`: BLE advertisement sequence
- `gwts`: Gateway 수신 timestamp
- `eid`: Xiaomi MiBeacon 이벤트 ID
- `eid_hex`: 16진 이벤트 ID
- `edata`: 원본 payload
- `bytes`: 디코딩된 byte 수
- `type`: `0x3003` 첫 번째 byte
- `event_ts`: `0x3003` payload 내장 timestamp

v1.10.4에서는 stale-stop이 추론되면 다음 로그도 추가됩니다.

```text
BLE MQTT T700i forced stop inferred: ... raw_event_ts=... gwts=... start_ts=... inferred_duration=...s
```

상태 로그에서는 원본 timestamp와 실제 적용 timestamp를 동시에 확인할 수 있습니다.

```text
BLE MQTT toothbrush state OK: ...
type=1
raw_event_ts=<old timestamp>
event_ts=<gwts>
live=true
raw_delta=<large value>
delta=0
forced_stop=true
duration=...
```

완료 로그는 다음처럼 표시됩니다.

```text
BLE MQTT toothbrush session complete: ... duration=... forced_stop=true raw_event_ts=...
```

## 런타임 필드

```text
active                boolean
start_ts              Unix UTC
last_ts               Unix UTC
last_score            integer 0..100
last_duration         seconds
watchdog_generation   runtime generation counter
last_activity_ts      runtime Unix UTC
```

`watchdog_generation`과 `last_activity_ts`는 런타임용 비영속 필드입니다.

## 정상 동작 확인

일반 시작:

```text
type=0 ... live=true ... forced_stop=false
motionSensor=active
```

일반 정상 종료:

```text
type=1 ... raw_event_ts=<current> event_ts=<current> live=true forced_stop=false
motionSensor=inactive
BLE MQTT toothbrush session complete
```

강제/조기 정지에서 이전 완료 timestamp가 재사용된 경우:

```text
T700i forced stop inferred
motionSensor=inactive
... raw_event_ts=<previous session> event_ts=<gwts> forced_stop=true ...
BLE MQTT toothbrush session complete ... forced_stop=true
```

이 경우 `watchdog timeout`이 뒤이어 발생하지 않아야 정상입니다.

종료 advertisement 자체가 없는 경우에만 다음 fallback이 예상됩니다.

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```
