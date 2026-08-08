# Xiaomi Gateway Edge Driver v1.8.2-runtime-fix

This release fixes the runtime error found after the dynamic-gateway migration.

## Fixes

- Removed the stale `gateway_for_device()` call from `mqtt_ble.start()`.
- MQTT applicability now means only "this device is a Xiaomi Gateway parent".
- `BLE via MQTT` is evaluated separately as the enable/disable preference.
- Turning `BLE via MQTT` Off now stops/invalidate an existing listener first.
- Dynamic gateway discovery DNI generation no longer needs a bitwise operator.
- Automatic BLE child registration/parent selection from v1.8.1 is retained.

## Gateway settings

```text
IP address
Health check interval
Auto child discovery
TOKEN
Zigbee state polling
Zigbee poll interval
BLE via MQTT
BLE MQTT broker IP
BLE MQTT port
```

## Automatic BLE

```text
MQTT BLE event
 -> pdid 5860 + MAC
 -> search all Gateway parents for ble-<MAC>
 -> existing child: preserve parent/name
 -> new child: existing BLE parent, otherwise MQTT source
 -> create automatically
```

## MQTT

```text
Topic             #
Keepalive         30s
PINGREQ           15s
PINGRESP timeout  10s
Receive tick       5s
Reconnect          3s
```

`packageKey` remains `xiaomi-gateway`.
