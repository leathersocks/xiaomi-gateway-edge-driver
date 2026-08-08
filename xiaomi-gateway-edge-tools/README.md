# Xiaomi Gateway Optional Tools v1.10.1

These files are intentionally separated from the SmartThings Edge driver ZIP.

Contents:
- `install-openmiio-mgl03-v5.py` — gateway-side openmiio/MQTT helper
- `mqtt-ble-probe-v2.py` — raw MQTT/BLE diagnostic subscriber
- `OPENMIIO-SETUP.md` — operational notes

They are not required by the SmartThings Edge Lua runtime or Device Profiles.
Keep them only on the administration PC.

Do not expose an unauthenticated MQTT broker or Telnet service to the Internet.
