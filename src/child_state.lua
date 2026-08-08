local capabilities = require "st.capabilities"
local log = require "log"

local miio_rpc = require "miio_rpc"

local child_state = {}

local INVENTORY_FIELD = "xiaomi_gateway_child_inventory"
local BLE_NOTICE_FIELD = "xiaomi_ble_state_notice"

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

function child_state.enabled(parent)
  if not parent.preferences then
    return false
  end

  local value = parent.preferences.childStatePolling
  if value == nil then
    return false
  end

  return value == true
end

function child_state.interval(parent)
  local value = 60

  if parent.preferences then
    value = tonumber(parent.preferences.childPollInterval) or 60
  end

  if value < 30 then
    return 30
  elseif value > 3600 then
    return 3600
  end

  return value
end

local function gateway_ip(parent)
  if not parent.preferences then
    return ""
  end

  return trim(parent.preferences.gatewayIp)
end

local function gateway_token(parent)
  if not parent.preferences then
    return ""
  end

  return trim(parent.preferences.gatewayToken)
end

local function timeout(parent)
  return 3
end

local function is_ble_definition(definition)
  local did = trim(definition and definition.did or "")
  local key = trim(definition and definition.key or "")

  return
    did:match("^blt%.") ~= nil or
    key:match("^ble%-") ~= nil
end

local function weather_properties(model, child_type)
  model = trim(model):lower()
  child_type = trim(child_type):lower()

  if model == "lumi.weather.v1" then
    return {
      "temperature",
      "humidity",
      "pressure",
    }
  end

  if model == "lumi.sensor_ht.v1" then
    return {
      "temperature",
      "humidity",
    }
  end

  if child_type == "temp-humidity" and
     model:match("^lumi%.") then
    return {
      "temperature",
      "humidity",
    }
  end

  return nil
end

local function response_values(result)
  if type(result) ~= "table" then
    return nil
  end

  -- python-miio's get_property_exp() sends:
  --   get_device_prop_exp [[sid, prop1, prop2, ...]]
  -- and then pops the last inner result list.
  if type(result[1]) == "table" then
    return result[#result]
  end

  return result
end

local function round(value, digits)
  local multiplier = 10 ^ (digits or 0)
  if value >= 0 then
    return math.floor((value * multiplier) + 0.5) / multiplier
  end
  return math.ceil((value * multiplier) - 0.5) / multiplier
end

local function emit_temperature(child, raw)
  local numeric = tonumber(raw)
  if not numeric then
    return false
  end

  local celsius = numeric / 100
  if celsius < -100 or celsius > 200 then
    return false
  end

  if child:supports_capability(capabilities.temperatureMeasurement) then
    child:emit_event(
      capabilities.temperatureMeasurement.temperature({
        value = round(celsius, 2),
        unit = "C",
      })
    )
    return true
  end

  return false
end

local function emit_humidity(child, raw)
  local numeric = tonumber(raw)
  if not numeric then
    return false
  end

  local percent = numeric / 100
  if percent < 0 or percent > 100 then
    return false
  end

  if child:supports_capability(
       capabilities.relativeHumidityMeasurement
     ) then
    child:emit_event(
      capabilities.relativeHumidityMeasurement.humidity(
        round(percent, 1)
      )
    )
    return true
  end

  return false
end

local function poll_weather(parent, child, definition, ip, token)
  local properties =
    weather_properties(definition.model, definition.type)

  if not properties then
    return {
      supported = false,
    }
  end

  local request = { definition.did }
  for _, property in ipairs(properties) do
    request[#request + 1] = property
  end

  local ok, response = miio_rpc.call(
    ip,
    token,
    "get_device_prop_exp",
    { request },
    timeout(parent)
  )

  if not ok then
    log.warn(string.format(
      "%s child state poll failed: did=%s model=%s method=get_device_prop_exp reason=%s",
      parent.label,
      tostring(definition.did or ""),
      tostring(definition.model or ""),
      tostring(response and response.reason or "unknown")
    ))

    return {
      supported = true,
      ok = false,
      reason = response and response.reason or "RPC failed",
    }
  end

  local values = response_values(response.result)
  if not values then
    log.warn(string.format(
      "%s child state poll returned no values: did=%s model=%s",
      parent.label,
      tostring(definition.did or ""),
      tostring(definition.model or "")
    ))

    return {
      supported = true,
      ok = false,
      reason = "empty property response",
    }
  end

  local emitted_temperature = emit_temperature(child, values[1])
  local emitted_humidity = emit_humidity(child, values[2])

  local pressure = nil
  if properties[3] == "pressure" and tonumber(values[3]) then
    pressure = tonumber(values[3]) / 100
  end

  child:online()
  if child:supports_capability(capabilities.presenceSensor) then
    child:emit_event(
      capabilities.presenceSensor.presence("present")
    )
  end

  log.info(string.format(
    "%s child state OK: label=%s did=%s model=%s temperature=%sC humidity=%s%% pressure=%s",
    parent.label,
    child.label,
    tostring(definition.did or ""),
    tostring(definition.model or ""),
    emitted_temperature and tostring(
      round((tonumber(values[1]) or 0) / 100, 2)
    ) or "-",
    emitted_humidity and tostring(
      round((tonumber(values[2]) or 0) / 100, 1)
    ) or "-",
    pressure and tostring(round(pressure, 2)) or "-"
  ))

  return {
    supported = true,
    ok = true,
    temperature = emitted_temperature,
    humidity = emitted_humidity,
    pressure = pressure,
  }
end

function child_state.poll(parent, source)
  if not child_state.enabled(parent) then
    return {
      enabled = false,
    }
  end

  local inventory = parent:get_field(INVENTORY_FIELD)
  if type(inventory) ~= "table" or #inventory == 0 then
    return {
      enabled = true,
      inventory = 0,
    }
  end

  local ip = gateway_ip(parent)
  local token = gateway_token(parent)

  if ip == "" or not miio_rpc.valid_token_hex(token) then
    return {
      enabled = true,
      inventory = #inventory,
      polled = 0,
      reason = "gateway IP/token is not configured",
    }
  end

  local polled = 0
  local succeeded = 0
  local skipped = 0

  for _, definition in ipairs(inventory) do
    if is_ble_definition(definition) then
      skipped = skipped + 1

      if not parent:get_field(BLE_NOTICE_FIELD) then
        parent:set_field(BLE_NOTICE_FIELD, true, { persist = false })
        log.info(string.format(
          "%s BLE child values are not polled through stock miIO; registration remains active",
          parent.label
        ))
      end
    else
      local child =
        parent:get_child_by_parent_assigned_key(definition.key)

      if child then
        local result =
          poll_weather(
            parent,
            child,
            definition,
            ip,
            token
          )

        if result.supported then
          polled = polled + 1
          if result.ok then
            succeeded = succeeded + 1
          end
        else
          skipped = skipped + 1
        end
      else
        -- try_create_device is asynchronous; the child may not yet exist
        -- during the same discovery pass that created it.
        skipped = skipped + 1
      end
    end
  end

  log.info(string.format(
    "%s child state poll complete: source=%s inventory=%d polled=%d succeeded=%d skipped=%d",
    parent.label,
    tostring(source or "unknown"),
    #inventory,
    polled,
    succeeded,
    skipped
  ))

  return {
    enabled = true,
    inventory = #inventory,
    polled = polled,
    succeeded = succeeded,
    skipped = skipped,
  }
end

return child_state
