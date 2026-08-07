# Xiaomi Gateway Edge Driver v1.3.0-child-r3

Based on the verified `v1.2.6f-final` distribution.

This version adds SmartThings `EDGE_CHILD` device registration under each
Xiaomi gateway while preserving the existing gateway health/diagnostics logic.

## What this version adds

Each gateway has four `Child devices` preference fields because SmartThings
limits a single string preference to 255 characters.

Use them as one continuous manifest:

```text
Child devices
Child devices 2
Child devices 3
Child devices 4
```

Each field accepts the same format, one child per line:

```text
type|key|label|model
```

Supported child types:

```text
temp-humidity
contact
motion
water
generic
```

Example:

```text
temp-humidity|ble-a4c138123456|Living Room Sensor|LYWSD02MMC
contact|zigbee-00158d0001234567|Front Door|lumi.sensor_magnet.aq2
motion|zigbee-00158d0007654321|Hall Motion|lumi.sensor_motion.aq2
```

The four fields are concatenated internally before parsing, providing roughly
1 KB of manifest capacity while keeping every Device Profile preference within
SmartThings' 255-character limit.

## SmartThings child behavior

The driver uses `EDGE_CHILD` devices with:

```text
parent_device_id
parent_assigned_child_key
```

The child key must be unique under each parent gateway.

Saving the gateway preferences, refreshing the gateway, or restarting the
driver triggers an idempotent child sync.

Existing children are reused by their parent-assigned key, so repeated syncs
do not create duplicates.

## Child profiles

```text
xiaomi-child-temp-hum
  temperatureMeasurement
  relativeHumidityMeasurement
  battery
  presenceSensor
  refresh

xiaomi-child-contact
  contactSensor
  battery
  presenceSensor
  refresh

xiaomi-child-motion
  motionSensor
  battery
  presenceSensor
  refresh

xiaomi-child-water
  waterSensor
  battery
  presenceSensor
  refresh

xiaomi-child-generic
  presenceSensor
  refresh
```

## Online / offline behavior

By default, child availability follows the parent gateway.

When the gateway is reachable:

```text
child online
presence = present
```

When the gateway reaches its configured offline failure threshold:

```text
child offline
presence = not present
```

This behavior can be disabled with:

```text
Child online state follows gateway
```

## Important current limitation

This version adds the **SmartThings child registration framework**, but it
does not yet read live temperature/humidity/contact/motion/etc. values from
the Xiaomi gateway.

The existing driver intentionally does not enable Telnet or MQTT and does not
store a Xiaomi token. On stock Xiaomi Multimode Gateway firmware, commonly
used local integrations obtain child-device data using additional gateway
credentials and a local gateway service path.

For this reason the child profiles are created now, but measurement/control
transport remains separate from registration.

## Install

No setup script is required:

```powershell
cd C:\SmartThings\xiaomi-gateway-edge-driver-v1.3.0-child-r3
smartthings edge:drivers:package . --install
```

The package keeps:

```text
packageKey: xiaomi-gateway
```

so it updates the existing Xiaomi Gateway driver.

## Removing a child

The driver intentionally does not auto-delete children when a manifest line is
removed.

To permanently remove a child:

1. Remove the child line from the parent gateway's `Child devices` preference.
2. Delete the child device from SmartThings.

If the manifest line remains, a deleted child will be recreated at the next sync.

## Existing gateway functions retained

- miIO UDP 54321 health check
- Status / IP / Latency / Last Seen / Failures
- KST Last Seen
- scheduled and manual refresh
- presenceSensor / healthCheck
- 3-failure default offline hysteresis
- no MQTT
- no Telnet
- no BLE scanning by the SmartThings Hub
- no Xiaomi token stored by this driver
