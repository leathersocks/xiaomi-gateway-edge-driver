# mgl03 openmiio MQTT setup

Confirm broker:

```powershell
Test-NetConnection 192.168.10.41 -Port 1883
```

If the broker is not running:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip 192.168.10.41 --force-restart
```

Probe BLE:

```powershell
py .\mqtt-ble-probe-v2.py --host 192.168.10.41
```

The probe subscribes to `#`, uses MQTT keepalive, and reconnects after a
connection failure.

SmartThings mgl03 settings:

```text
IP address              192.168.10.41
BLE via MQTT            On
BLE MQTT broker IP      blank
BLE MQTT port           1883
```

The driver topic is fixed internally to `#`.

Do not expose TCP 1883 to the Internet.

Gateway reboot note: the helper starts openmiio as a runtime process. If mgl03
reboots and TCP 1883 is no longer listening, rerun the helper.


## v1.8.0 gateway role

The Edge runtime no longer checks a static mgl03 model table.
Enable `BLE via MQTT` only on the gateway where this openmiio/Mosquitto
service is running.
