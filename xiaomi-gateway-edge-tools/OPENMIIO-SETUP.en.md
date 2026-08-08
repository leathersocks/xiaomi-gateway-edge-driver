# Xiaomi mgl03 openmiio / MQTT Setup Guide

[한국어](OPENMIIO-SETUP.md)

This document explains how to deliver BLE events from a **Xiaomi Mijia Smart Multi-Mode Gateway (`lumi.gateway.mgl03`)** to the SmartThings Edge Driver by using `openmiio_agent` and an MQTT Broker.

> This procedure is based on the current repository's `install-openmiio-mgl03-v5.py` and `mqtt-ble-probe-v2.py`.
>
> The target Gateway is the **mgl03 family**. The installation procedure and binary for `mgl001` are different, so do not use this script on an `mgl001`.

---

## 1. Architecture

BLE advertisements reach SmartThings through the following path:

```text
Xiaomi BLE device
      ↓
Xiaomi Gateway mgl03
      ↓
openmiio_agent
      ↓
Mosquitto MQTT Broker :1883
      ↓
miio/report / central/report
      ↓
Xiaomi Gateway SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

The Edge Driver subscribes to MQTT topic `#`. Actual BLE processing uses `_async.ble_event` messages found in `miio/report` and `central/report`.

---

## 2. Verified target environment

The current installer targets the following environment:

| Item | Value |
|---|---|
| Internal model | `lumi.gateway.mgl03` |
| Verified firmware family | `1.5.0.x` |
| openmiio binary | `openmiio_agent` MIPS v1.2.1 |
| Telnet port | TCP `23` |
| MQTT port | TCP `1883` |
| Telnet user | `admin` |
| openmiio install path | `/data/openmiio_agent` |
| openmiio log | `/var/log/st-openmiio.log` |

Telnet availability and behavior may differ by firmware or regional variant.

---

## 3. Requirements

The administration PC needs:

- Python 3
- Internet access
  - Used while the installer downloads the `openmiio_agent` MIPS v1.2.1 binary
- TCP `23` and TCP `1883` connectivity from the PC to the Xiaomi Gateway
- Telnet already enabled on the Xiaomi Gateway

`install-openmiio-mgl03-v5.py` itself does not require a Xiaomi miIO TOKEN or Gateway Key.

### Check Telnet status

Set the Gateway IP in Windows PowerShell:

```powershell
$GatewayIP = "192.168.1.100"
Test-NetConnection $GatewayIP -Port 23
```

Expected result:

```text
TcpTestSucceeded : True
```

If it is `False`, prepare the mgl03 so that Telnet can be used first. This installer **does not enable a closed Telnet port by itself**.

---

## 4. Check MQTT Broker status

First check TCP `1883` on the Gateway:

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

If you already get:

```text
TcpTestSucceeded : True
```

an MQTT Broker may already be running.

In that case, an existing `openmiio_agent` may also already be active. Do not immediately use `--force-restart`; check the current state first.

---

## 5. Install and start openmiio

Run from the `xiaomi-gateway-edge-tools` directory:

```powershell
cd xiaomi-gateway-edge-tools
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

The installer performs the following steps:

1. Checks TCP `23` Telnet connectivity
2. Logs in to the mgl03 `admin` shell
3. Checks Gateway information
4. Checks for an existing `openmiio_agent` process
5. Downloads `openmiio_agent` MIPS v1.2.1
6. Verifies the MD5 of the downloaded binary
7. Uploads it to `/data/openmiio_agent` on the Gateway
8. Verifies the MD5 of the remote binary
9. Sets executable permissions
10. Starts `openmiio_agent` with the modules below
11. Checks process status, MQTT `1883`, and logs

The modules started are:

```text
miio
mqtt
cache
central
```

The effective command is:

```text
/data/openmiio_agent miio mqtt cache central --log.level=trace
```

The `z3` module is intentionally not used in this BLE/MQTT configuration.

### Successful completion example

On success, the final output should look similar to:

```text
SUCCESS: MQTT broker is reachable at <Gateway IP>:1883
Next: subscribe to topic # and wait for BLE advertisements.
```

---

## 6. If openmiio is already running

The installer stops by default when it finds an existing `openmiio_agent` process.

This is intentional. It prevents an already working process from being terminated or replaced with a different configuration by mistake.

Use the following option **only when you intentionally want to replace or restart the existing process**:

```powershell
py .\install-openmiio-mgl03-v5.py `
  --gateway-ip $GatewayIP `
  --force-restart
```

> `--force-restart` terminates the existing `openmiio_agent` and starts it again using the configuration from this repository. Do not use it if another openmiio configuration is already working correctly.

---

## 7. Using different ports

Defaults:

```text
Telnet : 23
MQTT   : 1883
```

You can override them if needed:

```powershell
py .\install-openmiio-mgl03-v5.py `
  --gateway-ip $GatewayIP `
  --telnet-port 23 `
  --mqtt-port 1883
```

The SmartThings Edge Driver's `BLE MQTT port` must match the actual Broker port.

---

## 8. Check MQTT BLE events

After openmiio installation, use `mqtt-ble-probe-v2.py` to verify that actual BLE events are reaching MQTT:

```powershell
py .\mqtt-ble-probe-v2.py --host $GatewayIP
```

Defaults:

```text
Port      : 1883
Topic     : #
Reconnect : 3 seconds
Keepalive : 30 seconds
```

You can specify them explicitly if needed:

