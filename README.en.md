# Xiaomi Gateway SmartThings Edge Driver

[한국어](README.md)

This is an unofficial SmartThings Edge Driver that registers a Xiaomi Gateway with a SmartThings Hub as a **LAN device**, monitors Gateway status, and lets supported Xiaomi Zigbee/BLE child devices appear in SmartThings.

The current version uses local Xiaomi miIO communication and MQTT and is designed to operate inside the LAN without requiring Xiaomi Cloud connectivity.

---

## Main features

### Xiaomi Gateway

- Xiaomi miIO UDP `54321` health check
- Gateway online / degraded / offline state management
- Configurable health-check interval
- miIO TOKEN-based Xiaomi child-device discovery
- State polling for supported Zigbee temperature/humidity devices
- BLE over MQTT reception
- Multiple Xiaomi Gateways can be registered

#### Gateways verified in real use

The following Xiaomi Gateways have been verified in an actual SmartThings Hub environment.

| Product | Internal model | Product model / SKU | Verified firmware | Verified features |
|---|---|---|---|---|
| Xiaomi Smart Home Hub 2 | `lumi.gateway.mgl001` | `ZNDMWG04LM` / `BHR6765GL` | `1.0.8_0013` | miIO health check / TOKEN-based child discovery / Zigbee state polling |
| Xiaomi Mijia Smart Multi-Mode Gateway | `lumi.gateway.mgl03` | `ZNDMWG03LM` / `ZNDMWG02LM` family | `1.5.0_0026` | miIO health check / openmiio / MQTT BLE reception |

> The firmware versions above are versions verified in the actual test environment. They do not define minimum or maximum supported firmware versions. Behavior may differ by regional variant, firmware, or hardware revision even when the internal model is the same.

### Xiaomi BLE devices

The following BLE devices have been verified in real operation.

| Type | Model | Product model | pdid | Supported features |
|---|---|---|---:|---|
| Xiaomi BLE temperature/humidity sensor | `miaomiaoce.sensor_ht.o2` | `LYWSD02MMC` | `5860` | temperature / humidity / battery |
| Xiaomi Toothbrush T700i | `k0918.toothbrush.t700i` | `MES604` | `6032` | brushing start/end / duration / score / battery |

BLE devices are automatically registered as SmartThings `EDGE_CHILD` devices when MQTT advertisements are received.

### Xiaomi BLE temperature/humidity sensor

The Xiaomi BLE temperature/humidity sensor with `pdid=5860` reports temperature, humidity, and battery values through MiBeacon events.

The driver currently processes the following events:

| Item | EID | Hex | Data format | SmartThings Capability |
|---|---:|---:|---|---|
| Temperature | `19457` | `0x4C01` | little-endian IEEE-754 float32 | `temperatureMeasurement` |
| Humidity | `19458` | `0x4C02` | uint8 | `relativeHumidityMeasurement` |
| Battery | `18435` | `0x4803` | uint8 | `battery` |

Temperature event:

```text
pdid = 5860
EID  = 19457 / 0x4C01
edata = little-endian float32
        ↓
temperatureMeasurement
```

Humidity event:

```text
pdid = 5860
EID  = 19458 / 0x4C02
edata = uint8
        ↓
relativeHumidityMeasurement
```

Battery event:

```text
pdid = 5860
EID  = 18435 / 0x4803
edata = uint8
        ↓
battery
```

The driver reports temperature in Celsius (`°C`) and humidity/battery as percentages (`%`) in SmartThings. Temperature, humidity, and battery events may arrive together in one MQTT advertisement or in separate advertisements.

### Xiaomi Toothbrush T700i

The driver uses T700i MiBeacon events to reflect brushing state in SmartThings.

```text
Brushing starts
    ↓
motionSensor = active

Brushing ends
    ↓
motionSensor = inactive
```

Verified event:

```text
pdid = 6032
EID  = 12291 / 0x3003
```

Supported items:

- Brushing start time
- Brushing end time
- Brushing-duration calculation
- Brushing score
- Battery
- Preserves the first start time when repeated start events are received
- Filters historical BLE events so they do not incorrectly end the current brushing session
- Restores a recent active session after a driver restart

---

### Optional requirements by feature

#### Zigbee child discovery / state polling

The Xiaomi Gateway's own **32-character miIO TOKEN** is required.

```text
16 bytes / 32 hexadecimal characters
```

