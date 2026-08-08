# Xiaomi Gateway Edge Tools

[한국어](README.md)

`xiaomi-gateway-edge-tools` is an **optional administration and diagnostic toolkit for the Xiaomi Gateway SmartThings Edge Driver**.

These files are not required for the SmartThings Edge Driver itself to run. They are intended for use on an administration PC when configuring an openmiio/MQTT BLE path on a Xiaomi `mgl03` Gateway or when directly inspecting BLE events arriving through MQTT.

> Most SmartThings users do not need to install these tools. Use them only when you need to configure BLE over MQTT yourself or diagnose related problems.

---

## Included files

| File | Purpose |
|---|---|
| [`install-openmiio-mgl03-v5.py`](install-openmiio-mgl03-v5.py) | Installs `openmiio_agent` on an `mgl03` with Telnet already enabled and starts the MQTT/BLE-related modules |
| [`mqtt-ble-probe-v2.py`](mqtt-ble-probe-v2.py) | Connects to an MQTT Broker, receives Xiaomi `_async.ble_event` messages, and displays BLE events |
| [`OPENMIIO-SETUP.en.md`](OPENMIIO-SETUP.en.md) | mgl03 openmiio/MQTT setup procedure, SmartThings configuration, and troubleshooting guide |
| [`SHA256SUMS.txt`](SHA256SUMS.txt) | SHA-256 list for checking tool-file integrity |

---

## Target environment

The current openmiio installation procedure is intended for the following environment:

| Item | Verified environment |
|---|---|
| Xiaomi internal model | `lumi.gateway.mgl03` |
| Gateway family | Xiaomi Mijia Smart Multi-Mode Gateway |
| Verified firmware family | `1.5.0.x` |
| CPU / binary | MIPS / `openmiio_agent_mips` |
| Telnet | TCP `23` |
| MQTT | TCP `1883` |

`install-openmiio-mgl03-v5.py` is an **mgl03-specific tool**. Do not use it unchanged on `mgl001` or on Xiaomi Gateways with a different architecture.

---

## Overall architecture

```text
Xiaomi BLE device
      ↓
Xiaomi Gateway (mgl03)
      ↓
openmiio_agent
      ↓
Mosquitto / MQTT :1883
      ↓
miio/report / central/report
      ↓
Xiaomi Gateway SmartThings Edge Driver
      ↓
SmartThings EDGE_CHILD
```

The SmartThings Edge Driver subscribes to MQTT topic `#` and processes supported BLE events.

---

## Requirements

The administration PC needs the following:

- Python 3
- Access to the same LAN as the Xiaomi Gateway, or another management network that can reach it
- Access to Telnet TCP `23` on the target mgl03
- Access to MQTT TCP `1883` after installation
- Internet access
  - Required while the installer downloads the `openmiio_agent` MIPS v1.2.1 binary

The installer itself does not ask for a Xiaomi account password, miIO TOKEN, BLE KEY, or Gateway Key.

---

## 1. Set the Gateway address

PowerShell example:

```powershell
$GatewayIP = "192.168.1.41"
```

Replace `$GatewayIP` in the commands below with the actual IP address of your mgl03.

---

## 2. Check Telnet

Telnet must already be open before installing openmiio.

```powershell
Test-NetConnection $GatewayIP -Port 23
```

Expected result:

```text
TcpTestSucceeded : True
```

If it is `False`, do not run the installer yet. First make sure Telnet can be used on the mgl03.

---

## 3. Install and start openmiio

Run the following command from this directory:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP
```

The script performs the following steps:

1. Checks Telnet TCP `23`
2. Downloads `openmiio_agent` MIPS v1.2.1
3. Verifies the MD5 of the downloaded binary
4. Logs in to the mgl03 Telnet shell
5. Checks Gateway information
6. Checks whether `openmiio_agent` is already running
7. Uploads it to `/data/openmiio_agent` if needed
8. Verifies the MD5 of the remote binary
9. Applies executable permissions
10. Starts the `miio mqtt cache central` modules
11. Checks whether MQTT TCP `1883` is reachable

By default, the script does not replace or restart an already running `openmiio_agent` process.

To intentionally restart the existing process:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP --force-restart
```

Use `--force-restart` only when necessary because it can stop the currently running openmiio process.

