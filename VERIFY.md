# v1.8.2 Verification

Runtime source must not contain:

```text
gateway_for_device
knownBleChildren
find_ble_host
BLE_HOST_MODEL
require "gateways"
require "known_ble"
```

Expected settings:

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

Expected MQTT when enabled:

```text
BLE MQTT start requested ... enabled=true
BLE MQTT listener scheduled
BLE MQTT TCP connected
BLE MQTT CONNACK OK
BLE MQTT SUBACK OK
BLE MQTT connected
BLE MQTT PINGREQ sent
BLE MQTT PINGRESP OK
```

Expected MQTT when disabled:

```text
BLE MQTT start requested ... enabled=false
BLE MQTT disabled by preference
```

Expected BLE:

```text
BLE MQTT PUBLISH matched BLE event
BLE MQTT state OK
```