The TOKEN is different from a BLE KEY or Gateway Key.

See [`TOKEN-GUIDE.en.md`](TOKEN-GUIDE.en.md) for details.

#### Using BLE devices

To use BLE devices such as the Xiaomi BLE temperature/humidity sensor or Xiaomi Toothbrush T700i in SmartThings, the Edge Driver must be able to receive the Xiaomi Gateway's `_async.ble_event` data **through MQTT**.

##### When openmiio is required

openmiio is not required for every user. It is needed **only when using BLE over MQTT and there is no existing MQTT BLE event path that the SmartThings Hub can reach**.

| Usage / environment | Is openmiio required? | Explanation |
|---|---|---|
| Gateway online/offline status only | No | Uses only miIO UDP `54321` health checks |
| Zigbee child discovery / temperature-humidity polling | No | Uses the Gateway IP and miIO TOKEN |
| BLE devices are not used | No | Use `BLE via MQTT = Off` |
| A compatible MQTT Broker already provides `_async.ble_event` | No separate install needed | Configure the existing Broker IP/Port in the Edge Driver |
| BLE devices are used but there is no MQTT BLE event path | **Yes** | Configure openmiio and an MQTT Broker |
| BLE over MQTT on the currently verified `lumi.gateway.mgl03` environment | **Yes** | openmiio forwards BLE events through `miio/report` / `central/report` |

In short, openmiio is not required if you only need Gateway status or Zigbee devices. **When using a BLE temperature/humidity sensor or T700i, first check whether MQTT BLE events are already available. Install openmiio only if they are not.**

The openmiio installer included in this repository currently targets the verified **`lumi.gateway.mgl03` / MIPS environment**. Do not use it unchanged on `mgl001` or another Xiaomi Gateway.

For openmiio installation, MQTT verification, and BLE event diagnostics, see:

- [`xiaomi-gateway-edge-tools/README.en.md`](xiaomi-gateway-edge-tools/README.en.md) — complete openmiio/MQTT administration tools guide
- [`xiaomi-gateway-edge-tools/OPENMIIO-SETUP.en.md`](xiaomi-gateway-edge-tools/OPENMIIO-SETUP.en.md) — mgl03 openmiio installation and troubleshooting

To use BLE over MQTT, the Xiaomi Gateway or another device on the same LAN must provide:

```text
openmiio
Mosquitto or compatible MQTT Broker
```

The default MQTT port is `1883`.

```text
Xiaomi BLE device
      ↓
Xiaomi Gateway / openmiio
      ↓
MQTT Broker
      ↓
SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

The Xiaomi Gateway miIO TOKEN is not required for the BLE-over-MQTT path.

---

### Channel invitation link

[https://bestow-regional.api.smartthings.com/invite/Kr2zLBpAKpjA](https://bestow-regional.api.smartthings.com/invite/Kr2zLBpAKpjA)

### Installation steps

1. Install the **Xiaomi Gateway** driver from the list of available drivers.
2. Return to the SmartThings app after installation completes.
3. Run `Add device` → `Scan nearby`.
4. Open the newly created `Xiaomi Gateway` device and enter the actual Gateway `IP address`.
5. Configure TOKEN, Zigbee polling, and BLE MQTT settings if needed.

> Installing the driver from the channel does not automatically complete Xiaomi Gateway configuration. After scanning for the Gateway in the SmartThings app, you must enter the actual Xiaomi Gateway IP address.

---

## Registering a Xiaomi Gateway

After the driver is installed on the Hub, register a Gateway in the SmartThings app.

1. Open the SmartThings app.
2. Select `Add device`.
3. Run `Scan nearby`.
4. Wait for a `Xiaomi Gateway` device to be created.
5. Open the newly created `Xiaomi Gateway` device.
6. Enter the actual Xiaomi Gateway information under `Settings`.

Only one **unconfigured Xiaomi Gateway registration slot** is created at a time. To use multiple Gateways, finish configuring the first Gateway's IP address, then run `Scan nearby` again to add the next Gateway.

---

## Gateway settings

The Xiaomi Gateway settings in SmartThings contain the following nine items.

| Setting | Description | Default |
|---|---|---:|
| `IP address` | Xiaomi Gateway IPv4 address | none |
| `Health check interval` | miIO health-check interval | 60 seconds |
| `Auto child discovery` | TOKEN-based Xiaomi child discovery | Off |
| `TOKEN` | Xiaomi Gateway miIO TOKEN | none |
| `Zigbee state polling` | state polling for supported Zigbee devices | Off |
| `Zigbee poll interval` | Zigbee polling interval | 60 seconds |
| `BLE via MQTT` | enable BLE MQTT reception | Off |
| `BLE MQTT broker IP` | MQTT Broker IP | if blank, use Gateway IP |
| `BLE MQTT port` | MQTT Broker TCP port | 1883 |

---

## Simplest usage patterns

### Gateway status only

Only this setting is required:

```text
IP address = Xiaomi Gateway IP
```

The driver then uses UDP `54321` only to check Gateway status.

```text
online
  ↓
