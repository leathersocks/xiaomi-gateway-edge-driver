local gateway_runtime = {}

local GATEWAY_DNI_PREFIX = "xiaomi-gateway-"

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
