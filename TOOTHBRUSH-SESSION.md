# T700i 양치 세션 추적

[English](TOOTHBRUSH-SESSION.en.md)

이 설계에는 실제 런타임에서 관찰한 다음 데이터를 사용했습니다.

```text
start: type=0, live=true
end:   type=1, live=true, score present
battery: separate standard MiBeacon event
```

## 상태 머신

```text
IDLE
  |
  | live type=0
  v
BRUSHING
  |
  | repeated live type=0
  | keep first start timestamp
  |
  | live type=1
  v
IDLE + completed session
```

과거 종료 패킷은 저장된 기록보다 새로운 경우에만 메타데이터를 갱신할 수 있으며, 현재 상태를 `BRUSHING -> IDLE`로 변경하지 않습니다.

## 런타임 필드

```text
active         boolean
start_ts       Unix UTC
last_ts        Unix UTC
last_score     integer 0..100
last_duration  seconds
```

## 로그 확인

양치 시작 로그에는 다음 내용이 포함되어야 합니다.

```text
type=0 ... live=true ... start_ts=...
```

양치 종료 로그에는 다음 내용이 포함되어야 합니다.

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

그리고 두 번째 로그 줄에 다음 내용이 표시됩니다.

```text
BLE MQTT toothbrush session complete ...
```

배터리 이벤트는 완료된 양치 세션 이벤트와 별도로 수신될 수 있습니다.