degraded
  ↓
offline
```

By default, three consecutive failures are required before the Gateway is marked offline.

### Using Zigbee child devices

Add these settings:

```text
Auto child discovery = On
TOKEN                = Xiaomi Gateway miIO TOKEN
```

To poll temperature/humidity values:

```text
Zigbee state polling = On
Zigbee poll interval = 60
```

The main model families currently supported for state polling are Xiaomi Zigbee temperature/humidity devices.

Examples:

```text
lumi.weather.v1
lumi.sensor_ht.v1
```

Automatically discovered models are mapped by name to the following SmartThings child profiles:

- Temperature/Humidity
- Contact
- Motion
- Water Leak
- Generic

However, **real-time state support is not implemented for every automatically registered model.** Current Zigbee polling support focuses on temperature/humidity families.

### Using BLE temperature/humidity sensors / T700i

On the Gateway that provides MQTT, configure:

```text
BLE via MQTT       = On
BLE MQTT broker IP = MQTT Broker IP
BLE MQTT port      = 1883
```

If the Broker IP is left blank, the driver uses that Xiaomi Gateway's `IP address`.

When connected successfully, the driver subscribes to MQTT topic `#` and automatically processes Xiaomi BLE events.

---

## MQTT behavior

```text
Subscription Topic : #
Keepalive          : 30 seconds
PINGREQ            : 15 seconds
PINGRESP timeout   : 10 seconds
Receive timeout    : 5 seconds
Reconnect          : 3 seconds
```

BLE events are processed from:

```text
miio/report
central/report
```

Duplicate-prone `openmiio/log` copies are not used for BLE state processing.

---

## Devices created in SmartThings

A structure similar to the following may be created:

```text
Xiaomi Gateway
├─ Xiaomi Zigbee temperature/humidity sensor
├─ Xiaomi Contact Sensor
├─ Xiaomi Motion Sensor
└─ Xiaomi Water Leak Sensor

BLE MQTT advertisements
├─ BLE temperature/humidity xxxx
└─ BLE toothbrush xxxx
```

BLE devices use a stable child key derived from the MAC address, so repeated advertisements from the same sensor do not continuously create new devices.

If an existing BLE child already exists, the driver preserves its existing SmartThings name and parent relationship when possible.

---

## Verifying normal operation

### Gateway

In the SmartThings app, confirm that Gateway Status shows one of:

```text
online
degraded
offline
```

### BLE / MQTT

If BLE is enabled, verify after a successful connection that:

- A BLE temperature/humidity sensor is created automatically
- Temperature/humidity values update
- T700i brushing start/end state changes when the toothbrush is used
- MQTT automatically reconnects after a connection loss

### Developer logcat verification

Normal users do not need this. For troubleshooting, if SmartThings CLI is installed on a PC, check logs with:

```powershell
smartthings edge:drivers
```

After identifying the driver ID:

```powershell
smartthings edge:drivers:logcat <DRIVER_ID> --hub-address <HUB_IP>
```

A healthy MQTT connection should show logs similar to:

```text
BLE MQTT TCP connected
BLE MQTT CONNACK accepted
BLE MQTT SUBACK accepted
BLE MQTT PINGREQ sent
BLE MQTT PINGRESP OK
```

### T700i

When brushing starts:

```text
motionSensor = active
```

When brushing ends:

```text
motionSensor = inactive
```

Example of a normal completed-session log:

```text
BLE MQTT toothbrush session complete
start=...
end=...
duration=121s
duration_text=02:01
score=...
```

See [`TOOTHBRUSH-SESSION.en.md`](TOOTHBRUSH-SESSION.en.md) for details about T700i session handling.

---

## Troubleshooting

### Xiaomi Gateway is not discovered

