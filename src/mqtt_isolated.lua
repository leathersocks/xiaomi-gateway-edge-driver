local st_thread = require "st.thread"
local log = require "log"

local mqtt_ble = require "mqtt_ble"

local mqtt_isolated = {}

-- mqtt_ble.lua intentionally keeps its existing source.thread scheduling API.
-- This adapter presents the real Gateway device through a proxy whose only
-- overridden property is `thread`. Long-running MQTT receive/reconnect work
-- therefore runs on a dedicated SmartThings Thread instead of occupying the
-- Gateway device thread that owns lifecycle events and miIO health timers.
local CONTEXTS = {}

local function device_key(device)
  return tostring(
    device and
    (device.id or device.device_network_id or device.label) or
    "gateway"
  )
end

local function mqtt_enabled(device)
  return device and
    device.preferences and
    device.preferences.bleMqttEnabled == true
end

local function make_proxy(device, thread)
  return setmetatable({}, {
    __index = function(_, key)
      if key == "thread" then
        return thread
      end

      local value = device[key]

      if type(value) == "function" then
        return function(_, ...)
          return value(device, ...)
        end
      end

      return value
    end,

    __newindex = function(_, key, value)
      device[key] = value
    end,
  })
end

local function get_context(driver, device)
  local key = device_key(device)
  local context = CONTEXTS[key]

  if context then
    return context
  end

  local suffix = key:gsub("[^%w]", ""):sub(-8)
  local thread = st_thread.Thread(
    driver,
    "xiaomi BLE MQTT " .. (suffix ~= "" and suffix or "gateway")
  )

  context = {
    device = device,
    thread = thread,
    proxy = nil,
  }
  context.proxy = make_proxy(device, thread)
  CONTEXTS[key] = context

  log.info(string.format(
    "%s BLE MQTT dedicated thread created: device_thread_isolated=true",
    tostring(device.label or device.id or "Xiaomi Gateway")
  ))

  return context
end

local function existing_context(device)
  return CONTEXTS[device_key(device)]
end

function mqtt_isolated.status(device)
  local context = existing_context(device)
  return mqtt_ble.status(context and context.proxy or device)
end

function mqtt_isolated.start(driver, device, reason)
  local context = existing_context(device)

  -- A disabled Gateway never starts the long-running MQTT listener, so there
  -- is no reason to allocate a separate thread until BLE via MQTT is enabled.
  if not context and not mqtt_enabled(device) then
    return mqtt_ble.start(driver, device, reason)
  end

  context = context or get_context(driver, device)
  return mqtt_ble.start(driver, context.proxy, reason)
end

function mqtt_isolated.restart(driver, device, reason)
  local context = existing_context(device)

  if not context and not mqtt_enabled(device) then
    return mqtt_ble.restart(driver, device, reason)
  end

  context = context or get_context(driver, device)
  return mqtt_ble.restart(driver, context.proxy, reason)
end

function mqtt_isolated.stop(device, reason)
  local key = device_key(device)
  local context = CONTEXTS[key]
  local result = mqtt_ble.stop(
    context and context.proxy or device,
    reason
  )

  if context and tostring(reason or "") == "removed" then
    pcall(function()
      context.thread:close()
    end)
    CONTEXTS[key] = nil

    log.info(string.format(
      "%s BLE MQTT dedicated thread closed: source=removed",
      tostring(device.label or device.id or "Xiaomi Gateway")
    ))
  end

  return result
end

return mqtt_isolated
