local gateway_runtime = {}

local GATEWAY_DNI_PREFIX = "xiaomi-gateway-"
local MIIO_REACHABLE_FIELD = "xiaomi_gateway_miio_reachable"
local MQTT_STATE_FIELD = "xiaomi_ble_mqtt_state"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

function gateway_runtime.is_gateway(device)
  if not device then
    return false
  end

  local dni = trim(device.device_network_id)
  return dni:sub(1, #GATEWAY_DNI_PREFIX) == GATEWAY_DNI_PREFIX
end

function gateway_runtime.gateway_ip(device)
  if not device or not device.preferences then
    return ""
  end

  return trim(device.preferences.gatewayIp)
end

function gateway_runtime.mqtt_enabled(device)
  if not device or not device.preferences then
    return false
  end

  return device.preferences.bleMqttEnabled == true
end

function gateway_runtime.set_miio_reachable(device, reachable)
  device:set_field(
    MIIO_REACHABLE_FIELD,
    reachable == true,
    { persist = false }
  )
end

function gateway_runtime.miio_reachable(device)
  return device and device:get_field(MIIO_REACHABLE_FIELD) == true
end

function gateway_runtime.set_mqtt_state(device, state)
  device:set_field(
    MQTT_STATE_FIELD,
    tostring(state or "unknown"),
    { persist = false }
  )
end

function gateway_runtime.mqtt_state(device)
  if not device then
    return "never-started"
  end

  local value = device:get_field(MQTT_STATE_FIELD)
  return value == nil and "never-started" or tostring(value)
end

function gateway_runtime.mqtt_reachable(device)
  return gateway_runtime.mqtt_enabled(device) and
    gateway_runtime.mqtt_state(device) == "subscribed"
end

function gateway_runtime.is_reachable(device)
  return gateway_runtime.miio_reachable(device) or
    gateway_runtime.mqtt_reachable(device)
end

function gateway_runtime.apply_connectivity(device)
  if gateway_runtime.is_reachable(device) then
    device:online()
    return true
  end

  device:offline()
  return false
end

function gateway_runtime.role_summary(device)
  local roles = {}

  if gateway_runtime.mqtt_enabled(device) then
    roles[#roles + 1] = "mqtt-receiver"
  end

  if device.preferences and device.preferences.autoChildDiscovery == true then
    roles[#roles + 1] = "child-discovery"
  end

  if device.preferences and device.preferences.childStatePolling == true then
    roles[#roles + 1] = "zigbee-poll"
  end

  if #roles == 0 then
    return "status-only"
  end

  return table.concat(roles, "+")
end

return gateway_runtime
