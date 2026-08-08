# T700i Session Tracking

[한국어](TOOTHBRUSH-SESSION.md)

Observed real runtime data used for this design:

```text
start: type=0, live=true
end:   type=1, live=true, score present
battery: separate standard MiBeacon event
```

A forced toothbrush stop can occur without a normal `type=1` end packet. In that case SmartThings may otherwise leave `motionSensor` in the `active` state. A dedicated 30-second T700i activity watchdog is used as a fallback.

## State machine

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

Historical end packets can update metadata only when newer; they never change
BRUSHING -> IDLE.

## Watchdog behavior

- A new `live type=0` start event sets `motionSensor=active` and arms a 30-second watchdog.
- Repeated `type=0` advertisements while brushing refresh the watchdog deadline.
- A duplicate advertisement with the same `frmCnt` is still ignored for duplicate state processing, but if it contains the T700i `type=0` event it refreshes the watchdog because it confirms that the toothbrush is still active.
- A normal `live type=1` end event invalidates the watchdog and immediately sets `motionSensor=inactive`.
- If no additional T700i `type=0` activity advertisement or normal end event is seen for 30 seconds, the driver treats it as a forced stop or lost end packet and restores `motionSensor=inactive`.
- The watchdog fallback does not invent completion metadata such as end time or score. A later valid end record still follows the existing metadata update rules.

## Runtime fields

```text
active                boolean
start_ts              Unix UTC
last_ts               Unix UTC
last_score            integer 0..100
last_duration         seconds
watchdog_generation   runtime generation counter
last_activity_ts      runtime Unix UTC
```

`watchdog_generation` and `last_activity_ts` are non-persistent runtime fields.

## Log verification

Start should include:

```text
type=0 ... live=true ... start_ts=...
```

A normal end should include:

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

and a second line:

```text
BLE MQTT toothbrush session complete ...
```

If the watchdog handles a forced stop or lost end packet, a warning similar to the following is logged:

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```

Battery may arrive independently after the completed-session event.
