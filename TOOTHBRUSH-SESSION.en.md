# T700i Session Tracking

[한국어](TOOTHBRUSH-SESSION.md)

This design is based on behavior observed on the actual SmartThings Hub runtime.

```text
start:                 type=0, current timestamp, live=true
normal end:            type=1, current timestamp, score present
forced/early stop:     type=1, previous completed-session timestamp may be reused
battery:               separate standard MiBeacon event
```

For the T700i MiBeacon toothbrush event (`eid=12291 / 0x3003`), `type=0` means brushing start and **any non-zero event type is an end candidate**.

v1.10.2 expanded end handling to all non-zero `0x3003` types. v1.10.3 added raw BLE diagnostics so the actual forced-stop packet could be inspected before child resolution and `frmCnt` duplicate suppression.

A v1.10.3 forced-stop test revealed this exact pattern:

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

The forced-stop packet still uses `type=1`, but its embedded `event_ts=1786192057` is the timestamp of the previous completed brushing session instead of the current stop time. The previous 60-second live/history filter therefore classified this packet as historical and left `motionSensor=active` until the 30-second watchdog fired.

## v1.10.4 stale-stop handling

Starting with v1.10.4, a non-zero `0x3003` packet is inferred as the end of the current brushing session when all of the following are true:

- the current T700i session is `active`
- stored `start_ts > 0`
- `type != 0`
- the embedded timestamp is outside the 60-second live window
- Gateway receive time `gwts` is at or after `start_ts`
- `gwts - start_ts <= 10 minutes`
- the advertisement is new after normal `frmCnt` duplicate suppression

When those conditions are met, the raw embedded timestamp is retained for diagnostics while `gwts` is used as the effective end time for state and session calculations.

```text
raw_event_ts       = stale timestamp carried by the packet
effective_end_ts   = gwts
duration           = effective_end_ts - start_ts
motionSensor       = inactive
watchdog           = invalidated
```

For the observed sample, the start timestamp was `1786207643` and the forced-stop receive timestamp was `1786207649`, so the expected duration is about 6 seconds.

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

A stale end packet received while no current session is active remains historical and does not change current state. The driver therefore does not treat every old non-zero packet as a live end event.

## 30-second watchdog

The T700i activity watchdog remains as the final fallback when the end advertisement itself is lost or cannot be decoded.

- a new live `type=0` start arms the watchdog
- repeated `type=0` advertisements refresh it
- a normal live end or a v1.10.4 inferred stale stop invalidates it immediately
- if no end advertisement arrives, `motionSensor=inactive` is forced after 30 seconds of inactivity
- watchdog fallback does not invent completion time or score metadata

## Raw BLE diagnostics

Since v1.10.3, every `pdid=6032` packet is logged before child resolution and `frmCnt` duplicate suppression.

```text
BLE MQTT T700i RAW: topic=miio/report did=... mac=... pdid=6032 frmCnt=... gwts=... events=[#1 eid=... eid_hex=... edata=... bytes=... type=... event_ts=...]
```

Important fields:

- `frmCnt`: BLE advertisement sequence
- `gwts`: Gateway receive timestamp
- `eid`: Xiaomi MiBeacon event ID
- `eid_hex`: hexadecimal event ID
- `edata`: original payload
- `bytes`: decoded payload length
- `type`: first byte of the `0x3003` payload
- `event_ts`: embedded timestamp in the `0x3003` payload

When v1.10.4 infers a stale forced stop, an additional diagnostic line is emitted:

```text
BLE MQTT T700i forced stop inferred: ... raw_event_ts=... gwts=... start_ts=... inferred_duration=...s
```

The state log shows both the raw timestamp and the effective timestamp used by the driver:

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

The completion log includes the inferred flag as well:

```text
BLE MQTT toothbrush session complete: ... duration=... forced_stop=true raw_event_ts=...
```

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

## Verification

Normal start:

```text
type=0 ... live=true ... forced_stop=false
motionSensor=active
```

Normal completion:

```text
type=1 ... raw_event_ts=<current> event_ts=<current> live=true forced_stop=false
motionSensor=inactive
BLE MQTT toothbrush session complete
```

Forced/early stop that reuses the previous completion timestamp:

```text
T700i forced stop inferred
motionSensor=inactive
... raw_event_ts=<previous session> event_ts=<gwts> forced_stop=true ...
BLE MQTT toothbrush session complete ... forced_stop=true
```

No `watchdog timeout` should follow a successfully inferred forced stop.

Only when the end advertisement itself is absent should the fallback appear:

```text
BLE MQTT toothbrush watchdog timeout: ... inactivity=30s ... forcing motion inactive
```
