# T700i Session Tracking

[한국어](TOOTHBRUSH-SESSION.md)

Observed real runtime data used for this design:

```text
start: type=0, live=true
end:   type=1, live=true, score present
battery: separate standard MiBeacon event
```

## State machine

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

Historical end packets can update metadata only when newer; they never change
BRUSHING -> IDLE.

## Runtime fields

```text
active         boolean
start_ts       Unix UTC
last_ts        Unix UTC
last_score     integer 0..100
last_duration  seconds
```

## Log verification

Start should include:

```text
type=0 ... live=true ... start_ts=...
```

End should include:

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

and a second line:

```text
BLE MQTT toothbrush session complete ...
```

Battery may arrive independently after the completed-session event.
