# MGL03 openmiio/MQTT runtime

[한국어](OPENMIIO-RUNTIME.md)

When BLE devices are enabled, this Edge Driver needs an MQTT runtime that
provides `miio/report` and `central/report`. MGL03 installation, updates, boot
startup, integrity checks, and diagnostics are maintained centrally in
[`mgl03-homekit-bridge`](https://github.com/leathersocks/mgl03-homekit-bridge).
This repository no longer keeps a duplicate installer that modifies the
gateway directly.

## Install openmiio only, without Telnet

Run the following on a Windows PC in the same LAN:

```powershell
Set-Location C:\Git\mgl03-homekit-bridge
py -m pip install -r .\requirements-installer.txt
py .\scripts\install_no_telnet.py `
  --gateway-ip 192.168.10.41 `
  --mode openmiio
```

Enter that MGL03's 32-character miIO token at the hidden prompt. The supported
target is `lumi.gateway.mgl03` firmware `1.5.0` through `1.5.4`. The installer
does not open Telnet port 23. It verifies artifacts with SHA-256, rolls back on
failure, and checks MQTT TCP `1883` readiness.

`openmiio` mode does not require the HomeKit bridge binary or TCP `51826`. If a
complete `mgl03-homekit-bridge` installation is already healthy, the Edge
Driver can share the same Mosquitto/openmiio connection and no reinstall is
needed.

## Edge Driver settings

Configure the Gateway in the SmartThings app as follows:

```text
BLE via MQTT       = On
BLE MQTT broker IP = MGL03 IP address
BLE MQTT port      = 1883
```

The driver subscribes only to `miio/report` and `central/report`, not wildcard
topic `#`. To inspect MQTT events from a PC, run the diagnostic tool from the
runtime repository:

```powershell
py .\scripts\mqtt_ble_probe.py --host 192.168.10.41
```

Do not expose unauthenticated MQTT port 1883 to the internet. Keep it inside a
trusted LAN or VLAN.