```powershell
py .\mqtt-ble-probe-v2.py `
  --host $GatewayIP `
  --port 1883 `
  --topic "#" `
  --reconnect 3
```

On a successful connection you should see a message similar to:

```text
Subscribed; waiting for BLE events...
```

When a BLE device advertises, output similar to the following appears:

```text
--- BLE EVENT ---
topic : miio/report
did   : ...
mac   : ...
pdid  : ...
frmCnt: ...
gwts  : ...
evt   : eid=... edata=...
```

### Temperature/humidity events currently decoded by the probe

| Item | EID | Format |
|---|---:|---|
| Temperature | `19457 / 0x4C01` | little-endian IEEE-754 float32 |
| Humidity | `19458 / 0x4C02` | uint8 |
| Battery | `18435 / 0x4803` | uint8 |

Unknown EIDs are still printed with their raw `eid` and `edata`, which makes the probe useful for analyzing new BLE devices.

Press `Ctrl+C` to stop.

---

## 9. SmartThings Gateway settings

In the SmartThings app, open the Xiaomi Gateway device that will handle MQTT and configure:

```text
IP address              = Xiaomi Gateway IP
BLE via MQTT            = On
BLE MQTT broker IP      = blank or MQTT Broker IP
BLE MQTT port           = 1883
```

If the Broker is running on the Xiaomi Gateway itself, `BLE MQTT broker IP` may be left blank. In that case, the Edge Driver uses the Gateway's `IP address` value as the MQTT Broker address.

If the MQTT Broker runs on another LAN device, enter that device's IP address in `BLE MQTT broker IP`.

The Edge Driver's MQTT subscription topic is fixed internally to `#`.

---

## 10. Recommended verification order

Use this sequence to narrow down where a problem occurs:

```text
1. Telnet TCP 23 open
        ↓
2. install-openmiio-mgl03-v5.py completes successfully
        ↓
3. MQTT TCP 1883 open
        ↓
4. mqtt-ble-probe-v2.py subscription succeeds
        ↓
5. BLE advertisements are received
        ↓
6. SmartThings BLE via MQTT = On
        ↓
7. EDGE_CHILD is created automatically and values update
```

---

## 11. Troubleshooting

### `Telnet ...:23 is not open`

Possible causes:

- Telnet is not enabled on the mgl03
- The Gateway IP is wrong
- A firewall/VLAN blocks traffic between the PC and Gateway

Check:

```powershell
Test-NetConnection $GatewayIP -Port 23
```

### `Existing openmiio_agent detected`

An existing openmiio process is running.

If the system is working correctly, leaving it unchanged is safer. Use `--force-restart` only when you are certain you want this script to replace that process.

### MQTT `1883` does not open after installation

If Telnet access to the Gateway is available, inspect the log:

```sh
cat /var/log/st-openmiio.log
```

Or only the latest lines:

```sh
tail -n 100 /var/log/st-openmiio.log
```

Check the process:

```sh
ps w | grep '[o]penmiio_agent'
```

Check the MQTT listener:

```sh
netstat -ltnp 2>/dev/null | grep ':1883 '
```

### MQTT connects but no BLE events appear

Check the following in order:

- Whether the BLE device is actually advertising
- Whether `mqtt-ble-probe-v2.py` receives `miio/report` or `central/report`
- Whether `_async.ble_event` is present in the payload
- Whether the Gateway's openmiio log contains errors

### BLE devices are not created in SmartThings

- Confirm `BLE via MQTT = On`
- Check `BLE MQTT broker IP`
- Confirm `BLE MQTT port = 1883`
- Confirm that the SmartThings Hub can reach TCP `1883` on the Broker IP
- First verify actual BLE events with `mqtt-ble-probe-v2.py`

---

## 12. Notes after a Gateway reboot

The current helper starts `openmiio_agent` as a **runtime process**.

After the Gateway reboots, `openmiio_agent` and TCP `1883` may not automatically return.

Check first:

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

If the port is not open, check Telnet `23` and then run the installer helper again:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

Use `--force-restart` only when you determine that an existing process remains and should be restarted.

---

## 13. Security notes

- Do not expose TCP `23` Telnet or TCP `1883` MQTT directly to the Internet.
- Keep the Gateway and MQTT Broker inside a trusted LAN/VLAN.
- Do not publish ports `23` or `1883` externally through router port forwarding.
- Do not post real Gateway TOKENs, BLE KEYs, or Gateway Keys in GitHub Issues or logs.
- This installer does not require a miIO TOKEN/Gateway Key and does not print those secrets.
- Use this procedure only on Xiaomi Gateways that you own or administer.

---

## 14. Related files

| File | Purpose |
|---|---|
| `install-openmiio-mgl03-v5.py` | Installs openmiio_agent on mgl03 and starts the MQTT/BLE configuration |
| `mqtt-ble-probe-v2.py` | MQTT subscription and BLE event diagnostics |
| `README.en.md` | Overview of the tools directory |
| `../README.en.md` | SmartThings Edge Driver installation and usage |

---

## Summary

A typical setup sequence is:

```powershell
$GatewayIP = "192.168.1.100"

# 1. Check Telnet
Test-NetConnection $GatewayIP -Port 23

# 2. Install/start openmiio
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP

# 3. Check MQTT
Test-NetConnection $GatewayIP -Port 1883

# 4. Check BLE events
py .\mqtt-ble-probe-v2.py --host $GatewayIP
```

Then enable `BLE via MQTT` on the corresponding Gateway in SmartThings.
