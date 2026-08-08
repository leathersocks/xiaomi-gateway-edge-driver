# T700i 양치 세션 추적

[English](TOOTHBRUSH-SESSION.en.md)

이 설계에는 실제 런타임에서 관찰한 다음 데이터를 사용했습니다.

```text
start:      type=0, live=true
normal end: type=1, live=true, score present
forced end: type!=0 가능, score 없을 수 있음
battery:    separate standard MiBeacon event
```

T700i의 MiBeacon 칫솔 이벤트(EID `0x3003`)는 `type=0`을 양치 시작으로 처리하고, **0이 아닌 이벤트 타입은 종료로 처리**합니다. 실제 정상 양치 종료에서는 `type=1`이 확인되었지만, 사용자가 동작 중 전원 버튼 등으로 강제/조기 정지하는 경우 다른 non-zero 종료 코드가 들어올 수 있습니다.

기존 구현은 종료를 `type=1`로만 제한하여 이런 강제 정지 패킷을 수신하고도 무시할 수 있었고, 그 결과 SmartThings의 `motionSensor`가 계속 `active`로 남는 문제가 있었습니다. v1.10.2부터는 모든 non-zero `0x3003` 이벤트를 종료로 처리하여 즉시 `motionSensor=inactive`로 반영합니다.

또한 종료 패킷 자체가 유실되거나 해석할 수 없는 경우를 대비해 T700i 전용 30초 activity watchdog을 최종 안전망으로 유지합니다.

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
  | live type!=0
  | cancel watchdog
  v
IDLE + completed session

BRUSHING
  |
  | no repeated type=0 advertisement
  | and no decodable end event for 30s
  v
IDLE + watchdog fallback
```

과거 종료 패킷은 저장된 기록보다 새로운 경우에만 메타데이터를 갱신할 수 있으며, 현재 상태를 `BRUSHING -> IDLE`로 변경하지 않습니다.

## 강제 정지 처리

- 새로운 `live type=0` 시작 이벤트를 받으면 `motionSensor=active`로 변경하고 30초 watchdog을 시작합니다.
- 양치 중 반복되는 `type=0` 광고를 받으면 watchdog 제한 시간을 다시 30초로 갱신합니다.
- 동일한 `frmCnt`의 중복 광고는 상태 이벤트 중복 처리는 하지 않지만, T700i가 계속 동작 중임을 나타내는 `type=0` 광고라면 watchdog은 갱신합니다.
- `live type!=0` 이벤트를 받으면 T700i 종료 이벤트로 판단하고 watchdog을 무효화한 뒤 즉시 `motionSensor=inactive`로 변경합니다.
- 정상 완료에서는 일반적으로 `type=1`과 점수가 함께 들어오며, 강제/조기 정지에서는 다른 non-zero type 또는 점수가 없는 종료 패킷이 들어올 수 있습니다.
- 종료 패킷이 아예 수신되지 않으면 마지막 T700i `type=0` 활동 광고 이후 30초 뒤 watchdog이 `motionSensor=inactive`로 복구합니다.
- watchdog fallback은 종료 시각·점수 같은 완료 세션 메타데이터를 임의로 만들지 않습니다. 이후 유효한 종료 기록이 들어오면 기존 메타데이터 갱신 규칙을 따릅니다.

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

## 로그 확인

양치 시작 로그에는 다음 내용이 포함되어야 합니다.

```text
type=0 ... live=true ... start_ts=...
```

정상 양치 종료는 보통 다음과 같습니다.

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

강제/조기 정지 패킷이 다른 종료 코드를 사용하는 경우에는 다음처럼 `type`이 1이 아닌 non-zero 값일 수 있습니다.

```text
type=<non-zero> ... live=true ... duration=... score=-
```

정상적으로 종료 이벤트가 해석되면 이어서 다음 완료 로그가 표시됩니다.

```text
BLE MQTT toothbrush session complete ...
```

종료 이벤트 자체가 유실되어 watchdog이 동작한 경우 다음과 같은 경고 로그가 표시됩니다.

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```

배터리 이벤트는 완료된 양치 세션 이벤트와 별도로 수신될 수 있습니다.
