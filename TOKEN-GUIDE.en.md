# TOKEN Guide

[한국어](TOKEN-GUIDE.md)

The SmartThings setting is named:

```text
TOKEN
```

Enter the **miIO TOKEN of the Xiaomi Gateway itself** in this field.

The format is:

```text
16 bytes / 32 hexadecimal characters
```

For example:

```text
00112233445566778899aabbccddeeff
```

> The value above is only an example of the format and is not a real TOKEN.

## What the TOKEN is used for

This TOKEN is used only for the following features:

- Authenticated local discovery of Xiaomi child devices
- Zigbee device state polling

The driver uses this value when sending authenticated requests to the Xiaomi Gateway's local miIO API.

## How this TOKEN differs from other keys

The `TOKEN` described in this document is different from all of the following:

- BLE sensor TOKEN
- BLE Bind Key / BLE KEY
- mgl001 Gateway Key

Do not enter any of those values in the SmartThings `TOKEN` setting.

## BLE over MQTT and TOKEN

This TOKEN is not required when BLE data is delivered through MQTT.

```text
Xiaomi BLE device
    ↓
Gateway / openmiio
    ↓
MQTT
    ↓
SmartThings Edge Driver
```

In this path, the Gateway already forwards BLE events to MQTT, so the Edge Driver does not authenticate directly with individual BLE sensors.

## Security notes

A SmartThings Device Profile preference is configuration storage, not a dedicated secret vault.

For that reason, the TOKEN should be handled as follows:

- Do not store the TOKEN in a GitHub repository.
- Do not put a real TOKEN in README files, CHANGELOG files, or logs.
- Do not share the TOKEN with other users.
- Check screenshots and logs before publishing them to make sure the TOKEN is not included.

This driver does not print the configured TOKEN value to `logcat`.

## Summary

```text
SmartThings setting : TOKEN
Value               : Xiaomi Gateway miIO TOKEN
Length              : 16 bytes
Representation      : 32 hexadecimal characters
Used for            : authenticated child discovery / Zigbee state polling
Needed for BLE MQTT : No
Same as BLE KEY      : No
Same as Gateway Key : No
```