### Main options

```text
--gateway-ip     Gateway IP
--telnet-port    Telnet port, default 23
--mqtt-port      MQTT port, default 1883
--force-restart  stop the existing openmiio_agent and start it again
```

---

## 4. Check the MQTT Broker

After installation:

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

Expected result:

```text
TcpTestSucceeded : True
```

The openmiio log inside the Gateway is written to:

```text
/var/log/st-openmiio.log
```

---

## 5. Inspect BLE MQTT events

If MQTT is reachable, run the probe:

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

The probe reconnects if the connection is lost and searches for Xiaomi `_async.ble_event` messages.

To stop it:

```text
Ctrl+C
```

### BLE temperature/humidity events currently decoded by the probe

| Item | EID | Data format |
|---|---:|---|
| Temperature | `19457` / `0x4C01` | little-endian float32 |
| Humidity | `19458` / `0x4C02` | uint8 |
| Battery | `18435` / `0x4803` | uint8 |

Unsupported EIDs are still printed with their raw `eid` and `edata`, which is useful when analyzing new BLE devices.

---

## 6. SmartThings configuration

After openmiio/MQTT is running correctly on the mgl03, open the corresponding Xiaomi Gateway settings in SmartThings and configure:

```text
BLE via MQTT        = On
BLE MQTT broker IP  = blank
BLE MQTT port       = 1883
```

If `BLE MQTT broker IP` is left blank, the Edge Driver uses that Gateway's `IP address` as the MQTT Broker address.

If the MQTT Broker is running on another device, enter that device's IP address instead.

---

## Recommended verification order

```text
Telnet :23 reachable
      ↓
openmiio_agent installed/running
      ↓
MQTT :1883 reachable
      ↓
mqtt-ble-probe-v2.py receives BLE events
      ↓
SmartThings BLE via MQTT = On
      ↓
Supported BLE device is created as EDGE_CHILD
      ↓
Temperature/Humidity/Battery or T700i events update
```

When something fails, checking the chain in this order is usually the fastest way to find where the path is broken.

---

## Installer exit codes

The main exit codes from `install-openmiio-mgl03-v5.py` are:

| Code | Meaning |
|---:|---|
| `0` | openmiio started and the MQTT port was confirmed reachable |
| `1` | installation, connection, or verification error |
| `2` | openmiio start was attempted, but the MQTT port could not be reached |
| `3` | an existing `openmiio_agent` was detected and the script stopped because `--force-restart` was not used |

---

## After a Gateway reboot

The current helper starts openmiio as a **runtime process**.

After rebooting the mgl03, first check whether MQTT TCP `1883` is still open:

```powershell
Test-NetConnection $GatewayIP -Port 1883
```

If the port is closed:

```powershell
py .\install-openmiio-mgl03-v5.py --gateway-ip $GatewayIP --force-restart
```

---

## File integrity check

For example, in PowerShell:

```powershell
Get-FileHash .\install-openmiio-mgl03-v5.py -Algorithm SHA256
Get-FileHash .\mqtt-ble-probe-v2.py -Algorithm SHA256
```

Compare the results with [`SHA256SUMS.txt`](SHA256SUMS.txt).

---

## Security notes

- Do not expose Telnet TCP `23` to the Internet.
- Do not expose unauthenticated MQTT TCP `1883` to the Internet.
- Perform administration only inside a trusted LAN/VLAN.
- Do not put Gateway TOKENs, BLE KEYs, Gateway Keys, or Xiaomi account information in code or GitHub Issues.
- Check shared logs for sensitive information before posting them.

---

## Troubleshooting

For detailed installation steps and issue-specific checks, see:

[`OPENMIIO-SETUP.en.md`](OPENMIIO-SETUP.en.md)

A typical troubleshooting sequence is:

```text
Telnet 23
  ↓
openmiio_agent
  ↓
MQTT 1883
  ↓
mqtt-ble-probe
  ↓
SmartThings BLE via MQTT
```

---

## Notes

These tools are **optional administration tools** for `xiaomi-gateway-edge-driver` and do not need to be part of the SmartThings Edge Lua runtime or Device Profiles.

For normal driver installation and configuration, see the parent repository's [`README.en.md`](../README.en.md).
