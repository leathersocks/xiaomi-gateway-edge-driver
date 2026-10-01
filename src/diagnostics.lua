local capabilities = require "st.capabilities"
local log = require "log"

local capability_ids = require "generated_capabilities"
local device_summary = require "device_summary"
local diagnostics = {}

local FIELD_DEVICE_ID = "xiaomi_gateway_device_id"
local FIELD_LATENCY_MS = "xiaomi_gateway_latency_ms"
local FIELD_LAST_SEEN = "xiaomi_gateway_last_seen"
local FIELD_FAILURE_COUNT = "xiaomi_gateway_failure_count"
local FIELD_GATEWAY_STATUS = "xiaomi_gateway_status"
local FIELD_CONNECTED_DEVICE_COUNT = "xiaomi_gateway_connected_device_count"
local FIELD_CONNECTED_DEVICES = "xiaomi_gateway_connected_devices"

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
  local value = device:get_field(FIELD_FAILURE_COUNT)
  if value == nil then
    return 0
  end
  return tonumber(value) or 0
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
end

function diagnostics.record_failure(device, ip, threshold, fallback_reachable)
  local failures = diagnostics.failure_count(device) + 1
  local status = "degraded"

  if threshold ~= nil and failures >= tonumber(threshold) and
     fallback_reachable ~= true then
    status = "offline"
  end

  set_persistent(device, FIELD_FAILURE_COUNT, failures)
  set_persistent(device, FIELD_GATEWAY_STATUS, status)

  emit_cap(device, "status", "gatewayStatus", status)

  return failures
end

function diagnostics.emit_connected_devices(device, excluded_child_id)
  local summary = device_summary.build(
    device:get_child_list() or {},
    excluded_child_id,
    512
  )

  set_persistent(device, FIELD_CONNECTED_DEVICE_COUNT, summary.count)
  set_persistent(device, FIELD_CONNECTED_DEVICES, summary.text)

  emit_cap(
    device,
    "devices",
    "connectedDeviceCount",
    summary.count
  )
  emit_cap(
    device,
    "devices",
    "connectedDevices",
    summary.text
  )

  log.info(string.format(
    "%s connected device summary updated: count=%d devices=%s",
    tostring(device.label or device.id),
    summary.count,
    summary.text
  ))

  return summary
end

function diagnostics.emit_cached(device, ip)
  local value = device:get_field(FIELD_GATEWAY_STATUS)
  local status = value == nil and "offline" or tostring(value)

  emit_cap(device, "status", "gatewayStatus", status)
  diagnostics.emit_connected_devices(device)
end

return diagnostics
