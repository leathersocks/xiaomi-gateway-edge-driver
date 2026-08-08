# T700i Session Tracking

[한국어](TOOTHBRUSH-SESSION.md)

Observed runtime data used for this design:

```text
start:      type=0, live=true
normal end: type=1, live=true, score present
forced end: type!=0 possible, score may be absent
battery:    separate standard MiBeacon event
```

For the T700i MiBeacon toothbrush event (EID `0x3003`), `type=0` is treated as brushing start and **any non-zero event type is treated as brushing finish**. Normal completed brushing has been observed with `type=1`, but an early/manual stop may use another non-zero finish code.

The previous implementation accepted only `type=1` as finish. That could receive but ignore a forced-stop packet, leaving SmartThings `motionSensor` stuck at `active`. Starting with v1.10.2, every non-zero `0x3003` event is handled as an end event and immediately sets `motionSensor=inactive`.

A dedicated 30-second T700i activity watchdog remains as a final fallback when the end packet itself is lost or cannot be decoded.

Starting with v1.10.3, the driver also emits a T700i-specific raw BLE diagnostic log before child lookup and `frmCnt` duplicate suppression. This preserves the original `EID` and `edata` even when multiple Gateways receive the same packet or no SmartThings state event is emitted.

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

Historical end packets can update metadata only when newer; they never change the current BRUSHING state to IDLE.

## Forced-stop handling

- A new `live type=0` start event sets `motionSensor=active` and arms a 30-second watchdog.
- Repeated `type=0` advertisements while brushing refresh the watchdog deadline.
- A duplicate advertisement with the same `frmCnt` is still ignored for duplicate state processing, but if it contains the T700i `type=0` event it refreshes the watchdog because it confirms that the toothbrush is still active.
- A `live type!=0` event is treated as a T700i finish event, invalidates the watchdog, and immediately sets `motionSensor=inactive`.
- Normal completion typically provides `type=1` with a score. An early/manual stop may provide another non-zero type or an end packet without a score.
- If no end packet is received at all, the watchdog restores `motionSensor=inactive` 30 seconds after the last T700i `type=0` activity advertisement.
- The watchdog fallback does not invent completion metadata such as end time or score. A later valid end record still follows the existing metadata update rules.

## Raw BLE diagnostics

In v1.10.3 and later, each `pdid=6032` packet is logged in this format before duplicate suppression:

```text
BLE MQTT T700i RAW: topic=miio/report did=... mac=... pdid=6032 frmCnt=... gwts=... events=[#1 eid=... eid_hex=... edata=... bytes=... type=... event_ts=...]
```

Important fields:

- the Gateway/source label at the beginning of the log line
- `frmCnt`: BLE advertisement sequence
- `gwts`: Gateway receive timestamp
- `eid`: Xiaomi MiBeacon event ID
- `eid_hex`: hexadecimal event ID
- `edata`: original Gateway payload
- `bytes`: decoded payload length
- `type`: first byte for `eid=12291 / 0x3003`; `0` means start and non-zero is an end candidate
- `event_ts`: embedded timestamp decoded from the `0x3003` payload

For a forced-stop test, inspect the `T700i RAW` line immediately after pressing the stop/power button.

A non-zero `0x3003` event can be handled immediately:

```text
BLE MQTT T700i RAW: ... eid=12291 eid_hex=0x3003 edata=... type=2 event_ts=...
```

If another EID appears instead, that event may represent a separate T700i stop signal and should be analyzed further:

```text
BLE MQTT T700i RAW: ... eid=<not 12291> eid_hex=... edata=... type=- event_ts=-
```

If no `T700i RAW` line appears at all after the forced stop, either the toothbrush did not advertise an end event or the Gateway/openmiio path did not forward it; the 30-second watchdog remains necessary in that case.

When two Gateways subscribe to the same MQTT broker, the same `frmCnt` can appear once per Gateway in raw diagnostics. This is intentional: raw logging happens before duplicate suppression, while normal SmartThings state processing continues to use the existing duplicate filter.

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

A normal completed brushing usually includes:

```text
type=1 ... live=true ... duration=... duration_text=... score=...
```

When an early/manual stop uses another finish code, the log may instead show a non-zero type and no score:

```text
type=<non-zero> ... live=true ... duration=... score=-
```

A successfully decoded end event is followed by:

```text
BLE MQTT toothbrush session complete ...
```

If the end event itself is lost and the watchdog handles the stop, a warning similar to the following is logged:

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```

Battery may arrive independently after the completed-session event.
