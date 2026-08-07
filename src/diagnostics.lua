local capabilities = require "st.capabilities"
local log = require "log"

local capability_ids = require "generated_capabilities"
local diagnostics = {}

local FIELD_DEVICE_ID = "xiaomi_gateway_device_id"
local FIELD_LATENCY_MS = "xiaomi_gateway_latency_ms"
local FIELD_LAST_SEEN = "xiaomi_gateway_last_seen"
local FIELD_FAILURE_COUNT = "xiaomi_gateway_failure_count"
local FIELD_GATEWAY_STATUS = "xiaomi_gateway_status"

local caps = {}

if capability_ids ~= nil then
  for key, capability_id in pairs(capability_ids) do
    if capability_id ~= nil and capability_id ~= "" then
      caps[key] = capabilities[capability_id]
    end
  end
end

local function set_persistent(device, key, value)
  device:set_field(key, value, { persist = true })
end

local function emit_cap(device, cap_key, attribute, value)
  local cap = caps[cap_key]
  if cap == nil then
    log.warn(string.format(
      "%s diagnostics capability '%s' is not available",
      device.label,
      tostring(cap_key)
    ))
    return
  end

  local constructor = cap[attribute]
  if constructor == nil then
    log.warn(string.format(
      "%s diagnostics attribute '%s.%s' is not available",
      device.label,
      tostring(cap_key),
      tostring(attribute)
    ))
    return
  end

  device:emit_event(constructor(value))
end

function diagnostics.enabled()
  return next(caps) ~= nil
end

function diagnostics.failure_count(device)
  return tonumber(device:get_field(FIELD_FAILURE_COUNT)) or 0
end

function diagnostics.record_success(device, ip, result, last_seen)
  local device_id = tostring(result.device_id or "")
  local latency_ms = math.max(0, math.floor(tonumber(result.latency_ms) or 0))

  set_persistent(device, FIELD_DEVICE_ID, device_id)
  set_persistent(device, FIELD_LATENCY_MS, latency_ms)
  set_persistent(device, FIELD_LAST_SEEN, tostring(last_seen or ""))
  set_persistent(device, FIELD_FAILURE_COUNT, 0)
  set_persistent(device, FIELD_GATEWAY_STATUS, "online")

  emit_cap(device, "status", "gatewayStatus", "online")
  emit_cap(device, "ip", "gatewayIp", tostring(ip or ""))
  emit_cap(device, "latency", "latencyMs", latency_ms)
  emit_cap(device, "lastSeen", "lastSeen", tostring(last_seen or ""))
  emit_cap(device, "failures", "failureCount", 0)
end

function diagnostics.record_failure(device, ip, threshold)
  local failures = diagnostics.failure_count(device) + 1
  local status = "degraded"

  if threshold ~= nil and failures >= tonumber(threshold) then
    status = "offline"
  end

  set_persistent(device, FIELD_FAILURE_COUNT, failures)
  set_persistent(device, FIELD_GATEWAY_STATUS, status)

  emit_cap(device, "status", "gatewayStatus", status)
  emit_cap(device, "ip", "gatewayIp", tostring(ip or ""))
  emit_cap(device, "failures", "failureCount", failures)

  local latency_ms = tonumber(device:get_field(FIELD_LATENCY_MS))
  if latency_ms ~= nil then
    emit_cap(device, "latency", "latencyMs", latency_ms)
  end

  local last_seen = device:get_field(FIELD_LAST_SEEN)
  if last_seen ~= nil then
    emit_cap(device, "lastSeen", "lastSeen", tostring(last_seen))
  end

  return failures
end

function diagnostics.emit_cached(device, ip)
  local latency_ms = device:get_field(FIELD_LATENCY_MS)
  local last_seen = device:get_field(FIELD_LAST_SEEN)
  local failure_count = diagnostics.failure_count(device)
  local status = device:get_field(FIELD_GATEWAY_STATUS) or "offline"

  emit_cap(device, "status", "gatewayStatus", tostring(status))
  emit_cap(device, "ip", "gatewayIp", tostring(ip or ""))

  if latency_ms ~= nil then
    emit_cap(device, "latency", "latencyMs", tonumber(latency_ms) or 0)
  end
  if last_seen ~= nil then
    emit_cap(device, "lastSeen", "lastSeen", tostring(last_seen))
  end

  emit_cap(device, "failures", "failureCount", failure_count)
end

return diagnostics
