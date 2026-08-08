# TOKEN Guide

The SmartThings setting is named:

```text
TOKEN
```

It accepts the Xiaomi gateway's own 16-byte / 32-hex-character miIO token.

It is used only for authenticated local non-BLE child discovery and Zigbee
state polling. It is not a BLE sensor token, BLE bind key, or mgl001 Gateway Key.

The BLE-over-MQTT path does not require this token.

Security note: a SmartThings Device Profile preference is configuration storage,
not a dedicated secret vault. The driver does not print the TOKEN in logcat.