- Confirm that the driver is installed on the correct SmartThings Hub through the channel invitation link.
- Run `Scan nearby` again in the SmartThings app.
- Check whether an existing `Xiaomi Gateway` device with a blank IP already exists.
- If an unconfigured Gateway exists, configure its IP first, then scan again.

### Gateway is shown as offline

- Confirm that `IP address` is correct.
- Confirm that the SmartThings Hub can communicate with the Xiaomi Gateway over UDP `54321`.
- If you use VLANs, check firewall/ACL rules between the Hub and Gateway.

### Auto child discovery does not work

- Confirm `Auto child discovery = On`.
- Confirm that the correct **32-character miIO TOKEN** for the Xiaomi Gateway itself is configured.
- BLE sensors are not registered through this feature. BLE devices are dynamically registered from MQTT advertisements.

### BLE devices are not created

- Confirm `BLE via MQTT = On`.
- Check the Broker IP and Port.
- Confirm that openmiio and the MQTT Broker are running on the Xiaomi Gateway.
- Confirm that the SmartThings Hub can reach the MQTT Broker TCP port.
- Confirm that MQTT is actually receiving BLE events on `miio/report` or `central/report`.

### T700i score or battery does not update immediately

T700i score and battery information may not arrive in the same BLE packet.

- Score may be included in the brushing-end event.
- Battery arrives as a separate MiBeacon battery event.

It is therefore normal for the battery value to update separately after a brushing session ends.

---

## Developer source installation

Normal users do not need this procedure. Use it only if you need to develop, modify, or test the driver directly from the repository.

```powershell
git clone https://github.com/leathersocks/xiaomi-gateway-edge-driver.git
cd xiaomi-gateway-edge-driver
smartthings edge:drivers:package . --install
```

On Windows, you can also use:

```powershell
.\install.ps1
```

`sync-ui.ps1` is not a normal installation script. It is a maintenance utility that reapplies the UI definition of the existing Gateway Status Custom Capability.

---

## Security notes

- Never publish a real Gateway TOKEN in GitHub, README files, Issues, or logs.
- Do not store BLE KEYs, BLE Bind Keys, or Gateway Keys in the repository.
- This driver does not print the configured Gateway TOKEN to logcat.
- Do not expose unauthenticated MQTT port `1883` directly to the Internet.
- Keep the MQTT Broker inside a trusted LAN/VLAN.

---

## Currently verified items

The following have been verified in an actual SmartThings Hub environment:

- Xiaomi Gateway miIO UDP health check
- Gateway online/offline state management
- MQTT CONNECT / SUBSCRIBE
- MQTT PINGREQ / PINGRESP keepalive
- MQTT automatic reconnect
- BLE temperature/humidity event reception
- Automatic BLE child-device registration
- Automatic Xiaomi Toothbrush T700i registration
- T700i brushing start → `motionSensor active`
- T700i brushing end → `motionSensor inactive`
- T700i brushing-duration calculation
- T700i score handling
- T700i battery handling

---

## Notes and limitations

- This project is not an official Xiaomi or Samsung SmartThings driver.
- Behavior may differ by Xiaomi Gateway firmware, regional variant, or hardware revision.
- Some Xiaomi Gateways require the correct miIO TOKEN to use `get_device_list` or `get_device_prop_exp`.
- BLE support requires an openmiio/MQTT environment; it does not work from the Xiaomi Gateway feature set alone.
- This is not a universal driver for every Xiaomi Zigbee/BLE model.
- Unsupported devices may be registered as Generic children or may not provide real-time state.
- `sync-ui.ps1` is a maintenance tool for the repository's existing Custom Capability namespace and is not recommended for normal users.

---

## Related documents

- [`TOKEN-GUIDE.en.md`](TOKEN-GUIDE.en.md) — Xiaomi Gateway miIO TOKEN guide
- [`TOOTHBRUSH-SESSION.en.md`](TOOTHBRUSH-SESSION.en.md) — T700i brushing-session handling
- [`xiaomi-gateway-edge-tools/README.en.md`](xiaomi-gateway-edge-tools/README.en.md) — openmiio/MQTT setup and BLE diagnostic tools
- [`CHANGELOG.en.md`](CHANGELOG.en.md) — version history

Information needed to reproduce errors or add device support can be shared through GitHub Issues. Before attaching logs, make sure they do not contain sensitive information such as TOKENs, BLE KEYs, or Gateway Keys.
