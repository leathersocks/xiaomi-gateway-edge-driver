# T700i 양치 세션 추적

[English](TOOTHBRUSH-SESSION.en.md)

이 설계에는 실제 런타임에서 관찰한 다음 데이터를 사용했습니다.

```text
start: type=0, live=true
end:   type=1, live=true, score present
battery: separate standard MiBeacon event
```

강제로 칫솔 동작을 중지하는 경우 정상 종료 패킷(`type=1`)이 수신되지 않아 SmartThings의 `motionSensor`가 계속 `active`로 남는 사례가 확인되었습니다. 이를 보완하기 위해 T700i 전용 30초 activity watchdog을 사용합니다.

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
  | live type=1
  | cancel watchdog
  v
IDLE + completed session

BRUSHING
  |
  | no repeated type=0 advertisement for 30s
  v
IDLE + watchdog fallback
```

과거 종료 패킷은 저장된 기록보다 새로운 경우에만 메타데이터를 갱신할 수 있으며, 현재 상태를 `BRUSHING -> IDLE`로 변경하지 않습니다.

## Watchdog 동작

- 새로운 `live type=0` 시작 이벤트를 받으면 `motionSensor=active`로 변경하고 30초 watchdog을 시작합니다.
- 양치 중 반복되는 `type=0` 광고를 받으면 watchdog 제한 시간을 다시 30초로 갱신합니다.
- 동일한 `frmCnt`의 중복 광고는 상태 이벤트 중복 처리는 하지 않지만, T700i가 계속 동작 중임을 나타내는 `type=0` 광고라면 watchdog은 갱신합니다.
- 정상 `live type=1` 종료 이벤트를 받으면 watchdog을 무효화하고 즉시 `motionSensor=inactive`로 변경합니다.
- 마지막 T700i `type=0` 활동 광고 이후 30초 동안 추가 광고나 정상 종료 이벤트가 없으면 강제 중지 또는 종료 패킷 유실로 판단하여 `motionSensor=inactive`로 복구합니다.
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

정상 양치 종료 로그에는 다음 내용이 포함되어야 합니다.

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

그리고 두 번째 로그 줄에 다음 내용이 표시됩니다.

```text
BLE MQTT toothbrush session complete ...
```

강제 중지 또는 종료 패킷 유실로 watchdog이 동작한 경우 다음과 같은 경고 로그가 표시됩니다.

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```

배터리 이벤트는 완료된 양치 세션 이벤트와 별도로 수신될 수 있습니다.
